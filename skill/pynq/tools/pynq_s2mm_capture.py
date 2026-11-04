#!/usr/bin/env python3
"""PYNQ simple-S2MM fixed-frame capture, with bounded status polling.

The CLI is a reusable implementation derived from the RS555 Notebook procedure.
The included Notebook is the record of the actual board run; do not confuse it
with a separate on-board acceptance test of this CLI.
"""
from __future__ import annotations
import argparse
import time
from pathlib import Path

RX_CTRL = 0x30
RX_STATUS = 0x34
DMA_RESET = 0x4
DMA_HALTED = 0x1
DMA_IDLE = 0x2
DMA_ERR_MASK = 0x70
DMA_IOC = 0x1000


def validate_metadata(ip: dict, frame_bytes: int) -> tuple[int, int]:
    if frame_bytes <= 0 or frame_bytes % 4:
        raise ValueError('frame length must be a positive multiple of four')
    params = ip.get('parameters', {})
    def param(key):
        v = params.get(key, params.get(key.lower()))
        if v is None:
            raise ValueError(f'Missing DMA metadata parameter {key}')
        return int(str(v), 0)
    if param('C_INCLUDE_SG') != 0 or param('C_INCLUDE_S2MM') != 1:
        raise ValueError('Example requires simple DMA with S2MM enabled')
    if param('C_INCLUDE_MM2S') != 0:
        # MM2S may coexist in other designs, but this example exercises S2MM only.
        print('NOTE: MM2S present, S2MM used here')
    width = param('C_SG_LENGTH_WIDTH')
    if width <= 0 or width >= 32:
        raise ValueError('Unsupported DMA length width')
    max_bytes = (1 << width) - 1
    if frame_bytes > max_bytes:
        raise ValueError(f'Frame {frame_bytes} exceeds DMA length limit {max_bytes}')
    return width, max_bytes


def receive(overlay, dma_name: str, words: int, timeout_s: float):
    from pynq import allocate, MMIO
    import numpy as np

    if not overlay.is_loaded():
        raise ValueError('Overlay is not currently loaded')
    if words <= 0 or timeout_s <= 0:
        raise ValueError('words and timeout_s must be positive')
    ip = overlay.ip_dict.get(dma_name)
    if not ip:
        raise ValueError(f'Missing DMA instance: {dma_name}')
    width, max_bytes = validate_metadata(ip, words*4)
    dma = getattr(overlay, dma_name)
    if not hasattr(dma, 'recvchannel'):
        raise ValueError('No recvchannel; incompatible DMA or driver')
    if words*4 > dma.buffer_max_size:
        raise ValueError('Requested transfer exceeds PYNQ DMA driver limit')
    mmio = MMIO(ip['phys_addr'], ip['addr_range'])
    rx = dma.recvchannel
    buf = allocate(shape=(words,), dtype=np.uint32)
    transfer_started = False
    safe_to_free = True
    try:
        buf[:] = 0
        buf.flush()
        rx.transfer(buf)
        transfer_started = True
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            sr = mmio.read(RX_STATUS)
            if sr & DMA_ERR_MASK:
                raise RuntimeError(f'S2MM error in DMASR: 0x{sr:08x}')
            # The reference RS555 board run completed with 0x1002 (IOC and Idle).
            if (sr & (DMA_IDLE | DMA_IOC)) == (DMA_IDLE | DMA_IOC):
                rx.wait()  # Called only after observing completion in DMASR.
                buf.invalidate()
                output = np.array(buf, dtype=np.uint32, copy=True)
                return output, sr, rx.transferred
            time.sleep(0.01)
        raise TimeoutError(f'S2MM not complete after {timeout_s:.3g}s; DMASR=0x{mmio.read(RX_STATUS):08x}')
    except Exception:
        if transfer_started:
            # A failed transfer must be stopped before unpinning its DDR target.
            mmio.write(RX_CTRL, DMA_RESET)
            safe_to_free = False
            reset_deadline = time.monotonic() + 1.0
            while time.monotonic() < reset_deadline:
                if not (mmio.read(RX_CTRL) & DMA_RESET) and (mmio.read(RX_STATUS) & DMA_HALTED):
                    safe_to_free = True
                    break
                time.sleep(0.01)
        raise
    finally:
        if safe_to_free:
            buf.freebuffer()
        else:
            # Preserve the buffer reference in this running Python process.
            # Reset/repower hardware before any further DMA tests. A process
            # exit cannot be assumed to stop an active hardware DMA engine.
            _unrecovered_buffers.append(buf)
            print('WARNING: DMA reset not confirmed. Do not retry or exit until hardware is safely reset.')

_unrecovered_buffers = []


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description='Bounded PYNQ simple DMA S2MM fixed-frame capture')
    p.add_argument('--bit', required=True, type=Path)
    p.add_argument('--dma', required=True)
    p.add_argument('--words', required=True, type=int)
    p.add_argument('--timeout', type=float, default=3.0)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--download', action='store_true')
    p.add_argument('--ack-safe', action='store_true')
    a = p.parse_args(argv)
    if not a.ack_safe or not a.download:
        p.error('Requires --ack-safe and --download after physically isolating actuators')
    if not a.bit.is_file() or not a.bit.with_suffix('.hwh').is_file():
        p.error('Require a same-stem BIT and HWH from the intended hardware build')
    if a.words <= 0 or a.timeout <= 0:
        p.error('--words and --timeout must be positive')
    try:
        from pynq import Overlay
        import numpy as np
    except ImportError as exc:
        p.error(f'PYNQ/Linux/NumPy required: {exc}')
    # Parse and preflight parameters BEFORE any PL reconfiguration.
    overlay = Overlay(str(a.bit.resolve()), download=False)
    ip = overlay.ip_dict.get(a.dma)
    if ip is None:
        p.error(f'Unknown DMA IP: {a.dma}')
    try:
        width, max_bytes = validate_metadata(ip, a.words * 4)
    except ValueError as exc:
        p.error(str(exc))
    print(f'Metadata: S2MM length width={width}, max_bytes={max_bytes}; programming PL.')
    overlay.download()
    result, status, transferred = receive(overlay, a.dma, a.words, a.timeout)
    if transferred != a.words * 4:
        raise RuntimeError(f'Incomplete transfer: {transferred} != {a.words*4}')
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_bytes(np.asarray(result, dtype='<u4').tobytes())
    print(f'DMASR=0x{status:08x}, transferred={transferred}, nonzero={np.count_nonzero(result)}')
    print(f'Saved: {a.out}')
    print('No audio fidelity conclusion is implied by a successful DMA transfer.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

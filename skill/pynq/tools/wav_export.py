#!/usr/bin/env python3
"""Export packed 2x16-bit little-endian PCM to a 2-channel WAV file (stdlib)."""
from __future__ import annotations
import argparse
from pathlib import Path
import wave


def main(argv=None):
    p = argparse.ArgumentParser(description='Create stereo PCM16 WAV from packed uint32 DMA bytes')
    p.add_argument('input', type=Path)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--rate', type=int, default=16000, help='nominal sample rate')
    a = p.parse_args(argv)
    if a.rate <= 0:
        p.error('rate must be positive')
    try:
        raw = a.input.read_bytes()
        if not raw or len(raw) % 4:
            p.error('input must contain complete, nonempty 4-byte stereo frames')
        # The 32-bit packed word {B[15:0], A[15:0]} is little-endian on Zynq,
        # so its 4 bytes already encode interleaved A,B 16-bit signed samples.
        a.out.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(a.out), 'wb') as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(a.rate)
            f.writeframes(raw)
        print(f'Saved {a.out} ({len(raw)//4} stereo frames at nominal {a.rate} Hz)')
    except OSError as exc:
        p.error(str(exc))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

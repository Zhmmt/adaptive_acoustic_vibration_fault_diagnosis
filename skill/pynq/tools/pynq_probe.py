#!/usr/bin/env python3
"""PYNQ-side overlay IP/register-map metadata inspection, with no AXI register writes."""
from __future__ import annotations
import argparse
from pathlib import Path


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description='Inspect a PYNQ Overlay metadata/IP map without writing peripherals')
    p.add_argument('--bit', type=Path, required=True, help='bit/hwh pair with same stem')
    p.add_argument('--ip', help='optional IP instance name to display register_map')
    p.add_argument('--download', action='store_true', help='EXPLICITLY program FPGA (may reset hardware)')
    p.add_argument('--register-map', action='store_true', help='read and display live register_map, requires --ip and --download')
    a = p.parse_args(argv)
    if not a.bit.is_file() or not a.bit.with_suffix('.hwh').is_file():
        p.error('Both BIT and HWH must exist with the same file stem')
    try:
        from pynq import Overlay
    except ImportError as exc:
        p.error(f'Requires a PYNQ Linux environment: {exc}')
    if a.register_map and (not a.ip or not a.download):
        p.error('--register-map requires both --ip and --download; reads may have device side effects')
    if a.download:
        print('Programming FPGA: ensure externally powered actuators are isolated.')
    overlay = Overlay(str(a.bit), download=a.download)
    for name, info in sorted(overlay.ip_dict.items()):
        addr = info.get('phys_addr')
        addr_text = hex(addr) if addr is not None else 'NO_MMIO_ADDRESS'
        print(f'{name:32} {info.get("type", "?"):32} {addr_text:20} {info.get("addr_range", 0):#x}')
    if a.ip:
        if a.ip not in overlay.ip_dict:
            p.error(f'IP missing from loaded metadata: {a.ip}')
        print('Selected IP metadata:', a.ip, overlay.ip_dict[a.ip])
        if a.register_map:
            device = getattr(overlay, a.ip, None)
            if device is None:
                p.error(f'IP is listed but not directly accessible by attribute: {a.ip}')
            print('Reading live register_map; some hardware registers can have read side effects.')
            try:
                print(device.register_map)
            except AttributeError:
                print('This IP/driver exposes no register_map. Consult the IP product guide.')
    print('No AXI register writes requested by this tool.')
    if not a.download:
        print('Metadata only: does NOT establish which bitstream is currently programmed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

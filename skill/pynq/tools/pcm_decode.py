#!/usr/bin/env python3
"""Portable decoder for little-endian 32-bit words containing two signed 16-bit channels."""
from __future__ import annotations
import argparse
import csv
from pathlib import Path
import struct


def decode_words(raw: bytes, order: str = 'ab') -> list[tuple[int, int]]:
    if len(raw) % 4:
        raise ValueError('Packed stream size must be a multiple of four bytes')
    if order not in ('ab', 'ba'):
        raise ValueError('order must be ab or ba')
    result = []
    for low, high in struct.iter_unpack('<hh', raw):
        result.append((low, high) if order == 'ab' else (high, low))
    return result


def channel_summary(values: list[int]) -> dict:
    if not values:
        return {'count': 0, 'peak_abs': 0, 'mean_abs': 0.0, 'min': None, 'max': None}
    return {'count': len(values), 'peak_abs': max(abs(v) for v in values),
            'mean_abs': sum(abs(v) for v in values)/len(values), 'min': min(values), 'max': max(values)}


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description='Decode packed stereo PCM captured using an AXI DMA S2MM sample')
    p.add_argument('input', type=Path)
    p.add_argument('--out', required=True, type=Path, help='output CSV')
    p.add_argument('--order', choices=['ab', 'ba'], default='ab', help='ab: low16=A, high16=B')
    p.add_argument('--rate', type=float, default=16000., help='Hz, for CSV time axis only')
    a = p.parse_args(argv)
    if a.rate <= 0:
        p.error('--rate must be positive')
    try:
        samples = decode_words(a.input.read_bytes(), a.order)
    except (OSError, ValueError) as exc:
        p.error(str(exc))
    a.out.parent.mkdir(parents=True, exist_ok=True)
    with a.out.open('w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['sample_index', 'time_s', 'channel_a', 'channel_b'])
        for idx, (x, y) in enumerate(samples):
            w.writerow([idx, f'{idx/a.rate:.9f}', x, y])
    print('A:', channel_summary([v[0] for v in samples]))
    print('B:', channel_summary([v[1] for v in samples]))
    print('Saved:', a.out)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

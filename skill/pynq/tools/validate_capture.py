#!/usr/bin/env python3
"""Validate and summarize captured little-endian packed stereo PCM using stdlib only."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path


def analyze(raw: bytes, rate: float = 16000.0) -> dict:
    if len(raw) % 4:
        raise ValueError('capture size is not a multiple of 4 bytes')
    if not raw:
        raise ValueError('capture is empty')
    if rate <= 0 or not math.isfinite(rate):
        raise ValueError('sample rate must be finite and positive')
    pairs = list(struct.iter_unpack('<hh', raw))
    a = [int(x) for x, _ in pairs]
    b = [int(x) for _, x in pairs]
    n = len(pairs)

    def stats(data):
        mean = sum(data) / n
        rms = math.sqrt(sum(x*x for x in data)/n)
        ac_rms = math.sqrt(sum((x-mean)**2 for x in data)/n)
        return {'min': min(data), 'max': max(data), 'mean': mean, 'rms': rms,
                'ac_rms': ac_rms, 'nonzero_samples': sum(x != 0 for x in data)}

    am = sum(a)/n
    bm = sum(b)/n
    aa = sum((x-am)**2 for x in a)
    bb = sum((y-bm)**2 for y in b)
    covariance = sum((x-am)*(y-bm) for x,y in pairs)
    corr = (covariance/math.sqrt(aa*bb)) if aa>0 and bb>0 else None
    return {
        'bytes': len(raw), 'word_count': n, 'duration_s_nominal': n / rate,
        'nominal_rate_hz': rate,
        'sha256': hashlib.sha256(raw).hexdigest(),
        'nonzero_words': sum(x != 0 or y != 0 for x,y in pairs),
        'channel_a': stats(a), 'channel_b': stats(b),
        'channel_correlation': corr,
        'identical_sample_pairs': sum(x == y for x,y in pairs),
        'channel_difference_rms': math.sqrt(sum((x-y)**2 for x,y in pairs)/n),
        'first_10_pairs': [list(x) for x in pairs[:10]],
        'scope': 'Binary shape and signed PCM decoding only; no audio quality or sensor accuracy assertion'
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description='Audit a real S2MM raw stereo PCM frame (read-only)')
    p.add_argument('input', type=Path)
    p.add_argument('--words', type=int, default=4096, help='expected number of 32-bit words')
    p.add_argument('--rate', type=float, default=16000.0, help='nominal rate, not measured')
    p.add_argument('--sha256', default='', help='optional exact evidence fingerprint')
    p.add_argument('--out', type=Path, help='write JSON report')
    a = p.parse_args(argv)
    if a.words < 1:
        p.error('--words must be positive')
    try:
        report = analyze(a.input.read_bytes(), a.rate)
        report['check'] = 'PASS' if (
            report['word_count'] == a.words and
            (not a.sha256 or report['sha256'].casefold() == a.sha256.casefold())
        ) else 'FAIL'
        if a.out:
            a.out.parent.mkdir(parents=True, exist_ok=True)
            a.out.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf8')
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if report['check'] == 'PASS' else 2
    except (OSError, ValueError) as exc:
        p.error(str(exc))


if __name__ == '__main__':
    raise SystemExit(main())

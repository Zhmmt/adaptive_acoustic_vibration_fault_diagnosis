#!/usr/bin/env python3
"""Read-only Vivado HWH AXI address/contract auditor. Python >=3.9; stdlib only."""
from __future__ import annotations
import argparse
import hashlib
import json
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def read_hwh(path: Path) -> dict:
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f'HWH missing or empty: {path}')
    root = ET.parse(path).getroot()
    if root.tag != 'EDKSYSTEM':
        raise ValueError('Expected Vivado EDKSYSTEM HWH XML')
    info = root.find('SYSTEMINFO')
    instances = {}
    for m in root.findall('./MODULES/MODULE'):
        name = m.get('INSTANCE')
        if not name:
            continue
        if name in instances:
            raise ValueError(f'Duplicate HWH MODULE INSTANCE: {name}')
        params = {p.get('NAME'): p.get('VALUE') for p in m.findall('./PARAMETERS/PARAMETER') if p.get('NAME')}
        addr = {}
        for field in ('C_BASEADDR', 'C_HIGHADDR'):
            if field in params:
                try:
                    addr[field] = int(params[field], 0)
                except (ValueError, TypeError):
                    raise ValueError(f'{name} invalid {field}={params[field]}')
        instances[name] = {'type': m.get('MODTYPE', ''), 'vlnv': m.get('VLNV', ''),
                           'params': params, **addr}
    return {'path': str(path), 'sha256': digest(path),
            'device': dict(info.attrib) if info is not None else {}, 'ips': instances}


def check_contract(manifest: dict, spec: dict) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    actual = manifest['ips']
    for name, req in spec.get('instances', {}).items():
        ip = actual.get(name)
        if ip is None:
            errors.append(f'MISSING: {name}'); continue
        if 'type' in req and ip['type'] != req['type']:
            errors.append(f'{name}: type {ip["type"]!r} != {req["type"]!r}')
        if 'vlnv' in req and ip['vlnv'] != req['vlnv']:
            errors.append(f'{name}: VLNV {ip["vlnv"]!r} != {req["vlnv"]!r}')
        for param, expected in req.get('params', {}).items():
            real = ip['params'].get(param)
            if real is None or str(real).casefold() != str(expected).casefold():
                errors.append(f'{name}: {param} actual={real!r}, expected={expected!r}')
        for fld in ('C_BASEADDR', 'C_HIGHADDR'):
            if fld in req:
                try:
                    expected = int(str(req[fld]), 0)
                except ValueError:
                    errors.append(f'{name}: invalid contract {fld}')
                    continue
                if ip.get(fld) != expected:
                    real = ip.get(fld)
                    errors.append(f'{name}: {fld} actual={None if real is None else hex(real)}, expected={hex(expected)}')
    if not actual:
        errors.append('HWH has no MODULE elements')
    ranges = []
    for name, ip in actual.items():
        if ip['type'] not in ('axi_gpio', 'axi_dma', 'axi_iic'):
            continue
        lo, hi = ip.get('C_BASEADDR'), ip.get('C_HIGHADDR')
        if lo is None or hi is None:
            errors.append(f'{name}: missing AXI address interval')
            continue
        if hi < lo:
            errors.append(f'{name}: reversed AXI address interval')
        ranges.append((lo, hi, name))
    ranges.sort()
    for prev, nxt in zip(ranges, ranges[1:]):
        if prev[1] >= nxt[0]:
            errors.append(f'OVERLAP: {prev[2]} [{hex(prev[0])}, {hex(prev[1])}] / {nxt[2]} [{hex(nxt[0])}, {hex(nxt[1])}]')
    if spec.get('device'):
        for k, v in spec['device'].items():
            if manifest['device'].get(k) != v:
                errors.append(f'device.{k}: actual={manifest["device"].get(k)!r}, expected={v!r}')
    if spec.get('instances'):
        extra = set(actual) - set(spec['instances'])
        if extra:
            warnings.append(f'{len(extra)} other HWH modules not constrained (e.g. interconnect/PS)')
    return errors, warnings


def inspect_bit(hwh: Path, bit: Path) -> list[str]:
    issues = []
    if not bit.is_file() or bit.stat().st_size == 0:
        return [f'BIT missing or empty: {bit}']
    if bit.suffix.lower() != '.bit' or bit.stem != hwh.stem:
        issues.append(f'BIT/HWH filename stem differs: {bit.name} / {hwh.name}')
    return issues


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description='Offline, read-only HWH address/contract checker')
    p.add_argument('hwh', type=Path, help='Vivado-generated .hwh')
    p.add_argument('--contract', type=Path, help='optional JSON interface contract')
    p.add_argument('--bit', type=Path, help='optional bitfile presence/name check (NOT matching-build proof)')
    p.add_argument('--json', action='store_true', help='print full machine-readable report')
    p.add_argument('--report', type=Path, help='write JSON report')
    a = p.parse_args(argv)
    try:
        manifest = read_hwh(a.hwh)
        spec = json.loads(a.contract.read_text(encoding='utf-8')) if a.contract else {}
        errors, warnings = check_contract(manifest, spec)
        bit_meta = None
        if a.bit:
            errors += inspect_bit(a.hwh, a.bit)
            if a.bit.is_file() and a.bit.stat().st_size:
                bit_meta = {'path': str(a.bit), 'sha256': digest(a.bit)}
            warnings.append('A BIT/HWH filename/hash check cannot prove they came from the same implementation run.')
        record = {'result': 'PASS' if not errors else 'FAIL', 'checked_hwh': str(a.hwh),
                  'hwh_sha256': manifest['sha256'], 'device': manifest['device'],
                  'ip_count': len(manifest['ips']), 'ips': manifest['ips'],
                  'bit': bit_meta, 'errors': errors, 'warnings': warnings,
                  'scope': 'Static HWH and optional file presence checks only; no synthesis, timing, or board validation.'}
        if a.report:
            a.report.parent.mkdir(parents=True, exist_ok=True)
            a.report.write_text(json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        if a.json:
            print(json.dumps(record, ensure_ascii=False, indent=2, sort_keys=True))
        else:
            for name, ip in sorted(manifest['ips'].items()):
                if 'C_BASEADDR' in ip and ip['type'] in ('axi_gpio', 'axi_dma', 'axi_iic'):
                    print(f'{name:23} {ip["type"]:9} {ip["C_BASEADDR"]:#010x}-{ip["C_HIGHADDR"]:#010x}')
            print(f'RESULT: {record["result"]}  IPs: {record["ip_count"]}')
            for msg in errors: print('ERROR:', msg)
            for msg in warnings: print('NOTE:', msg)
        return 0 if not errors else 2
    except (ValueError, ET.ParseError, OSError, json.JSONDecodeError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())

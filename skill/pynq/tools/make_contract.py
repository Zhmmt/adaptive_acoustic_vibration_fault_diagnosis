#!/usr/bin/env python3
"""Generate a reviewed baseline JSON contract from a Vivado HWH snapshot."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from overlay_audit import read_hwh

TYPES = {'axi_gpio', 'axi_dma', 'axi_iic'}
PARAMS = {
    'axi_gpio': ('C_GPIO_WIDTH', 'C_IS_DUAL', 'C_GPIO2_WIDTH'),
    'axi_dma': ('C_INCLUDE_S2MM', 'C_INCLUDE_MM2S', 'C_INCLUDE_SG', 'C_S_AXIS_S2MM_TDATA_WIDTH', 'C_SG_LENGTH_WIDTH'),
    'axi_iic': (),
}


def build_contract(manifest):
    result = {'schema_version': 1, 'title': 'Review and freeze this baseline before checking later builds',
              'device': {k: manifest['device'][k] for k in ('DEVICE', 'PACKAGE') if k in manifest['device']},
              'instances': {}}
    for name, ip in sorted(manifest['ips'].items()):
        if ip['type'] not in TYPES:
            continue
        fields = {'type': ip['type'], 'vlnv': ip['vlnv'], 'params': {
            k: ip['params'][k] for k in PARAMS[ip['type']] if k in ip['params']}}
        for k in ('C_BASEADDR', 'C_HIGHADDR'):
            if k in ip:
                fields[k] = hex(ip[k])
        result['instances'][name] = fields
    return result


def main(argv=None):
    p = argparse.ArgumentParser(description='Generate an AXI contract snapshot from a known baseline HWH')
    p.add_argument('hwh', type=Path)
    p.add_argument('--out', required=True, type=Path)
    a = p.parse_args(argv)
    contract = build_contract(read_hwh(a.hwh))
    if not contract['instances']:
        p.error('No axi_gpio / axi_dma / axi_iic modules found')
    if a.out.exists():
        p.error(f'Refusing to overwrite existing contract: {a.out}')
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(contract, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Created {a.out} with {len(contract["instances"])} AXI modules; REVIEW before accepting as baseline.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

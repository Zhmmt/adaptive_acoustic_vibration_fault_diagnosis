#!/usr/bin/env python3
"""Compare PS-accessible memory map and selected IP parameters.
Use after an optimized HWH is generated; do not infer compatibility from RTL alone.
"""
from pathlib import Path
import argparse,xml.etree.ElementTree as ET,sys
ap=argparse.ArgumentParser()
ap.add_argument('--baseline',default='baseline_artifacts/board_tested_original_hwh')
ap.add_argument('--candidate',default='deploy/rs555_final.hwh')
a=ap.parse_args()
def collect(p):
    p=Path(p)
    if not p.exists():sys.exit('MISSING HWH: '+str(p))
    root=ET.parse(p).getroot()
    addr={};params={}
    for m in root.iter('MODULE'):
        name=m.attrib.get('INSTANCE','')
        if name not in ('axi_dma_audio','axi_gpio_ctrl','axi_gpio_status0','axi_gpio_status1','axi_gpio_status2','axi_gpio_adxl_sw','axi_iic_adxl'):
            continue
        ps={p.attrib.get('NAME'):p.attrib.get('VALUE') for p in m.iter('PARAMETER')}
        addr[name]=(ps.get('C_BASEADDR'),ps.get('C_HIGHADDR'))
        selected=('C_GPIO_WIDTH','C_GPIO2_WIDTH','C_IS_DUAL','C_ALL_INPUTS','C_ALL_INPUTS_2','C_ALL_OUTPUTS','C_INCLUDE_MM2S','C_INCLUDE_S2MM','C_S_AXIS_S2MM_TDATA_WIDTH')
        params[name]={k:ps[k] for k in selected if k in ps}
    return addr,params
x,y=collect(a.baseline),collect(a.candidate)
errors=[]
for typ,old,new in zip(('AXI address map','IP settings'),x,y):
    for k in sorted(set(old)|set(new)):
        if k not in old or k not in new or old[k]!=new[k]:errors.append(f'{typ} {k}: original={old.get(k)}, optimized={new.get(k)}')
if errors:
    print('VITIS_ABI_MISMATCH: do not load original ELF with changed bitstream!')
    for e in errors:print(' - '+e)
    sys.exit(2)
print('VITIS_ABI_PASS: compared AXI base/high addresses and selected IP settings.')
print('Still check PS register semantics, XDC pins, DMA frame data and board operation; this is not a hardware test.')

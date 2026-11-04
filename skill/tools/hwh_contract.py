#!/usr/bin/env python3
"""Compare AXI base/high addresses and selected parameters in any two Xilinx HWH XML files."""
from pathlib import Path
import argparse,json,xml.etree.ElementTree as ET,sys
p=argparse.ArgumentParser();p.add_argument('baseline',type=Path);p.add_argument('candidate',type=Path);a=p.parse_args()
keys={'C_BASEADDR','C_HIGHADDR','C_GPIO_WIDTH','C_GPIO2_WIDTH','C_IS_DUAL','C_ALL_INPUTS','C_ALL_INPUTS_2','C_ALL_OUTPUTS','C_INCLUDE_MM2S','C_INCLUDE_S2MM','C_S_AXIS_S2MM_TDATA_WIDTH','C_SG_LENGTH_WIDTH'}
def load(path):
 doc=ET.parse(path).getroot();out={}
 for m in doc.iter('MODULE'):
  name=m.attrib.get('INSTANCE','');params={p.attrib.get('NAME'):p.attrib.get('VALUE') for p in m.iter('PARAMETER')}
  if 'C_BASEADDR' in params:out[name]={k:params[k] for k in sorted(keys) if k in params}
 return out
x,y=load(a.baseline),load(a.candidate);bad=[]
for name in sorted(set(x)|set(y)):
 if x.get(name)!=y.get(name):bad.append({'ip':name,'old':x.get(name),'new':y.get(name)})
print(json.dumps({'compatible':not bad,'checked_peripherals':len(x),'differences':bad},indent=2,ensure_ascii=False))
sys.exit(1 if bad else 0)

#!/usr/bin/env python3
"""Check routed Vivado timing summaries; never substitutes external I/O constraints."""
import argparse,re,json,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('report',type=Path);p.add_argument('--require-pass',action='store_true');a=p.parse_args()
s=a.report.read_text(encoding='utf-8',errors='replace')
# Vivado timing report numeric row after WNS(ns) header
m=re.search(r'WNS\(ns\).*?WHS\(ns\).*?\n\s*-+.*?\n\s*([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+(\d+)\s+\d+\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)',s,re.S)
if not m:
 print('UNRECOGNIZED_TIMING_FORMAT');sys.exit(2)
wns,tns,fail,whs,ths=m.groups()
r={'setup_wns_ns':float(wns),'setup_tns_ns':float(tns),'setup_failing_endpoints':int(fail),'hold_whs_ns':float(whs),'hold_ths_ns':float(ths)}
r['pass_internal_timing']=r['setup_wns_ns']>=0 and r['setup_tns_ns']>=0 and r['setup_failing_endpoints']==0 and r['hold_whs_ns']>=0
print(json.dumps(r,indent=2,ensure_ascii=False))
if a.require_pass and not r['pass_internal_timing']:sys.exit(1)

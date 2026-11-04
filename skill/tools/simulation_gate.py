#!/usr/bin/env python3
"""Confirm that a Vivado xsim full-run log includes the expected verified marker."""
from pathlib import Path
import argparse,sys
p=argparse.ArgumentParser();p.add_argument('log',type=Path);p.add_argument('--marker',required=True);a=p.parse_args()
s=a.log.read_text(encoding='utf-8',errors='replace')
fail=any(x in s for x in ['Fatal:', '$fatal', 'TEST_FAIL','VALID_FAIL','ERROR: [VRFC'])
if a.marker not in s or fail:
 print('SIM_GATE_FAIL',a.log,'marker_found=',a.marker in s,'fatal_found=',fail);sys.exit(1)
print('SIM_GATE_PASS',a.log,'marker=',a.marker)

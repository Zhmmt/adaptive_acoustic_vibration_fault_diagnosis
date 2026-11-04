#!/usr/bin/env python3
"""Static contract check: unchanged public module headers and original XDC.
Not a replacement for Vivado simulation or routed timing.
"""
from pathlib import Path
import re,sys,hashlib
root=Path(__file__).resolve().parents[1]
changed=['fir31.v','st7789p3_dashboard.v','tach_rpm.v','dc_blocker.v']
def header(s):
    s=re.sub(r'//[^\n]*|/\*.*?\*/','',s,flags=re.S)
    st=s.index('module ')
    match=re.search(r'\)\s*;',s[st:])
    return ''.join(s[st:st+match.end()].split()) if match else ''
for f in changed:
    orig=(root/'baseline_artifacts'/f).read_text()
    opt=(root/'rtl'/f).read_text()
    assert header(orig)==header(opt),f+' PORT/PARAMETER INTERFACE CHANGED'
    print('MODULE_PORT_CONTRACT_PASS',f)
for f in ['motor_pwm.v','rs555_system_core.v','dmic_audio.v','axis_stereo_frame.v']:
    assert (root/'baseline_artifacts'/f).read_bytes()==(root/'rtl'/f).read_bytes(),f+' changed'
    print('PRESERVED_CORE_PASS',f)
print('STATIC_CONTRACT_PASS (does NOT certify Vitis executable or hardware timing)')

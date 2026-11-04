#!/usr/bin/env python3
"""Read-only, portable integrity checks for the RS555 distribution."""
from pathlib import Path
import zipfile,io,re,hashlib,sys
root=Path(__file__).resolve().parents[1]
errors=[]
for rel in ['rtl/fir31.v','rtl/dc_blocker.v','rtl/tach_rpm.v','rtl/st7789p3_dashboard.v','src/vitis/main.c','board/deploy/rs555_final.bit','board/deploy/rs555_final.hwh','board/deploy/rs555_final.xsa','board/deploy/rs555_vitis_app.elf','build/reports/optimized/timing_summary.rpt','build/reports/optimized/utilization.rpt','skill/README.md','report/design_report.pdf']:
 if not (root/rel).is_file() or not (root/rel).stat().st_size:errors.append('missing '+rel)
try:
 x=zipfile.ZipFile(root/'board/deploy/rs555_final.xsa')
 for suffix in ['bit','hwh']:
  xs=[n for n in x.namelist() if n.endswith('.'+suffix)]
  if len(xs)!=1:errors.append('XSA '+suffix+' count invalid')
  elif x.read(xs[0])!=(root/f'board/deploy/rs555_final.{suffix}').read_bytes():errors.append('XSA '+suffix+' differs from deploy')
except Exception as e:errors.append('XSA validation: '+str(e))
text=(root/'build/reports/optimized/timing_gate_result.txt').read_text()
for key in ['SETUP_WNS_NS','HOLD_WHS_NS']:
 m=re.search(rf'^{key}=([-+\d.]+)',text,re.M)
 if not m or float(m.group(1))<0:errors.append(key+' timing gate negative/missing')
for p in sorted((root/'board/evidence').glob('photo_*.jpg')):
 if not p.stat().st_size:errors.append('empty photo '+p.name)
if errors:
 print('SUBMISSION_INTEGRITY_FAIL')
 for e in errors:print(' -',e)
 sys.exit(1)
print('SUBMISSION_INTEGRITY_PASS: files exist, XSA/bit/hwh consistent, recorded timing gate nonnegative')
print('NOTE: this is NOT a hardware or pin timing validation')

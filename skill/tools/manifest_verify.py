#!/usr/bin/env python3
"""Verify a previously generated sha256 manifest without rewriting any artifact."""
from pathlib import Path
import sys,hashlib,argparse
p=argparse.ArgumentParser();p.add_argument('manifest',type=Path);a=p.parse_args();root=a.manifest.parent
bad=[];n=0
for line in a.manifest.read_text().splitlines():
 if not line.strip() or line.startswith('#'):continue
 sha,rel=line.split('  ',1);target=(root/rel)
 if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=sha:bad.append(rel)
 n+=1
print('MANIFEST_PASS' if not bad else 'MANIFEST_FAIL',n,'checked',len(bad),'bad')
for b in bad:print(b)
sys.exit(1 if bad else 0)

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refresh file hashes after applying replacement files, from project root."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "manifest_sha256.txt"
# Build-generated outputs are never part of the submitted source archive unless
# manually moved into their designated preserved locations.
EXCLUDED_FOLDERS = {".git", ".Xil", "__pycache__"}
EXCLUDED_ROOT_OUTPUTS = {"reports", "deploy"}
EXCLUDED_BUILD_FOLDERS = {(ROOT / "build" / "overlay").resolve()}

def included(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    if path == OUTPUT or any(part in EXCLUDED_FOLDERS for part in relative.parts) or relative.parts[0] in EXCLUDED_ROOT_OUTPUTS:
        return False
    if any(path.resolve().is_relative_to(x) for x in EXCLUDED_BUILD_FOLDERS):
        return False
    return path.is_file()

lines = []
for path in sorted(ROOT.rglob("*")):
    if included(path):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {path.relative_to(ROOT).as_posix()}")
OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"HASH_MANIFEST_REFRESHED {len(lines)} files -> {OUTPUT}")

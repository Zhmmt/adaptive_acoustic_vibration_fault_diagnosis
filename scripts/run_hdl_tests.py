#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Isolated Vivado XSim regression for the submitted RTL and testbenches.

Runs actual xvlog/xelab/xsim, not compile-only checks.  No simulated PASS files.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "rtl"
TB = ROOT / "sim" / "optimized" / "testbench"
OUT = ROOT / "reports" / "simulation"

# (case, top, RTL module filenames, testbench filenames, exact completion token)
CASES = [
    ("fir31", "tb_fir31_pipeline", ["fir31.v"], ["tb_fir31_pipeline.v"], "FIR31_PIPELINE_TEST_PASS"),
    ("lcd", "tb_lcd_rpm_bcd", ["lcd_spi_byte.v", "st7789p3_dashboard.v"], ["tb_lcd_rpm_bcd.v"], "LCD_RPM_BCD_TEST_PASS"),
    ("tach_equivalence", "tb_tach_rpm_equivalence", ["tach_rpm.v"], ["tach_rpm_original_reference.v", "tb_tach_rpm_equivalence.v"], "TACH_EQ_PASS"),
    ("dc_blocker", "tb_dc_blocker_sparse", ["dc_blocker.v"], ["tb_dc_blocker_sparse.v"], "DC_BLOCKER_SPARSE_TEST_PASS"),
    ("stereo_stream", "tb_audio_integration", ["cic3_decimator.v", "dc_blocker.v", "fir31.v", "dmic_audio.v", "axis_stereo_frame.v"], ["tb_audio_integration.v"], "AUDIO_INTEGRATION_TEST_PASS"),
]

def fail(msg: str, code: int = 1) -> int:
    print("ERROR: " + msg, file=sys.stderr)
    return code

def run_cmd(argv: list[str], cwd: Path, logpath: Path) -> int:
    print("  $ " + " ".join(argv))
    with logpath.open("w", encoding="utf-8", errors="replace") as f:
        f.write("CMD: " + " ".join(argv) + "\n")
        f.flush()
        try:
            p = subprocess.run(argv, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, check=False)
        except OSError as e:
            f.write("\nCOMMAND_START_FAILED: " + str(e) + "\n")
            return 127
        return p.returncode

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true", help="Check source paths; do not claim simulation PASS")
    args = parser.parse_args()
    required = []
    for _, _, mods, tests, _ in CASES:
        required += [RTL / m for m in mods] + [TB / t for t in tests]
    missing = sorted({str(p.relative_to(ROOT)) for p in required if not p.is_file()})
    if missing:
        return fail("Missing test sources:\n  " + "\n  ".join(missing), 2)
    print("SOURCE_PATH_CHECK_PASS: all five optimized testbenches and RTL dependencies exist")
    if args.check_only:
        print("CHECK_ONLY: no simulation was executed")
        return 0
    for executable in ("xvlog", "xelab", "xsim"):
        if not shutil.which(executable):
            return fail(f"{executable} unavailable. Launch Vivado 2026.1 Command Prompt first.", 2)

    OUT.mkdir(parents=True, exist_ok=True)
    for case, top, mods, tests, marker in CASES:
        case_dir = OUT / case
        # Generated work is case-local, preventing stale compiled modules/snapshots.
        if case_dir.exists():
            shutil.rmtree(case_dir)
        case_dir.mkdir(parents=True)
        sources = [str(RTL / m) for m in mods] + [str(TB / t) for t in tests]
        snapshot = "rs555_" + case + "_snapshot"
        commands = [
            ("compile", ["xvlog", "--relax", "-log", str(case_dir / "compile.log"), *sources]),
            ("elaborate", ["xelab", "xil_defaultlib." + top, "-s", snapshot, "-log", str(case_dir / "elaborate.log")]),
            ("run", ["xsim", snapshot, "-runall", "-log", str(case_dir / "runtime.log")]),
        ]
        print(f"\n== XSim test: {case} ==")
        for stage, cmd in commands:
            rc = run_cmd(cmd, case_dir, case_dir / (stage + ".stdout.txt"))
            if rc:
                return fail(f"{case} {stage} failed (exit {rc}); see {case_dir}")
        runtime = case_dir / "runtime.log"
        if not runtime.is_file():
            return fail(f"{case}: XSim runtime.log missing")
        transcript = runtime.read_text(encoding="utf-8", errors="replace")
        if marker not in transcript:
            return fail(f"{case}: expected marker {marker!r} missing from actual runtime.log")
        if "FATAL:" in transcript or "Fatal:" in transcript or "$fatal" in transcript:
            return fail(f"{case}: fatal diagnostic found in runtime.log")
        print(f"SIM_PASS: {case} ({marker})")
    (OUT / "all_sim_tests_pass.txt").write_text(
        "ALL_SIM_TESTS_PASS\nTool: Vivado XSim (actual execution)\n" +
        "\n".join(f"{case}: {marker}" for case, _, _, _, marker in CASES) + "\n",
        encoding="utf-8")
    print("\nALL_SIM_TESTS_PASS — generated logs are in reports/simulation/<case>/")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

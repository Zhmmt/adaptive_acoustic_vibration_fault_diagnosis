#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Reproducible RS555 verification gates and Vivado batch build.

Usage: python scripts/reproduce_all.py [preflight|sim|build|verify|all]
Hardware commands are never emulated. 'verify' reads newly generated outputs.
"""
from __future__ import annotations
import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPORTS = ROOT / "reports" / "optimized"
DEPLOY = ROOT / "deploy"


def failure(message: str, code: int = 1) -> int:
    print("ERROR: " + message, file=sys.stderr)
    return code


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def preflight() -> int:
    expected = [
        "vivado/build_overlay_timing_guard.tcl", "constraints/overlay.xdc",
        "rtl/rs555_system_core.v", "rtl/fir31.v", "rtl/dc_blocker.v",
        "rtl/st7789p3_dashboard.v", "rtl/tach_rpm.v", "rtl/axis_stereo_frame.v",
        "sim/optimized/testbench/tb_fir31_pipeline.v", "sim/optimized/testbench/tb_lcd_rpm_bcd.v",
        "sim/optimized/testbench/tb_tach_rpm_equivalence.v",
        "sim/optimized/testbench/tb_dc_blocker_sparse.v",
        "sim/optimized/testbench/tb_audio_integration.v", "src/vitis/main.c",
        "src/vitis/lscript.ld", "scripts/check_vitis_abi.py",
        "baseline_artifacts/board_tested_original_hwh",
    ]
    missing = [p for p in expected if not (ROOT / p).is_file()]
    if missing:
        return failure("Missing mandatory files: " + ", ".join(missing), 2)
    tcl = (ROOT / "vivado/build_overlay_timing_guard.tcl").read_text(encoding="utf-8", errors="replace")
    if not re.search(r"CONFIG\.c_sg_length_width\s*\{16\}", tcl):
        return failure("DMA configuration is not 16-bit in Vivado Tcl", 2)
    if not re.search(r"PCW_FPGA0_PERIPHERAL_FREQMHZ\s*\{100\.000000\}", tcl):
        return failure("100 MHz PS FCLK0 constraint not found in Vivado Tcl", 2)
    print("SOURCE_PREFLIGHT_PASS: RTL, XDC, Tcl, Vitis source, testbenches and DMA16 configuration found")
    return 0


def command(argv: list[str], logfile: Path) -> int:
    logfile.parent.mkdir(parents=True, exist_ok=True)
    print("$ " + " ".join(argv))
    with logfile.open("w", encoding="utf-8", errors="replace") as out:
        try:
            proc = subprocess.run(argv, cwd=ROOT, stdout=out, stderr=subprocess.STDOUT, check=False)
        except OSError as e:
            out.write("COMMAND_START_FAILED: " + str(e) + "\n")
            return 127
    return proc.returncode


def simulate() -> int:
    if not shutil.which("xvlog"):
        return failure("Vivado 2026.1 simulator not found in PATH", 2)
    return command([sys.executable, str(ROOT / "scripts/run_hdl_tests.py")],
                   ROOT / "reports" / "simulation" / "simulation_driver.log")


def build() -> int:
    if not shutil.which("vivado"):
        return failure("vivado executable missing. Use Vivado 2026.1 Command Prompt", 2)
    (ROOT / "reports").mkdir(exist_ok=True)
    # Never silently overwrite preserved, independently validated board/deploy assets.
    print("NOTICE: rebuilding to ROOT/deploy and ROOT/reports/optimized;")
    print("        archived board/deploy files are NOT overwritten.")
    run = ["vivado", "-mode", "batch", "-source", str(ROOT / "vivado/build_overlay_timing_guard.tcl"),
           "-log", str(ROOT / "reports/vivado_reproduce.log"),
           "-journal", str(ROOT / "reports/vivado_reproduce.jou")]
    rc = command(run, ROOT / "reports" / "vivado_batch_stdout.txt")
    if rc:
        return failure(f"Vivado batch execution failed ({rc}). See reports/vivado_reproduce.log and reports/optimized.")
    return verify()


def parse_timing_summary(path: Path) -> tuple[float, float, int, float, float, int, float]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for i, line in enumerate(lines):
        if "WNS(ns)" in line and "TNS(ns)" in line and "WHS(ns)" in line:
            for later in lines[i + 1:i + 5]:
                if re.match(r"^\s*[-+]?\d+(?:\.\d+)?\s+[-+]?\d", later):
                    nums = later.split()
                    if len(nums) >= 9:
                        # WNS, TNS, setup failing endpoints, setup total,
                        # WHS, THS, hold failing endpoints, hold total, WPWS...
                        return (float(nums[0]), float(nums[1]), int(nums[2]),
                                float(nums[4]), float(nums[5]), int(nums[6]), float(nums[8]))
    raise ValueError("Timing summary not parseable: missing summary metrics table")


def hwh_dma_width(raw: bytes) -> int:
    tree = ET.fromstring(raw)
    for module in tree.iter("MODULE"):
        if module.attrib.get("INSTANCE", "") != "axi_dma_audio":
            continue
        for prop in module.iter("PARAMETER"):
            if prop.attrib.get("NAME", "").lower() == "c_sg_length_width":
                return int(prop.attrib["VALUE"], 0)
    raise ValueError("HWH lacks axi_dma_audio/C_SG_LENGTH_WIDTH")


def verify() -> int:
    required = [REPORTS / name for name in
                ("timing_summary.rpt", "utilization.rpt", "drc.rpt", "check_timing.rpt", "timing_gate_result.txt")]
    required += [DEPLOY / ("rs555_final." + ext) for ext in ("bit", "hwh", "xsa")]
    missing = [str(p.relative_to(ROOT)) for p in required if not p.is_file() or p.stat().st_size <= 0]
    if missing:
        return failure("Missing or empty generated artifacts: " + ", ".join(missing), 2)
    try:
        wns, tns, setup_failed, whs, ths, hold_failed, wpws = parse_timing_summary(REPORTS / "timing_summary.rpt")
        gate = (REPORTS / "timing_gate_result.txt").read_text(errors="replace")
        if "SETUP_WNS_NS=" in gate:
            gate_wns = float(re.search(r"SETUP_WNS_NS=([^\s]+)", gate).group(1))
            gate_whs = float(re.search(r"HOLD_WHS_NS=([^\s]+)", gate).group(1))
            if abs(wns - gate_wns) > 0.002 or abs(whs - gate_whs) > 0.002:
                raise ValueError("Gate file and timing summary disagree: possible stale report")
        if min(wns, whs, wpws) < 0 or tns < -0.00001 or ths < -0.00001 or setup_failed or hold_failed:
            raise ValueError(f"Timing failure: WNS={wns}, TNS={tns}, WHS={whs}, setup_failed={setup_failed}, hold_failed={hold_failed}")
        bit = (DEPLOY / "rs555_final.bit").read_bytes()
        hwh = (DEPLOY / "rs555_final.hwh").read_bytes()
        if hwh_dma_width(hwh) != 16:
            raise ValueError("Generated HWH has a non-16-bit DMA length register")
        with zipfile.ZipFile(DEPLOY / "rs555_final.xsa") as archive:
            bits = [n for n in archive.namelist() if n.lower().endswith(".bit")]
            hwhs = [n for n in archive.namelist() if n.lower().endswith(".hwh")]
            if len(bits) != 1 or len(hwhs) != 1:
                raise ValueError("XSA must contain exactly one bitstream and one HWH")
            if archive.read(bits[0]) != bit or archive.read(hwhs[0]) != hwh:
                raise ValueError("Deploy BIT/HWH are not byte-for-byte identical to those embedded in XSA")
    except (ValueError, OSError, ET.ParseError, zipfile.BadZipFile, AttributeError, IndexError) as ex:
        return failure(str(ex), 2)
    print(f"ROUTED_TIMING_PASS WNS={wns:.3f} ns, TNS={tns:.3f} ns, WHS={whs:.3f} ns, WPWS={wpws:.3f} ns")
    print("DMA16_PASS: generated HWH contains 16-bit DMA length")
    print("XSA_ASSET_MATCH_PASS: generated BIT/HWH match XSA contents byte for byte")
    for name in ("bit", "hwh", "xsa"):
        path = DEPLOY / f"rs555_final.{name}"
        print(f"sha256  {sha256(path.read_bytes())}  {path.relative_to(ROOT)}")
    if not (ROOT / "scripts/check_vitis_abi.py").is_file():
        return failure("Missing AXI compatibility check script")
    rc = command([sys.executable, str(ROOT / "scripts/check_vitis_abi.py"),
                  "--baseline", str(ROOT / "baseline_artifacts/board_tested_original_hwh"),
                  "--candidate", str(DEPLOY / "rs555_final.hwh")],
                 ROOT / "reports" / "abi_reproduce.log")
    if rc:
        return failure("AXI register/IP compatibility check failed. Do NOT reuse historical ELF without revalidation.")
    print("VITIS_ABI_PASS: selected HWH address/IP contracts match baseline; this does not prove ELF/board operation")
    print("REPRODUCTION_GATE_PASS: implement report and artifacts verified, board validation still required")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action", nargs="?", choices=("preflight", "sim", "build", "verify", "all"), default="all")
    args = ap.parse_args()
    if args.action != "verify":
        rc = preflight()
        if rc:
            return rc
    if args.action == "preflight":
        return 0
    if args.action == "sim":
        return simulate()
    if args.action == "verify":
        return verify()
    if args.action == "build":
        return build()
    rc = simulate()
    if rc:
        return rc
    return build()

if __name__ == "__main__":
    raise SystemExit(main())

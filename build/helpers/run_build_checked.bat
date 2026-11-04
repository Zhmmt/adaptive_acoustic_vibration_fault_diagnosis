@echo off
setlocal
cd /d "%~dp0\.."
where vivado >nul 2>nul
if errorlevel 1 (
 echo ERROR: Run this batch file from Vivado 2026.1 Command Prompt.
 exit /b 2
)
vivado -mode batch -source vivado/build_overlay_timing_guard.tcl -log reports/vivado_optimized.log -journal reports/vivado_optimized.jou
if errorlevel 1 (
 echo BUILD NOT APPROVED. Read reports/optimized/timing_summary.rpt and timing_gate_result.txt.
 exit /b 1
)
python scripts/check_vitis_abi.py --baseline baseline_artifacts/board_tested_original_hwh --candidate deploy/rs555_final.hwh
if errorlevel 1 (
 echo ADDRESS/IP MISMATCH: original Vitis ELF MUST NOT be assumed compatible.
 exit /b 1
)
echo TIMING and ABI checked. Full board retest with matched new BIT + original ELF is still required.

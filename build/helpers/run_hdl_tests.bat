@echo off
setlocal EnableExtensions
cd /d "%~dp0\.."
where xvlog >nul 2>nul
if errorlevel 1 (
  echo ERROR: Open a Vivado 2026.1 Command Prompt, then run scripts\run_hdl_tests.bat
  exit /b 2
)
if not exist reports\simulation mkdir reports\simulation
call :onetest fir31 tb_fir31_pipeline "rtl\fir31.v" "sim\testbench\tb_fir31_pipeline.v" FIR31_PIPELINE_TEST_PASS
if errorlevel 1 exit /b 1
call :onetest lcd tb_lcd_rpm_bcd "rtl\lcd_spi_byte.v" "rtl\st7789p3_dashboard.v" "sim\testbench\tb_lcd_rpm_bcd.v" LCD_RPM_BCD_TEST_PASS
if errorlevel 1 exit /b 1
call :onetest tach_eq tb_tach_rpm_equivalence "rtl\tach_rpm.v" "sim\testbench\tach_rpm_original_reference.v" "sim\testbench\tb_tach_rpm_equivalence.v" TACH_EQ_PASS
if errorlevel 1 exit /b 1
call :onetest dc tb_dc_blocker_sparse "rtl\dc_blocker.v" "sim\testbench\tb_dc_blocker_sparse.v" DC_BLOCKER_SPARSE_TEST_PASS
if errorlevel 1 exit /b 1
call :onetest stereo tb_audio_integration "rtl\cic3_decimator.v" "rtl\dc_blocker.v" "rtl\fir31.v" "rtl\dmic_audio.v" "rtl\axis_stereo_frame.v" "sim\testbench\tb_audio_integration.v" AUDIO_INTEGRATION_TEST_PASS
if errorlevel 1 exit /b 1
echo ALL_SIM_TESTS_PASS. Review reports\simulation\*.log
exit /b 0
:onetest
set CASE=%~1
set TOP=%~2
shift
shift
set FILES=
:loop
if "%~2"=="" goto compile
set FILES=%FILES% "%~1"
shift
goto loop
:compile
set EXPECT=%~1
echo ==== %CASE% ====
xvlog --relax %FILES% -log reports\simulation\%CASE%_compile.log || exit /b 1
xelab xil_defaultlib.%TOP% -s %CASE%_snapshot -log reports\simulation\%CASE%_elab.log || exit /b 1
xsim %CASE%_snapshot -runall -log reports\simulation\%CASE%_sim.log || exit /b 1
findstr /C:"%EXPECT%" reports\simulation\%CASE%_sim.log >nul
if errorlevel 1 (
 echo FAIL: expected %EXPECT% not found in %CASE% log
 exit /b 1
)
echo %CASE% PASS
exit /b 0

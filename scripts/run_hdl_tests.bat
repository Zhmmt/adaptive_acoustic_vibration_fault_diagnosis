@echo off
setlocal EnableExtensions
pushd "%~dp0.." || exit /b 2
where python >nul 2>nul
if errorlevel 1 (
  echo ERROR: Python 3 is required in the Vivado 2026.1 Command Prompt.
  popd
  exit /b 2
)
python "scripts\run_hdl_tests.py" %*
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%

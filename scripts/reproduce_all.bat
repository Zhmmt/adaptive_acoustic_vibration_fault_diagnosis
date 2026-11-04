@echo off
setlocal EnableExtensions
pushd "%~dp0.." || exit /b 2
where python >nul 2>nul
if errorlevel 1 (
  echo ERROR: Python 3 not found.
  popd
  exit /b 2
)
python "scripts\reproduce_all.py" all
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%

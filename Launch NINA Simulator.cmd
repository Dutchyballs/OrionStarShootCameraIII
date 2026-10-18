@echo off
setlocal
cd /d "%~dp0"
if defined ORION_PYTHON (
  "%ORION_PYTHON%" alpaca\orion_alpaca.py --simulate
  goto finished
)
where py >nul 2>nul
if not errorlevel 1 (
  py -3 alpaca\orion_alpaca.py --simulate
) else (
  python alpaca\orion_alpaca.py --simulate
)
:finished
if errorlevel 1 (
  echo Install Python 3.10 or later, then run this launcher again.
  pause
)

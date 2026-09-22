@echo off
setlocal
title Orion StarShoot - One-Time USB Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\bind-orion-camera.ps1"
set "RESULT=%errorlevel%"
echo.
if "%RESULT%"=="0" (
  echo SUCCESS - the Orion camera is shared with WSL.
) else (
  echo SETUP FAILED with code %RESULT%.
)
echo You may close this window.
pause
exit /b %RESULT%

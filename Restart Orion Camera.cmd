@echo off
start "Orion Camera Recovery" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0tools\restart-orion-camera.ps1" %*

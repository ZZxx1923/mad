@echo off
chcp 65001 >nul
title Remote PC Control - Device Setup
cd /d "%~dp0"
echo Setting up this device (agent)... please follow the instructions.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File | Unblock-File" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-agent.ps1"
echo.
echo Done. Press any key to close.
pause >nul

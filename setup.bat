@echo off
chcp 65001 >nul
title Remote PC Control - Full Setup
cd /d "%~dp0"
echo Starting setup... please follow the instructions.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File | Unblock-File" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
echo.
echo Done. Press any key to close.
pause >nul

@echo off
chcp 65001 >nul
title Remote PC Control - Remove Agent
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-agent.ps1" -Remove
echo.
echo Done. Press any key to close.
pause >nul

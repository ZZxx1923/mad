@echo off
chcp 65001 >nul
title إزالة الوكيل - التحكم عن بعد
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-agent.ps1" -Remove
echo.
echo   انتهى. اضغط أي زر للإغلاق.
pause >nul

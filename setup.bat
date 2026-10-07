@echo off
chcp 65001 >nul
title الإعداد الكامل - التحكم عن بعد
cd /d "%~dp0"
echo.
echo   جارِ إزالة حظر الملفات المنزّلة (يمنع تحذير الأمان)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File | Unblock-File" 2>nul
echo   بدء الإعداد...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
echo.
echo   انتهى. اضغط أي زر للإغلاق.
pause >nul

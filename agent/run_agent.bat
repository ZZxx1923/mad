@echo off
REM تشغيل الـ Agent على ويندوز. ضعه في نفس مجلد agent.py
cd /d "%~dp0"
python agent.py
pause

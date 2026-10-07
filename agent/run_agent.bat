@echo off
chcp 65001 >nul
title Remote PC Control - Agent
cd /d "%~dp0"
python agent.py
pause

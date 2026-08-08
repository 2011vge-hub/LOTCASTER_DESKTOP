@echo off
title Build Walker Pilot
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Walker-Pilot.ps1"
pause


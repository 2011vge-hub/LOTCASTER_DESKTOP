@echo off
title LotCaster System Check
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-LotCaster.ps1"
pause

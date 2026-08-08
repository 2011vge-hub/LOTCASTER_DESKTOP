@echo off
title Install LotCaster Desktop Icon
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Create-LotCaster-Desktop-Icon.ps1"
pause

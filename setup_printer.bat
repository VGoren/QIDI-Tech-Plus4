@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -File "%~dp0Tools\setup_printer.ps1"
pause

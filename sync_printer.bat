@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -File "%~dp0Tools\sync_printer.ps1"
pause

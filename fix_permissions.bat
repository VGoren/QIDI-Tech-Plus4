@echo off
chcp 65001 > nul
echo Запуск исправления прав на принтере QIDI...
powershell -ExecutionPolicy Bypass -File "%~dp0Tools\fix_permissions.ps1"
pause

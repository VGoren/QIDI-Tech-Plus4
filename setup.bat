@echo off
setlocal enabledelayedexpansion

echo ======================================================
echo   QIDI Tech Plus 4 Sync Setup
echo ======================================================

powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '%~dp0Tools\printer-sync.psm1'; Initialize-PrinterSync -Interactive"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Setup failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [SUCCESS] Setup finished successfully.
echo You can now use sync_all.bat to synchronize your files.
echo.
pause

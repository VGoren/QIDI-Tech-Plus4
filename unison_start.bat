@echo off
setlocal

echo ======================================================
echo   QIDI Tech Plus 4 - Unison Auto-Sync Mode
echo ======================================================

powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '%~dp0Tools\printer-sync.psm1'; Invoke-SyncAll -Watch"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Unison stopped or failed!
    pause
    exit /b %ERRORLEVEL%
)

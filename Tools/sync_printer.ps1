[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$S = [char]0x2215
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$RemoteBase = "Y:/"

# Очищаем битые lock-файлы rclone перед стартом, чтобы не было ошибки "prior lock file found"
$RcloneCache = Join-Path $env:LOCALAPPDATA "rclone/bisync"
if (Test-Path $RcloneCache) {
    Get-ChildItem -Path $RcloneCache -Filter "*.lck" | Remove-Item -Force -ErrorAction SilentlyContinue
}

$Pairs = @(
    @{ L="etc"; R="etc"; Mode="bisync" },
    @{ L="home$($S)mks$($S)printer_data$($S)config"; R="home/mks/printer_data/config"; Mode="bisync" },
    @{ L="home$($S)mks$($S)printer_data$($S)gcodes"; R="home/mks/printer_data/gcodes"; Mode="bisync" },
    @{ L="home$($S)mks$($S)printer_data$($S)logs"; R="home/mks/printer_data/logs"; Mode="pull" }
)

Write-Host ">>> СИНХРОНИЗАЦИЯ Rclone..." -ForegroundColor Cyan

foreach ($Item in $Pairs) {
    $LocalPath = Join-Path $ProjectRoot $Item.L
    $RemotePath = Join-Path $RemoteBase $Item.R

    if (-not (Test-Path $LocalPath)) { New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null }

    if ($Item.Mode -eq "bisync") {
        Write-Host "`n↔ 2-Way Sync: $($Item.L)" -ForegroundColor Yellow
        # Оставляем --resync ПОСЛЕДНИЙ РАЗ для etc и gcodes.
        rclone bisync "$LocalPath" "$RemotePath" --fix-case --conflict-resolve newer --verbose --resync
    } else {
        Write-Host "`n↓ Pull Sync: $($Item.L)" -ForegroundColor Green
        rclone copy "$RemotePath" "$LocalPath" --update --progress
    }
}

Write-Host "`n>>> ГОТОВО! Папки etc и gcodes должны быть синхронизированы." -ForegroundColor Green
pause
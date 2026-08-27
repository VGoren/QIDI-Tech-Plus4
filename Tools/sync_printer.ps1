[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$S = [char]0x2215
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$RemoteBase = "Y:/"

$Pairs = @(
    @{ L="home/mks/printer_data/config";  R="home/mks/printer_data/config"; Mode="bisync" }
    @{ L="home/mks/printer_data/gcodes";  R="home/mks/printer_data/gcodes"; Mode="bisync" }
    @{ L="home/mks/printer_data/logs";    R="home/mks/printer_data/logs";   Mode="pull"   }
)

$Resync = "--resync"
$LockDir = Join-Path $env:LOCALAPPDATA "rclone/bisync"

Write-Host ">>> AUTO-WATCHER ENABLED (Interval: 2s) <<<" -ForegroundColor Magenta
Write-Host ">>> Press Ctrl+C to stop.`n" -ForegroundColor Gray

while ($true) {
    # Чистим замки перед каждым циклом, чтобы избежать зависаний "prior lock file found"
    if (Test-Path $LockDir) { Get-ChildItem $LockDir -Filter "*.lck" | Remove-Item -Force -ErrorAction SilentlyContinue }

    foreach ($Item in $Pairs) {
        $FlatName = $Item.L.Replace('/', $S)
        $FullLocal = Join-Path $ProjectRoot $FlatName
        $FullRemote = Join-Path $RemoteBase $Item.R

        if (-not (Test-Path $FullLocal)) { New-Item -ItemType Directory -Path $FullLocal -Force | Out-Null }

        if ($Item.Mode -eq "bisync") {
            # Вывод логов rclone идет напрямую в консоль
            rclone bisync "$FullLocal" "$FullRemote" --fix-case --conflict-resolve newer $Resync --verbose
        } else {
            rclone copy "$FullRemote" "$FullLocal" --update --verbose
        }
    }

    # Снимаем флаг ресинка после первой успешной итерации
    if ($Resync -eq "--resync") { $Resync = "" }

    Start-Sleep -Seconds 2
}
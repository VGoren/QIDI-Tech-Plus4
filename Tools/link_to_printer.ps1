# Скрипт создания "плоских" ссылок с имитацией пути
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Форсируем UTF8 для корректного отображения спецсимвола
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if ($Host.Name -eq "ConsoleHost") { chcp 65001 | Out-Null }

try {
    $IP = "192.168.100.194"
    $User = "mks"
    $Pass = "makerbase"
    $RemoteRoot = "\\$IP\QidiRoot"
    $RepoRoot = $PSScriptRoot

    # Разрешенный слэш (Unicode Division Slash U+2215)
    $S = [char]0x2215

    Write-Host ">>> Авторизация в сети..." -ForegroundColor Cyan
    net use $RemoteRoot $Pass /user:$User /persistent:no | Out-Null

    # Маппинг: Имя ссылки -> Реальный путь на принтере
    $Mappings = @(
        @{ Name = "etc"; Path = "etc" },
        @{ Name = "home$($S)mks$($S)printer_data$($S)config"; Path = "home\mks\printer_data\config" }
    )

    foreach ($M in $Mappings) {
        $LocalLinkPath = Join-Path $RepoRoot $M.Name
        $RemotePath = Join-Path $RemoteRoot $M.Path

        if (Test-Path $LocalLinkPath) {
            Write-Host ">>> Пересоздаю ссылку $($M.Name)..."
            Remove-Item $LocalLinkPath -Force
        }

        Write-Host ">>> Создаю Symbolic Link: $($M.Name)" -ForegroundColor Yellow
        # Для сетевых путей используем /D вместо /J
        cmd /c mklink /D `"$LocalLinkPath`" `"$RemotePath`" | Out-Null
    }

    Write-Host "`n>>> ГОТОВО! Используйте 'git add .' чтобы добавить содержимое ссылок в гит." -ForegroundColor Green
}
catch {
    Write-Host "`n[ОШИБКА] $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host "`nНажмите любую клавишу..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# QIDI Tech Plus 4 Setup Wrapper
param (
    [string]$IP = "192.168.100.194",
    [string]$User = "mks",
    [string]$Pass = "makerbase",
    [string]$DriveLetter = "Y:",
    [switch]$SetupRclone = $true # Заменили флаг Unison
)

Write-Host ">>> Проверка Rclone на стороне Windows..." -ForegroundColor Cyan

# 1. Установка Rclone на ПК (вместо Unison)
try {
    if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
        Write-Host "Rclone не найден. Установка..." -ForegroundColor Yellow
        winget install -e --id Rclone.Rclone --accept-source-agreements --accept-package-agreements
    }
} catch {
    Write-Host "Ошибка установки Rclone." -ForegroundColor Red
}

# 2. Linux-скрипт: Оставили ТОЛЬКО репозитории и Samba (как в оригинале)
$LinuxScript = @'
set -e
export DEBIAN_FRONTEND=noninteractive

PRINTER_PASS="$1"
PRINTER_USER="$2"

echo "--- [1/2] System Prep ---"
# Настройка репозиториев для старой Debian Buster
if ! grep -q "archive.debian.org" /etc/apt/sources.list; then
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    echo "deb http://archive.debian.org/debian buster main contrib non-free" | sudo tee /etc/apt/sources.list
    echo "deb http://archive.debian.org/debian-security buster/updates main contrib non-free" | sudo tee -a /etc/apt/sources.list
    echo 'Acquire::Check-Valid-Until "false";' | sudo tee /etc/apt/apt.conf.d/10no--check-valid-until
fi

echo "--- [2/2] Installing Samba ---"
sudo apt-get update
sudo apt-get install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" samba -y

# Samba setup (идентично оригиналу)
if ! grep -q "\[QidiRoot\]" /etc/samba/smb.conf; then
    sudo sed -i "/\[global\]/a \   unix extensions = no" /etc/samba/smb.conf
    echo -e "\n[QidiRoot]\n   comment = Root FS\n   path = /\n   browseable = yes\n   read only = no\n   guest ok = no\n   force user = root\n   follow symlinks = yes\n   wide links = yes" | sudo tee -a /etc/samba/smb.conf
    sudo systemctl restart smbd
fi

(echo "$PRINTER_PASS"; echo "$PRINTER_PASS") | sudo smbpasswd -s -a $PRINTER_USER
echo "SUCCESS: Samba is ready."
'@

try {
    $CleanScript = ($LinuxScript -replace "`r", "")
    $Base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($CleanScript))

    Write-Host ">>> Передача скрипта установки на принтер $IP..." -ForegroundColor Cyan
    # Передаем только пароль и пользователя
    ssh -t -o ConnectTimeout=15 -o StrictHostKeyChecking=no "${User}@${IP}" "echo '$Base64' | base64 -d | sudo bash -s '$Pass' '$User'"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Установка на стороне принтера завершилась ошибкой."
        exit 1
    }

    # Мапим диск Y: (без изменений)
    Write-Host ">>> Подключение сетевого диска $DriveLetter..." -ForegroundColor Cyan
    $RemoteRoot = "\\$IP\QidiRoot"
    net use * /delete /y 2>$null | Out-Null
    $Letter = if ($DriveLetter.Contains(":")) { $DriveLetter } else { "${DriveLetter}:" }
    net use $Letter $RemoteRoot $Pass "/user:$User" /persistent:yes | Out-Null

    Write-Host ">>> ВСЕ ГОТОВО!" -ForegroundColor Green

} catch {
    Write-Error "Критическая ошибка скрипта: $($_.Exception.Message)"
    exit 1
}
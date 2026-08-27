# QIDI Tech Plus 4 Setup Wrapper
param (
    [string]$IP = "192.168.100.194",
    [string]$User = "mks",
    [string]$Pass = "makerbase",
    [string]$DriveLetter = "Y:",
    [switch]$SetupUnison = $false
)

Write-Host ">>> Определение локальной версии Unison..." -ForegroundColor Cyan

# 1. Получаем точную версию из установленного unison в Windows
$LocalV = "2.54.0" # Значение по умолчанию
try {
    $vRaw = & unison -version
    if ($vRaw -match "version (\d+\.\d+\.\d+)") {
        $LocalV = $Matches[1]
        Write-Host "Обнаружена локальная версия: $LocalV" -ForegroundColor Green
    }
} catch {
    Write-Host "Unison не найден в PATH. Будет использована версия $LocalV по умолчанию." -ForegroundColor Yellow
}

# 2. Обращаемся к GitHub API, чтобы найти прямую ссылку на linux-aarch64 (arm64) для этой версии
Write-Host ">>> Поиск подходящего бинарника на GitHub для Linux ARM64..." -ForegroundColor Cyan
$GitHubUrl = "https://api.github.com/repos/bcpierce00/unison/releases/tags/v$LocalV"
$DownloadUrl = $null

try {
    $ReleaseInfo = Invoke-RestMethod -Uri $GitHubUrl -UseBasicParsing
    # Ищем ассет, в имени которого есть 'linux', 'aarch64' или 'arm64' и 'tar.gz'
    $Asset = $ReleaseInfo.assets | Where-Object {
        ($_.name -like "*linux*" -and ($_.name -like "*aarch64*" -or $_.name -like "*arm64*")) -and $_.name -like "*.tar.gz"
    } | Select-Object -First 1

    if ($Asset) {
        $DownloadUrl = $Asset.browser_download_url
        Write-Host "Найдена прямая ссылка: $DownloadUrl" -ForegroundColor Green
    } else {
        throw "Не удалось найти подходящий .tar.gz архив для архитектуры aarch64 в релизе v$LocalV"
    }
} catch {
    Write-Warning "Ошибка при обращении к GitHub API: $($_.Exception.Message)"
    Write-Host "Будет предпринята попытка сформировать ссылку вручную..." -ForegroundColor Yellow
    # Запасной вариант (угадываем стандартное имя файла)
    $DownloadUrl = "https://github.com/bcpierce00/unison/releases/download/v$LocalV/unison-v$LocalV+0.1.0-linux-aarch64.tar.gz"
}

$LinuxScript = @'
set -e
export DEBIAN_FRONTEND=noninteractive

# Аргументы из PowerShell: $1=URL_СКАЧИВАНИЯ, $2=PASSWORD, $3=USER, $4=TARGET_VERSION
DL_URL="$1"
PRINTER_PASS="$2"
PRINTER_USER="$3"
V_NUM="$4"

echo "--- [1/3] System Prep ---"
# Очищаем битые версии
sudo rm -f /usr/bin/unison

# Настройка репозиториев для старой Debian Buster
if ! grep -q "archive.debian.org" /etc/apt/sources.list; then
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    echo "deb http://archive.debian.org/debian buster main contrib non-free" | sudo tee /etc/apt/sources.list
    echo "deb http://archive.debian.org/debian-security buster/updates main contrib non-free" | sudo tee -a /etc/apt/sources.list
    echo 'Acquire::Check-Valid-Until "false";' | sudo tee /etc/apt/apt.conf.d/10no--check-valid-until
fi

echo "--- [2/3] Installing Dependencies & Samba ---"
sudo apt-get update
sudo apt-get install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" samba curl tar -y

echo "--- [3/3] Downloading Unison from GitHub ---"
echo "Target URL: $DL_URL"
sudo curl -L -f "$DL_URL" -o /tmp/unison.tar.gz || { echo "Download failed!"; exit 1; }

# Распаковка во временную папку
mkdir -p /tmp/unison_extracted
sudo tar -xzf /tmp/unison.tar.gz -C /tmp/unison_extracted

# Поиск бинарника (он может быть в корне архива или в /bin/)
if [ -f /tmp/unison_extracted/bin/unison ]; then
    sudo mv /tmp/unison_extracted/bin/unison /usr/bin/unison
elif [ -f /tmp/unison_extracted/unison ]; then
    sudo mv /tmp/unison_extracted/unison /usr/bin/unison
fi

sudo chmod +x /usr/bin/unison
rm -rf /tmp/unison.tar.gz /tmp/unison_extracted

# Проверка версии на стороне принтера
INSTALLED_V=$(unison -version)
echo "Printer side: $INSTALLED_V"

# Samba setup (if needed)
if ! grep -q "\[QidiRoot\]" /etc/samba/smb.conf; then
    sudo sed -i "/\[global\]/a \   unix extensions = no" /etc/samba/smb.conf
    echo -e "\n[QidiRoot]\n   comment = Root FS\n   path = /\n   browseable = yes\n   read only = no\n   guest ok = no\n   force user = root\n   follow symlinks = yes\n   wide links = yes" | sudo tee -a /etc/samba/smb.conf
    sudo systemctl restart smbd
fi

(echo "$PRINTER_PASS"; echo "$PRINTER_PASS") | sudo smbpasswd -s -a $PRINTER_USER
echo "SUCCESS: Printer is ready."
'@

try {
    # Кодируем скрипт в Base64 для безопасной передачи через SSH
    $CleanScript = ($LinuxScript -replace "`r", "")
    $Base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($CleanScript))

    Write-Host ">>> Передача скрипта установки на принтер $IP..." -ForegroundColor Cyan
    # Запускаем скрипт, передавая найденную URL-ссылку в качестве первого аргумента ($1)
    ssh -t -o ConnectTimeout=15 -o StrictHostKeyChecking=no "${User}@${IP}" "echo '$Base64' | base64 -d | sudo bash -s '$DownloadUrl' '$Pass' '$User' '$LocalV'"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Установка на стороне принтера завершилась ошибкой."
        exit 1
    }

    # Мапим диск Y:
    Write-Host ">>> Подключение сетевого диска $DriveLetter..." -ForegroundColor Cyan
    $RemoteRoot = "\\$IP\QidiRoot"
    # Удаляем старые привязки к этому IP, чтобы не было конфликтов
    net use * /delete /y 2>$null | Out-Null
    $Letter = if ($DriveLetter.Contains(":")) { $DriveLetter } else { "${DriveLetter}:" }
    net use $Letter $RemoteRoot $Pass "/user:$User" /persistent:yes | Out-Null

    Write-Host ">>> ВСЕ ГОТОВО! Версии синхронизированы ($LocalV)." -ForegroundColor Green

} catch {
    Write-Error "Критическая ошибка скрипта: $($_.Exception.Message)"
    exit 1
}
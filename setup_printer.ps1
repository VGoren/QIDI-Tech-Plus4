# QIDI Tech Plus 4 Setup Wrapper
param (
    [string]$IP = "192.168.100.194",
    [string]$User = "mks",
    [string]$Pass = "makerbase",
    [string]$DriveLetter = "Z:"
)

$LinuxScript = @"
echo ""
set -e

# Function to just wait for the lock
wait_for_lock() {
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        echo "Waiting for other apt process..."
        sleep 2
    done
}

export DEBIAN_FRONTEND=noninteractive

echo "--- [1/3] System Recovery ---"
echo "Fixing any interrupted installations..."
sudo dpkg --configure -a
wait_for_lock

echo "--- [2/3] Repositories & Update ---"
[ ! -f /etc/apt/sources.list.bak ] && cp /etc/apt/sources.list /etc/apt/sources.list.bak
echo "deb http://archive.debian.org/debian buster main contrib non-free" > /etc/apt/sources.list
echo "deb http://archive.debian.org/debian-security buster/updates main contrib non-free" >> /etc/apt/sources.list
echo "Acquire::Check-Valid-Until \"false\";" > /etc/apt/apt.conf.d/10no--check-valid-until
apt-get update

echo "--- [3/3] Samba Clean Reinstall ---"
wait_for_lock
apt-get purge samba samba-common -y
rm -rf /etc/samba
apt-get install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" samba -y

echo "Applying QidiRoot config..."
sed -i "/\[global\]/a \   unix extensions = no" /etc/samba/smb.conf
echo -e "\n[QidiRoot]\n   comment = Root FS\n   path = /\n   browseable = yes\n   read only = no\n   guest ok = no\n   force user = root\n   follow symlinks = yes\n   wide links = yes" >> /etc/samba/smb.conf

systemctl restart smbd
(echo "$Pass"; echo "$Pass") | smbpasswd -s -a $User
sleep 2
echo "DONE: Printer setup finished."
"@

try {
    Write-Host ">>> Connecting to $IP..." -ForegroundColor Cyan
    $CleanScript = "$Pass`n$LinuxScript" -replace "`r", ""

    $CleanScript | ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${User}@${IP}" "sudo -S bash"

    if ($LASTEXITCODE -ne 0) { throw "Linux side failed." }

    Write-Host ">>> Re-mounting $DriveLetter..." -ForegroundColor Cyan
    if (Get-PSDrive -Name $DriveLetter[0] -ErrorAction SilentlyContinue) {
        net use $DriveLetter /delete /y | Out-Null
    }

    net use $DriveLetter "\\$IP\QidiRoot" $Pass /user:$User /persistent:yes
    Write-Host "SUCCESS: Drive $DriveLetter is ready." -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

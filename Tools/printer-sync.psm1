function Get-PrinterConfigPath {
    $path = Join-Path $env:APPDATA "qidi-printer-sync"
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return Join-Path $path "config.json"
}

function Get-PrinterConfig {
    $configPath = Get-PrinterConfigPath
    if (Test-Path $configPath) {
        return Get-Content $configPath | ConvertFrom-Json
    }
    return $null
}

function Set-PrinterConfig {
    param($IP, $User, $Pass, $DriveLetter)
    $configPath = Get-PrinterConfigPath
    $config = @{ IP = $IP; User = $User; Pass = $Pass; DriveLetter = $DriveLetter }
    $config | ConvertTo-Json | Set-Content $configPath
}

function Get-AvailableDriveLetter {
    $occupied = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name
    $letters = [char[]]([char]'Z'..[char]'D') # From Z down to D
    foreach ($l in $letters) {
        if ($occupied -notcontains $l) {
            return "$($l):"
        }
    }
    return $null
}

function Install-Unison {
    Write-Host "Checking Unison installation..." -ForegroundColor Cyan
    if (-not (Get-Command unison -ErrorAction SilentlyContinue)) {
        Write-Host "Unison not found. Installing via winget..." -ForegroundColor Yellow
        winget install -e --id bcpierce00.unison --accept-source-agreements --accept-package-agreements
        Write-Host "Please restart your terminal after installation if 'unison' is not recognized." -ForegroundColor Yellow
    } else {
        Write-Host "Unison is already installed." -ForegroundColor Green
    }
}

function Initialize-SSHKeys {
    param($IP, $User, $Pass)
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Host "Setting up SSH keys..." -ForegroundColor Cyan

    # Check if we already have access
    $testKey = ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no "$User@$IP" "echo 1" 2>$null
    if ($testKey -eq "1") {
        Write-Host "SSH access OK." -ForegroundColor Green
        return
    }

    $keyPath = Join-Path $HOME ".ssh\id_rsa"
    if (-not (Test-Path $keyPath)) {
        Write-Host "Generating key..." -ForegroundColor Yellow
        ssh-keygen -t rsa -b 4096 -f $keyPath -q -N ''
    }

    $pubKey = Get-Content "$keyPath.pub"
    Write-Host "Deploying key. Enter printer password once ($Pass):" -ForegroundColor Cyan

    $cmd = "mkdir -p ~/.ssh && grep -qF '$pubKey' ~/.ssh/authorized_keys || echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
    ssh -o StrictHostKeyChecking=no "$User@$IP" $cmd
}

function New-UnisonProfiles {
    param($IP, $User)
    $unisonDir = Join-Path $HOME ".unison"
    if (-not (Test-Path $unisonDir)) {
        New-Item -ItemType Directory -Path $unisonDir -Force | Out-Null
    }

    # Project root is one level up from this module (Tools/)
    $localBase = Split-Path $PSScriptRoot -Parent
    $remoteBase = "ssh://$User@$IP/"
    $s = [char]0x2215 # Special slash ∕

    # We need to create ONE profile per PAIR of roots because Unison only supports 2 roots per profile.
    $items = @(
        @{ Name = "etc"; L = "etc"; R = "etc"; TwoWay = $true },
        @{ Name = "config"; L = "home${s}mks${s}printer_data${s}config"; R = "home/mks/printer_data/config"; TwoWay = $true },
        @{ Name = "models"; L = "home${s}mks${s}printer_data${s}gcodes"; R = "home/mks/printer_data/gcodes"; TwoWay = $true },
        @{ Name = "logs"; L = "home${s}mks${s}printer_data${s}logs"; R = "home/mks/printer_data/logs"; TwoWay = $false },
        @{ Name = "comms"; L = "home${s}mks${s}printer_data${s}comms"; R = "home/mks/printer_data/comms"; TwoWay = $false },
        @{ Name = "videos"; L = "home${s}mks${s}printer_data${s}videos"; R = "home/mks/printer_data/videos"; TwoWay = $false },
        @{ Name = "timelapse"; L = "home${s}mks${s}printer_data${s}timelapse"; R = "home/mks/printer_data/timelapse"; TwoWay = $false }
    )

    $allProfileNames = @()
    foreach ($item in $items) {
        $profileName = "qidi_$($item.Name)"
        $allProfileNames += $profileName

        $localRoot = Join-Path $localBase $item.L
        if (-not (Test-Path $localRoot)) { New-Item -ItemType Directory -Path $localRoot -Force | Out-Null }
        $localRoot = $localRoot.Replace('\', '/')

        $content = "# Unison profile for $($item.Name)`r`n"
        $content += "root = $localRoot`r`n"
        $content += "root = $($remoteBase)$($item.R)`r`n"
        $content += "batch = true`r`nconfirmbigdel = false`r`nfastcheck = true`r`n"
        if (-not $item.TwoWay) {
            $content += "force = $($remoteBase)$($item.R)`r`n"
        }

        # Use UTF8 encoding for the special slash character
        $content | Set-Content (Join-Path $unisonDir "$profileName.prf") -Encoding UTF8
    }

    # Save the list of profiles for Invoke-SyncAll
    $allProfileNames | ConvertTo-Json | Set-Content (Join-Path (Split-Path (Get-PrinterConfigPath)) "profiles.json")
    Write-Host "Unison profiles created in $unisonDir" -ForegroundColor Green
}

function Invoke-SyncAll {
    param([switch]$Watch)

    $config = Get-PrinterConfig
    if (-not $config) {
        Write-Error "Printer not configured. Run Initialize-PrinterSync first."
        return
    }

    $profilesPath = Join-Path (Split-Path (Get-PrinterConfigPath)) "profiles.json"
    if (-not (Test-Path $profilesPath)) {
        Write-Error "Profiles not found. Run Initialize-PrinterSync first."
        return
    }
    $profiles = Get-Content $profilesPath | ConvertFrom-Json

    if ($Watch) {
        Write-Host ">>> AUTO-SYNC MODE ENABLED. Monitoring changes..." -ForegroundColor Magenta
        Write-Host ">>> Press Ctrl+C to stop." -ForegroundColor Cyan
        while ($true) {
            foreach ($p in $profiles) {
                unison "$p" -silent
            }
            Start-Sleep -Seconds 2
        }
    } else {
        Write-Host "Starting full synchronization..." -ForegroundColor Cyan
        foreach ($p in $profiles) {
            Write-Host ">>> Syncing profile: $p..." -ForegroundColor Yellow
            unison "$p"
        }
        Write-Host "Sync complete!" -ForegroundColor Green
    }
}

function Initialize-PrinterSync {
    param([switch]$Interactive)

    $config = Get-PrinterConfig
    if ($Interactive -or -not $config) {
        $defIP = if ($config.IP) { $config.IP } else { "192.168.100.194" }
        $IP = Read-Host "Enter printer IP [$defIP]"
        if ([string]::IsNullOrWhiteSpace($IP)) { $IP = $defIP }

        $defUser = if ($config.User) { $config.User } else { "mks" }
        $User = Read-Host "Enter printer username [$defUser]"
        if ([string]::IsNullOrWhiteSpace($User)) { $User = $defUser }

        $defPass = if ($config.Pass) { $config.Pass } else { "makerbase" }
        $Pass = Read-Host "Enter printer password [$defPass]"
        if ([string]::IsNullOrWhiteSpace($Pass)) { $Pass = $defPass }

        $defDrive = if ($config.DriveLetter) { $config.DriveLetter } else { Get-AvailableDriveLetter }
        $DriveLetter = Read-Host "Enter drive letter [$defDrive]"
        if ([string]::IsNullOrWhiteSpace($DriveLetter)) { $DriveLetter = $defDrive }

        Set-PrinterConfig -IP $IP -User $User -Pass $Pass -DriveLetter $DriveLetter
        $config = Get-PrinterConfig
    }

    Install-Unison

    # Setup SSH Keys FIRST so other SSH calls don't ask for password
    Initialize-SSHKeys -IP $config.IP -User $config.User -Pass $config.Pass

    Write-Host ">>> Running printer-side setup (Samba, Unison, $($config.DriveLetter) drive)..." -ForegroundColor Cyan
    $setupPrinterScript = Join-Path $PSScriptRoot "setup_printer.ps1"
    & $setupPrinterScript -IP $config.IP -User $config.User -Pass $config.Pass -DriveLetter $config.DriveLetter -SetupUnison

    New-UnisonProfiles -IP $config.IP -User $config.User

    Write-Host "Setup complete. You can now use unison_start.bat" -ForegroundColor Green
}

Export-ModuleMember -Function Initialize-PrinterSync, Invoke-SyncAll

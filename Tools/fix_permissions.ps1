<#
.SYNOPSIS
    Fix file permissions for saved_variables.cfg on QIDI printer via SSH.
#>

param(
    [string]$PrinterIP = "192.168.100.194",
    [string]$User = "mks",
    [string]$Password = "makerbase"
)

Write-Host "Connecting to printer $PrinterIP ($User)..." -ForegroundColor Cyan

$remoteCommands = @"
echo 'Fixing ownership...'
echo '$Password' | sudo -S chown -R ${User}:${User} /home/mks/printer_data/config
echo 'Setting permissions on saved_variables.cfg...'
echo '$Password' | sudo -S chmod 664 /home/mks/printer_data/config/saved_variables.cfg
echo 'Restarting Klipper...'
echo '$Password' | sudo -S systemctl restart klipper
echo 'Done! Permissions successfully fixed.'
"@

$remoteCommands = $remoteCommands.Replace("`r`n", "`n")

ssh "$User@$PrinterIP" $remoteCommands

Write-Host "Done!" -ForegroundColor Green

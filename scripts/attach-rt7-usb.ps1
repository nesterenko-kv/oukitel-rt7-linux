[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+-\d+$')]
    [string]$BusId,

    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$usbipd = Get-Command 'usbipd.exe' -ErrorAction Stop
$version = (& $usbipd.Source --version).Trim()
$state = (& $usbipd.Source state | ConvertFrom-Json)
$device = @($state.Devices | Where-Object { $_.BusId -eq $BusId })

if ($device.Count -ne 1) {
    throw "Exactly one connected USB device must exist at BUSID $BusId."
}

$instanceId = [string]$device[0].InstanceId
$description = [string]$device[0].Description
if ($instanceId -notmatch '^USB\\VID_0E8D&PID_' -or $description -notmatch 'RT7|MediaTek|MTK') {
    throw "Refusing non-RT7/MediaTek device at BUSID $BusId ($description)."
}

if (-not $device[0].PersistedGuid) {
    throw @"
The device is not shared yet. In an elevated PowerShell run:
  usbipd bind --busid $BusId
Then rerun this script from the normal terminal.
"@
}

Write-Host "usbipd-win: $version"
Write-Host "Validated MediaTek target at BUSID $BusId ($description)."
Write-Host "Planned command: usbipd attach --wsl docker-desktop --busid $BusId --auto-attach"

if (-not $Execute) {
    Write-Host 'Dry run only; pass -Execute to attach USB to docker-desktop.'
    exit 0
}

& $usbipd.Source attach --wsl docker-desktop --busid $BusId --auto-attach
if ($LASTEXITCODE -ne 0) {
    throw "usbipd attach failed with status $LASTEXITCODE."
}

Write-Host 'USB auto-attach is active. The operation is reversible with:'
Write-Host "  usbipd detach --busid $BusId"

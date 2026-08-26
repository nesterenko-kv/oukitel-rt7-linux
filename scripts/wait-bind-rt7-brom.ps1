[CmdletBinding()]
param(
    [ValidateRange(5, 600)]
    [int]$TimeoutSeconds = 180,

    [ValidateRange(50, 2000)]
    [int]$PollMilliseconds = 100,

    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$usbipd = Get-Command 'usbipd.exe' -ErrorAction Stop
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$bromPattern = '^USB\\VID_0E8D&PID_0003\\'

Write-Host "Waiting up to $TimeoutSeconds seconds for MediaTek BootROM 0e8d:0003..."
while ([DateTime]::UtcNow -lt $deadline) {
    $state = (& $usbipd.Source state | ConvertFrom-Json)
    $devices = @($state.Devices | Where-Object {
        [string]$_.InstanceId -match $bromPattern -and $_.BusId
    })

    if ($devices.Count -gt 1) {
        throw 'Refusing more than one connected MediaTek BootROM device.'
    }
    if ($devices.Count -eq 1) {
        $busId = [string]$devices[0].BusId
        Write-Host "Detected MediaTek BootROM at BUSID $busId."
        if ($devices[0].PersistedGuid) {
            Write-Host 'BootROM USB identity is already shared.'
            Write-Output $busId
            exit 0
        }
        if (-not $Execute) {
            Write-Host "Dry run only. In elevated PowerShell run: usbipd bind --busid $busId"
            Write-Output $busId
            exit 0
        }

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw '-Execute requires an elevated PowerShell process.'
        }

        & $usbipd.Source bind --busid $busId
        if ($LASTEXITCODE -ne 0) {
            throw "usbipd bind failed with status $LASTEXITCODE."
        }
        Write-Host "Shared only the detected 0e8d:0003 device at BUSID $busId."
        Write-Output $busId
        exit 0
    }

    Start-Sleep -Milliseconds $PollMilliseconds
}

throw "Timed out waiting for MediaTek BootROM 0e8d:0003 after $TimeoutSeconds seconds."

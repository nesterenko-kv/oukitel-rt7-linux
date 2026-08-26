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
$transportPattern = [regex]::new(
    '^USB\\VID_0E8D&PID_(?<pid>0003|2000)\\',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if ($Execute) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '-Execute requires an elevated PowerShell process.'
    }
}

Write-Host "Waiting up to $TimeoutSeconds seconds for RT7 preloader/BROM 0e8d:2000 or 0e8d:0003..."
while ([DateTime]::UtcNow -lt $deadline) {
    $state = (& $usbipd.Source state | ConvertFrom-Json)
    $devices = @($state.Devices | Where-Object {
        $transportPattern.IsMatch([string]$_.InstanceId) -and $_.BusId
    })

    if ($devices.Count -gt 1) {
        throw 'Refusing more than one connected MediaTek boot-transport device.'
    }
    if ($devices.Count -eq 1) {
        $instanceId = [string]$devices[0].InstanceId
        $match = $transportPattern.Match($instanceId)
        $pid = $match.Groups['pid'].Value.ToLowerInvariant()
        $mode = if ($pid -eq '0003') { 'BootROM' } else { 'preloader' }
        $busId = [string]$devices[0].BusId
        Write-Host "Detected MediaTek $mode 0e8d:$pid at BUSID $busId."

        if (-not $Execute) {
            if ($devices[0].PersistedGuid) {
                Write-Host 'USB identity is already shared; dry run made no changes.'
            } else {
                Write-Host "Dry run only. In elevated PowerShell run: usbipd bind --busid $busId"
            }
            Write-Output $busId
            exit 0
        }

        if (-not $devices[0].PersistedGuid) {
            & $usbipd.Source bind --busid $busId
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'The short-lived USB identity vanished during bind; continuing to wait.'
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }
            Write-Host "Shared only the detected 0e8d:$pid device at BUSID $busId."
        }

        if (-not $devices[0].ClientIPAddress) {
            & $usbipd.Source attach --wsl docker-desktop --busid $busId
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'The short-lived USB identity vanished during attach; continuing to wait.'
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }
            Write-Host "Attached 0e8d:$pid to Docker Desktop."
        }

        if ($pid -eq '0003') {
            Write-Host 'BootROM transport is ready for the waiting read-only capture.'
            Write-Output $busId
            exit 0
        }

        Write-Host 'Preloader is attached; waiting for its volatile transition to BootROM.'
    }

    Start-Sleep -Milliseconds $PollMilliseconds
}

throw "Timed out waiting for RT7 preloader/BROM after $TimeoutSeconds seconds."

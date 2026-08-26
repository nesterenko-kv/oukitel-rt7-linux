[CmdletBinding()]
param(
    [ValidateRange(5, 600)]
    [int]$TimeoutSeconds = 180,

    [ValidateRange(10, 2000)]
    [int]$PollMilliseconds = 25,

    [switch]$Execute,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$usbipd = Get-Command 'usbipd.exe' -ErrorAction Stop
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$targetPids = @('2000', '0003')
$transportPattern = [regex]::new(
    '^USB\\VID_0E8D&PID_(?<pid>0003|2000)\\',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Changing the Windows USB binding requires an elevated PowerShell process.'
    }
}

if ($Force -and -not $Execute) {
    throw '-Force requires -Execute because it changes the Windows USB binding.'
}

if ($Execute -and $Force) {
    $initialState = (& $usbipd.Source state | ConvertFrom-Json)
    foreach ($targetPid in $targetPids) {
        $hardwareId = "0e8d:$targetPid"
        $pattern = [regex]::new(
            "^USB\\VID_0E8D&PID_${targetPid}\\",
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        $nonForced = @($initialState.Devices | Where-Object {
            $pattern.IsMatch([string]$_.InstanceId) -and
            $_.PersistedGuid -and
            -not $_.IsForced
        })
        if ($nonForced.Count -gt 0) {
            Assert-Administrator
            & $usbipd.Source unbind --hardware-id $hardwareId
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to remove the existing non-forced $hardwareId binding."
            }
            Write-Host "Removed the existing non-forced $hardwareId binding."
        }
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
        $transportPid = $match.Groups['pid'].Value.ToLowerInvariant()
        $mode = if ($transportPid -eq '0003') { 'BootROM' } else { 'preloader' }
        $busId = [string]$devices[0].BusId
        Write-Host "Detected MediaTek $mode 0e8d:$transportPid at BUSID $busId."

        if (-not $Execute) {
            if ($devices[0].PersistedGuid) {
                Write-Host 'USB identity is already shared; dry run made no changes.'
            } else {
                Write-Host "Dry run only. In elevated PowerShell run: usbipd bind --busid $busId"
            }
            Write-Output $busId
            exit 0
        }

        $bindingReady = $devices[0].PersistedGuid -and
            (-not $Force -or $devices[0].IsForced)
        if (-not $bindingReady) {
            # usbipd-win 5.3 can report success for `bind --force
            # --hardware-id` while persisting IsForced=false. Bind the exact,
            # already validated connected BUSID so --force is authoritative.
            Assert-Administrator
            $bindArguments = @('bind')
            if ($Force) {
                $bindArguments += '--force'
            }
            $bindArguments += @('--busid', $busId)
            & $usbipd.Source @bindArguments 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'The short-lived USB identity vanished during bind; continuing to wait.'
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }

            $state = (& $usbipd.Source state | ConvertFrom-Json)
            $boundDevice = @($state.Devices | Where-Object {
                [string]$_.InstanceId -eq $instanceId -and
                $_.PersistedGuid -and
                (-not $Force -or $_.IsForced)
            })
            if ($boundDevice.Count -ne 1) {
                Write-Host 'usbipd did not persist the requested binding; continuing to wait.'
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }
            $devices[0] = $boundDevice[0]
        }

        if (-not $devices[0].ClientIPAddress) {
            & $usbipd.Source attach --wsl docker-desktop --busid $busId
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'The short-lived USB identity vanished during attach; continuing to wait.'
                Start-Sleep -Milliseconds $PollMilliseconds
                continue
            }
            Write-Host "Attached 0e8d:$transportPid to Docker Desktop."
        }

        if ($transportPid -eq '0003') {
            Write-Host 'BootROM transport is ready for the waiting read-only capture.'
            Write-Output $busId
            exit 0
        }

        Write-Host 'Preloader is attached; waiting for its volatile transition to BootROM.'
    }

    Start-Sleep -Milliseconds $PollMilliseconds
}

throw "Timed out waiting for RT7 preloader/BROM after $TimeoutSeconds seconds."

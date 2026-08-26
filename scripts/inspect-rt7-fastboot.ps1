[CmdletBinding()]
param(
    [string]$Container = 'rt7-adb',
    [string]$Image = 'local/oukitel-rt7-android-tools:34.0.4',
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-DockerFastboot {
    param([Parameter(Mandatory = $true)][string[]]$FastbootArguments)

    $command = @('exec', $Container, 'fastboot')
    if ($Serial) {
        $command += @('-s', $Serial)
    }
    $command += $FastbootArguments
    $output = (& docker @command 2>&1 | Out-String).Trim()
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
}

$inspectOutput = & docker inspect $Container --format '{{.State.Running}}|{{.Config.Image}}' 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Android-tools container '$Container' is unavailable."
}
$containerState = ($inspectOutput | Out-String).Trim() -split '\|', 2
if ($containerState.Count -ne 2 -or $containerState[0] -ne 'true') {
    throw "Android-tools container '$Container' is not running."
}
if ($containerState[1] -ne $Image) {
    throw "Android-tools image mismatch: expected '$Image', got '$($containerState[1])'."
}

$devicesResult = Invoke-DockerFastboot -FastbootArguments @('devices')
if ($devicesResult.ExitCode -ne 0) {
    throw "fastboot devices failed: $($devicesResult.Output)"
}
$devices = @(
    $devicesResult.Output -split "`r?`n" |
        Where-Object { $_ -match '^\s*([^\s]+)\s+fastboot\s*$' } |
        ForEach-Object { $Matches[1] }
)
if ($Serial) {
    if ($Serial -notin $devices) {
        throw "Requested fastboot serial '$Serial' is not connected."
    }
} elseif ($devices.Count -ne 1) {
    throw "Exactly one fastboot device is required; found $($devices.Count)."
} else {
    $Serial = $devices[0]
}

$productResult = Invoke-DockerFastboot -FastbootArguments @('getvar', 'product')
if ($productResult.ExitCode -ne 0 -or $productResult.Output -notmatch '(?im)^\s*(?:\(bootloader\)\s*)?product:\s*([^\s]+)') {
    throw "Unable to identify fastboot product: $($productResult.Output)"
}
$product = $Matches[1]
if ($product -notmatch '(?i)(P07|TP758|6853|6893)') {
    throw "Refusing unexpected fastboot product '$product'."
}

$queries = @(
    @('getvar', 'current-slot'),
    @('getvar', 'slot-count'),
    @('getvar', 'unlocked'),
    @('getvar', 'secure'),
    @('getvar', 'max-download-size'),
    @('flashing', 'get_unlock_ability')
)

Write-Host "Validated RT7-family fastboot target: serial=$Serial product=$product"
Write-Host "product: $($productResult.Output)"
foreach ($query in $queries) {
    $result = Invoke-DockerFastboot -FastbootArguments $query
    $label = $query -join ' '
    if ($result.ExitCode -eq 0) {
        Write-Host "${label}: $($result.Output)"
    } else {
        Write-Host "${label}: unsupported or failed ($($result.Output))"
    }
}
Write-Host 'Read-only fastboot inspection complete; no boot, flash, erase, or unlock command ran.'

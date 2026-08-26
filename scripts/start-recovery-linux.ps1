[CmdletBinding()]
param(
    [string]$WorkDir,
    [string]$Serial,
    [string]$AdbContainer = 'rt7-adb',
    [string]$AdbImage = 'local/oukitel-rt7-android-tools:34.0.4',
    [string]$ImageName = 'rt7-debian-bookworm-arm64-recovery-test-v2.ext4',
    [int]$SshPort = 22007,
    [switch]$SkipPush
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $WorkDir) {
    $WorkDir = Join-Path (Split-Path -Parent $repoRoot) 'oukitel-rt7-linux-work'
}

$image = Join-Path (Join-Path $WorkDir 'rootfs') $ImageName
$sshKey = Join-Path (Join-Path $WorkDir 'keys') 'rt7_admin_ed25519'
$knownHosts = Join-Path (Join-Path $WorkDir 'keys') 'rt7_recovery_known_hosts'
$containerImage = "/rt7-work/rootfs/$ImageName"
$containerStarter = '/project/scripts/rt7-recovery-linux-start.sh'
$remoteImage = '/tmp/rt7-debian-recovery-test.ext4'
$remoteStarter = '/tmp/rt7-recovery-linux-start.sh'

foreach ($path in @($image, $sshKey, (Join-Path $PSScriptRoot 'rt7-recovery-linux-start.sh'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}
if ($SshPort -lt 1024 -or $SshPort -gt 65535) {
    throw 'SshPort must be between 1024 and 65535.'
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $command = @(
        'run', '--rm',
        '--network', "container:$AdbContainer",
        '--volume', "${WorkDir}:/rt7-work:ro",
        '--volume', "${repoRoot}:/project:ro",
        '--entrypoint', 'adb',
        $AdbImage
    )
    if ($Serial) {
        $command += @('-s', $Serial)
    }
    $command += $Arguments
    & docker @command
    if ($LASTEXITCODE -ne 0) {
        throw "adb failed with status ${LASTEXITCODE}: $($Arguments -join ' ')"
    }
}

$adbStateOutput = & docker inspect $AdbContainer --format '{{.State.Running}}|{{.Config.Image}}' 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Docker ADB container '$AdbContainer' is unavailable."
}
$adbState = ($adbStateOutput | Out-String).Trim()
$adbParts = $adbState -split '\|', 2
if ($adbParts[0] -ne 'true') {
    throw "Docker ADB container '$AdbContainer' is not running."
}
if ($adbParts[1] -ne $AdbImage) {
    throw "ADB container image mismatch: expected '$AdbImage', got '$($adbParts[1])'."
}

Invoke-Adb get-state
$bootMode = (Invoke-Adb shell getprop ro.bootmode | Out-String).Trim()
$hardware = (Invoke-Adb shell getprop ro.hardware | Out-String).Trim()
if ($bootMode -ne 'recovery') {
    throw "Refusing to continue outside recovery mode (reported '$bootMode')."
}
if ($hardware -ne 'mt6853') {
    throw "Refusing unexpected hardware '$hardware'; expected mt6853."
}

if (-not $SkipPush) {
    $expectedHash = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
    Invoke-Adb push $containerImage $remoteImage
    $actualHashLine = (Invoke-Adb shell sha256sum $remoteImage | Out-String).Trim()
    $actualHash = ($actualHashLine -split '\s+')[0].ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Transferred ext4 hash mismatch: expected $expectedHash, got $actualHash"
    }
    Invoke-Adb push $containerStarter $remoteStarter
}

Invoke-Adb shell chmod 0755 $remoteStarter
Invoke-Adb shell $remoteStarter $remoteImage
Invoke-Adb forward "tcp:$SshPort" tcp:22

$sshArguments = @(
    '-i', $sshKey,
    '-p', $SshPort,
    '-o', 'BatchMode=yes',
    '-o', 'ConnectTimeout=2',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', "UserKnownHostsFile=$knownHosts",
    'rt7@127.0.0.1',
    'sudo /usr/local/sbin/rt7-healthcheck'
)

for ($attempt = 1; $attempt -le 30; $attempt++) {
    & ssh @sshArguments
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Recovery Debian is ready: ssh -i `"$sshKey`" -p $SshPort rt7@127.0.0.1"
        exit 0
    }
    Start-Sleep -Seconds 1
}

throw 'SSH/Docker health check did not pass within 30 seconds.'

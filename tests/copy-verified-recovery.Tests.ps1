$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/copy-verified-recovery.ps1')).Path
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count) {
    throw "PowerShell parse errors:`n$($parseErrors | Out-String)"
}

$source = Get-Content -LiteralPath $scriptPath -Raw
$requiredGuards = @(
    'Source and destination resolve to the same physical disk',
    'Refusing to overwrite an existing recovery path',
    'Capture manifest and SHA256SUMS disagree',
    'SHA256SUMS contains a duplicate artifact path',
    'Captured artifact hash mismatch',
    'Independent recovery copy hash mismatch',
    "if (-not `$Execute)"
)
foreach ($guard in $requiredGuards) {
    if (-not $source.Contains($guard)) {
        throw "Recovery copy guard is missing: $guard"
    }
}
if ($source -match '\bRemove-Item\b') {
    throw 'Recovery copy helper must leave an incomplete staging copy for inspection.'
}

$testRoot = [IO.Path]::GetFullPath([IO.Path]::Combine(
    [IO.Path]::GetTempPath(),
    ('rt7-copy-test-' + [guid]::NewGuid().ToString('N'))
))
$sourceDirectory = Join-Path $testRoot 'rt7-test-capture'
$destinationRoot = Join-Path $testRoot 'destination'
$global:Rt7CopyPartitionCall = 0

function global:Get-Partition {
    param([Parameter(Mandatory = $true)][char]$DriveLetter)

    $global:Rt7CopyPartitionCall++
    [pscustomobject]@{ DiskNumber = $global:Rt7CopyPartitionCall }
}

function global:Get-Disk {
    param([Parameter(Mandatory = $true)][int]$Number)

    [pscustomobject]@{
        Number = $Number
        FriendlyName = "RT7 test disk $Number"
    }
}

try {
    New-Item -ItemType Directory -Path (
        (Join-Path $sourceDirectory 'pass1'),
        (Join-Path $sourceDirectory 'pass2'),
        $destinationRoot
    ) | Out-Null
    $payload = [Text.Encoding]::ASCII.GetBytes('verified-rt7-test')
    foreach ($passName in @('pass1', 'pass2')) {
        [IO.File]::WriteAllBytes(
            (Join-Path $sourceDirectory "$passName/test.bin"),
            $payload
        )
    }
    $hash = (Get-FileHash -LiteralPath (
        Join-Path $sourceDirectory 'pass1/test.bin'
    ) -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        format = 2
        read_passes = @('pass1', 'pass2')
        artifacts = [ordered]@{
            'test.bin' = [ordered]@{
                size = $payload.Length
                sha256 = $hash
                verified_copies = 2
            }
        }
    }
    [IO.File]::WriteAllText(
        (Join-Path $sourceDirectory 'capture-manifest.json'),
        (($manifest | ConvertTo-Json -Depth 8) + "`n"),
        [Text.Encoding]::ASCII
    )
    [IO.File]::WriteAllText(
        (Join-Path $sourceDirectory 'SHA256SUMS.txt'),
        "$hash  pass1/test.bin`n$hash  pass2/test.bin`n",
        [Text.Encoding]::ASCII
    )

    & $scriptPath `
        -SourceDirectory $sourceDirectory `
        -DestinationRoot $destinationRoot `
        -Execute

    $copy = Join-Path $destinationRoot 'rt7-test-capture'
    if (-not (Test-Path -LiteralPath $copy -PathType Container)) {
        throw 'Verified recovery copy was not published from staging.'
    }
    if (Test-Path -LiteralPath "$copy.copying") {
        throw 'Successful recovery copy left a staging directory behind.'
    }
    $copiedHash = (Get-FileHash -LiteralPath (
        Join-Path $copy 'pass2/test.bin'
    ) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($copiedHash -ne $hash) {
        throw 'Published recovery copy does not match the fixture hash.'
    }

    [IO.File]::WriteAllText(
        (Join-Path $sourceDirectory 'SHA256SUMS.txt'),
        "$hash  pass1/test.bin`n$hash  pass1/test.bin`n",
        [Text.Encoding]::ASCII
    )
    try {
        & $scriptPath `
            -SourceDirectory $sourceDirectory `
            -DestinationRoot $destinationRoot
        throw 'Duplicate recovery checksum fixture unexpectedly passed.'
    } catch {
        if ($_.Exception.Message -notmatch 'duplicate artifact path') {
            throw
        }
    }
} finally {
    Remove-Item function:global:Get-Partition -ErrorAction SilentlyContinue
    Remove-Item function:global:Get-Disk -ErrorAction SilentlyContinue
    Remove-Variable Rt7CopyPartitionCall -Scope Global -ErrorAction SilentlyContinue

    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $testRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test cleanup target escaped the system temporary directory.'
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

Write-Host 'Independent recovery copy static and runtime safety checks: PASS'

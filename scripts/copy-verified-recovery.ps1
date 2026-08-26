[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot,

    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-PhysicalDiskForPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $qualifier = Split-Path -Path $Path -Qualifier
    if ($qualifier -notmatch '^(?<letter>[A-Za-z]):$') {
        throw "A local drive-letter path is required: $Path"
    }
    $partitions = @(Get-Partition -DriveLetter $Matches['letter'])
    if ($partitions.Count -ne 1) {
        throw "Exactly one partition must resolve drive $qualifier."
    }
    Get-Disk -Number $partitions[0].DiskNumber
}

function Get-RelativeArtifactPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ManifestPath
    )

    if ([IO.Path]::IsPathRooted($ManifestPath)) {
        throw "Checksum manifest contains an absolute path: $ManifestPath"
    }
    $nativePath = $ManifestPath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $Root $nativePath))
    $prefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar) +
        [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Checksum manifest path escapes the capture directory: $ManifestPath"
    }
    $fullPath
}

$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$destinationRootPath = (Resolve-Path -LiteralPath $DestinationRoot).Path
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Source capture directory does not exist: $source"
}
if (-not (Test-Path -LiteralPath $destinationRootPath -PathType Container)) {
    throw "Destination root does not exist: $destinationRootPath"
}

$sourceDisk = Get-PhysicalDiskForPath -Path $source
$destinationDisk = Get-PhysicalDiskForPath -Path $destinationRootPath
if ($sourceDisk.Number -eq $destinationDisk.Number) {
    throw "Source and destination resolve to the same physical disk $($sourceDisk.Number)."
}

$captureManifestPath = Join-Path $source 'capture-manifest.json'
$checksumManifestPath = Join-Path $source 'SHA256SUMS.txt'
foreach ($requiredPath in @($captureManifestPath, $checksumManifestPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Verified capture metadata is missing: $requiredPath"
    }
}

$captureManifest = Get-Content -LiteralPath $captureManifestPath -Raw | ConvertFrom-Json
if ([int]$captureManifest.format -ne 2) {
    throw "Unsupported capture manifest format: $($captureManifest.format)"
}
$readPasses = @($captureManifest.read_passes)
$artifactProperties = @($captureManifest.artifacts.PSObject.Properties)
if (($readPasses -join ',') -ne 'pass1,pass2' -or $artifactProperties.Count -eq 0) {
    throw 'Capture manifest does not describe two verified read passes.'
}

$expectedChecksums = @{}
foreach ($artifactProperty in $artifactProperties) {
    $artifactName = [string]$artifactProperty.Name
    $artifact = $artifactProperty.Value
    $artifactHash = [string]$artifact.sha256
    if (
        $artifactName -notmatch '^[A-Za-z0-9._-]+$' -or
        $artifactHash -notmatch '^[0-9a-fA-F]{64}$' -or
        [int]$artifact.verified_copies -ne 2 -or
        [long]$artifact.size -lt 0
    ) {
        throw "Invalid verified artifact metadata: $artifactName"
    }
    foreach ($passName in $readPasses) {
        $expectedChecksums["$passName/$artifactName"] = @{
            Hash = $artifactHash
            Size = [long]$artifact.size
        }
    }
}

$checksumLines = @(Get-Content -LiteralPath $checksumManifestPath)
$expectedChecksumCount = $expectedChecksums.Count
if ($checksumLines.Count -ne $expectedChecksumCount) {
    throw "SHA256SUMS contains $($checksumLines.Count) entries; expected $expectedChecksumCount."
}

$seenChecksums = [System.Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
foreach ($line in $checksumLines) {
    if ($line -notmatch '^(?<hash>[0-9a-fA-F]{64})  (?<path>.+)$') {
        throw "Invalid SHA256SUMS line: $line"
    }
    $listedHash = $Matches['hash']
    $listedPath = $Matches['path'].Replace('\', '/')
    if (-not $expectedChecksums.ContainsKey($listedPath)) {
        throw "SHA256SUMS contains an unexpected artifact path: $listedPath"
    }
    if (-not $seenChecksums.Add($listedPath)) {
        throw "SHA256SUMS contains a duplicate artifact path: $listedPath"
    }
    $expected = $expectedChecksums[$listedPath]
    if ($listedHash -ine $expected.Hash) {
        throw "Capture manifest and SHA256SUMS disagree for: $listedPath"
    }
    $artifactPath = Get-RelativeArtifactPath -Root $source -ManifestPath $listedPath
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "Captured artifact is missing: $artifactPath"
    }
    if ((Get-Item -LiteralPath $artifactPath).Length -ne $expected.Size) {
        throw "Captured artifact size mismatch: $artifactPath"
    }
    $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
    if ($actualHash -ine $listedHash) {
        throw "Captured artifact hash mismatch: $artifactPath"
    }
}

$destination = Join-Path $destinationRootPath (Split-Path -Leaf $source)
$staging = "$destination.copying"
foreach ($path in @($destination, $staging)) {
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to overwrite an existing recovery path: $path"
    }
}

Write-Host "Verified $expectedChecksumCount artifact hashes in the source capture."
Write-Host (
    "Independent disks: source $($sourceDisk.Number) ($($sourceDisk.FriendlyName)); " +
    "destination $($destinationDisk.Number) ($($destinationDisk.FriendlyName))."
)
Write-Host "Planned destination: $destination"
if (-not $Execute) {
    Write-Host 'Dry run only; pass -Execute to create and verify the independent copy.'
    return
}

New-Item -ItemType Directory -Path $staging | Out-Null
Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $staging -Recurse

$sourceFiles = @(Get-ChildItem -LiteralPath $source -Recurse -Force -File)
foreach ($sourceFile in $sourceFiles) {
    $relativePath = [IO.Path]::GetRelativePath($source, $sourceFile.FullName)
    $copiedPath = Join-Path $staging $relativePath
    if (-not (Test-Path -LiteralPath $copiedPath -PathType Leaf)) {
        throw "Copied recovery file is missing: $copiedPath"
    }
    $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
    $copiedHash = (Get-FileHash -LiteralPath $copiedPath -Algorithm SHA256).Hash
    if ($sourceHash -ine $copiedHash) {
        throw "Independent recovery copy hash mismatch: $relativePath"
    }
}

Move-Item -LiteralPath $staging -Destination $destination
Write-Host "Verified independent recovery copy: $destination"

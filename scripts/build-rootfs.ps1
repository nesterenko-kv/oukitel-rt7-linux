[CmdletBinding()]
param(
    [string]$WorkDir,
    [string]$OutputName = 'rt7-debian-bookworm-arm64.rootfs.tar',
    [switch]$SkipExport
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $WorkDir) {
    $WorkDir = Join-Path (Split-Path -Parent $repoRoot) 'oukitel-rt7-linux-work'
}
$rootfsDir = Join-Path $WorkDir 'rootfs'
$output = Join-Path $rootfsDir $OutputName
$image = 'local/oukitel-rt7-rootfs:bookworm'

if ($OutputName -notmatch '^[A-Za-z0-9._-]+\.tar$') {
    throw 'OutputName must be a plain .tar filename.'
}

New-Item -ItemType Directory -Path $rootfsDir -Force | Out-Null

& docker buildx build `
    --platform linux/arm64 `
    --provenance=false `
    --output "type=docker,name=$image" `
    (Join-Path $repoRoot 'rootfs')
if ($LASTEXITCODE -ne 0) {
    throw "ARM64 rootfs image build failed with status $LASTEXITCODE."
}

& docker run --rm --privileged `
    --platform linux/arm64 `
    --cgroupns host `
    --volume "${repoRoot}:/project:ro" `
    --entrypoint /bin/sh `
    $image `
    /project/rootfs/smoke-test.sh
if ($LASTEXITCODE -ne 0) {
    throw "ARM64 rootfs smoke test failed with status $LASTEXITCODE."
}

if ($SkipExport) {
    Write-Host 'Image and smoke test completed; tar export skipped.'
    exit 0
}

if (Test-Path -LiteralPath $output) {
    throw "Refusing to overwrite $output"
}

& docker buildx build `
    --platform linux/arm64 `
    --provenance=false `
    --output "type=tar,dest=$output" `
    (Join-Path $repoRoot 'rootfs')
if ($LASTEXITCODE -ne 0) {
    throw "ARM64 rootfs tar export failed with status $LASTEXITCODE."
}

$artifact = Get-Item -LiteralPath $output
$sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Rootfs tar: $($artifact.FullName)"
Write-Host "Size: $($artifact.Length)"
Write-Host "SHA256: $sha256"

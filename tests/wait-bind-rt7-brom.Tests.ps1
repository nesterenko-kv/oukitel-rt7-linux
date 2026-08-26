$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../scripts/wait-bind-rt7-brom.ps1')).Path
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

# PowerShell variable names are case-insensitive. `$pid` therefore collides
# with the read-only automatic `$PID` variable and fails before USB polling.
$automaticPidReferences = @($ast.FindAll(
    {
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.VariablePath.UserPath -ieq 'pid'
    },
    $true
))
if ($automaticPidReferences.Count) {
    throw 'The helper must not assign or reference a task variable named $pid.'
}

$source = Get-Content -LiteralPath $scriptPath -Raw
if (-not $source.Contains("`$bindArguments += @('--busid', `$busId)")) {
    throw 'The helper no longer force-binds the exact validated BUSID.'
}
if ($source.Contains("`$bindArguments += @('--hardware-id'")) {
    throw 'The unreliable usbipd forced hardware-ID bind returned.'
}
if (-not $source.Contains('[int]$PollMilliseconds = 25')) {
    throw 'The subsecond RT7 BootROM polling default changed unexpectedly.'
}

Write-Host 'RT7 BootROM helper static safety checks: PASS'

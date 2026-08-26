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

$global:Rt7UsbipdTestCalls = [System.Collections.Generic.List[string]]::new()
function global:usbipd.exe {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $joined = $Arguments -join ' '
    $global:Rt7UsbipdTestCalls.Add($joined)
    $global:LASTEXITCODE = 0
    switch ($Arguments[0]) {
        'state' {
            @{
                Devices = @(
                    @{
                        BusId = '3-4'
                        ClientIPAddress = $null
                        Description = 'Unknown device'
                        InstanceId = 'USB\VID_0E8D&PID_0003\RT7BROMTEST'
                        IsForced = $true
                        PersistedGuid = '00000000-0000-0000-0000-000000000003'
                        StubInstanceId = $null
                    }
                )
            } | ConvertTo-Json -Depth 4
        }
        'attach' {}
        default { throw "Unexpected fake usbipd call: $joined" }
    }
}

try {
    $result = @(& $scriptPath -Execute -Force -TimeoutSeconds 5 -PollMilliseconds 10)
    if ($result[-1] -ne '3-4') {
        throw "Expected BUSID 3-4 from the attached BootROM helper, got: $result"
    }
    $attachCalls = @($global:Rt7UsbipdTestCalls | Where-Object {
        $_ -eq 'attach --wsl docker-desktop --busid 3-4'
    })
    if ($attachCalls.Count -ne 1) {
        throw "Expected one exact BootROM attach call, got: $($global:Rt7UsbipdTestCalls -join ', ')"
    }
    $mutations = @($global:Rt7UsbipdTestCalls | Where-Object {
        $_ -match '^(?:bind|unbind)\b'
    })
    if ($mutations.Count) {
        throw "Already forced BootROM must not mutate USB bindings: $($mutations -join ', ')"
    }
} finally {
    Remove-Item function:global:usbipd.exe -ErrorAction SilentlyContinue
    Remove-Variable Rt7UsbipdTestCalls -Scope Global -ErrorAction SilentlyContinue
}

Write-Host 'RT7 BootROM helper static and attach-flow safety checks: PASS'

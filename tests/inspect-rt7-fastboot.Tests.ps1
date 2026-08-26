$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$global:Rt7FastbootTestCalls = [System.Collections.Generic.List[string]]::new()

function global:docker {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $joined = $Arguments -join ' '
    $global:Rt7FastbootTestCalls.Add($joined)
    $global:LASTEXITCODE = 0
    switch -Regex ($joined) {
        '^inspect rt7-adb --format ' {
            'true|local/oukitel-rt7-android-tools:34.0.4'
        }
        '^exec rt7-adb fastboot devices$' {
            "RT7TESTSERIAL`tfastboot"
        }
        '^exec rt7-adb fastboot -s RT7TESTSERIAL getvar product$' {
            '(bootloader) product: tP758'
        }
        '^exec rt7-adb fastboot -s RT7TESTSERIAL getvar current-slot$' {
            '(bootloader) current-slot: a'
        }
        '^exec rt7-adb fastboot -s RT7TESTSERIAL getvar slot-count$' {
            '(bootloader) slot-count: 2'
        }
        '^exec rt7-adb fastboot -s RT7TESTSERIAL getvar unlocked$' {
            '(bootloader) unlocked: no'
        }
        '^exec rt7-adb fastboot -s RT7TESTSERIAL getvar secure$' {
            '(bootloader) secure: yes'
        }
        '^exec rt7-adb fastboot -s RT7TESTSERIAL getvar max-download-size$' {
            '(bootloader) max-download-size: 0x10000000'
        }
        '^exec rt7-adb fastboot -s RT7TESTSERIAL flashing get_unlock_ability$' {
            '(bootloader) get_unlock_ability: 1'
        }
        default {
            $global:LASTEXITCODE = 1
            "unexpected fake docker call: $joined"
        }
    }
}

try {
    & (Join-Path $PSScriptRoot '../scripts/inspect-rt7-fastboot.ps1')
    if ($global:Rt7FastbootTestCalls.Count -ne 9) {
        throw "Expected 9 fixed inspection calls, got $($global:Rt7FastbootTestCalls.Count)."
    }
    $dangerous = @(
        $global:Rt7FastbootTestCalls | Where-Object {
            $_ -match '\bfastboot\b.*\s(?:boot|flash|erase)\b' -or
            $_ -match '\bflashing\s+(?:unlock|lock)\s*$'
        }
    )
    if ($dangerous.Count) {
        throw "Dangerous fastboot call generated: $($dangerous -join ', ')"
    }
    Write-Host 'Guarded fastboot inspection mock: PASS'
} finally {
    Remove-Item function:global:docker -ErrorAction SilentlyContinue
    Remove-Variable Rt7FastbootTestCalls -Scope Global -ErrorAction SilentlyContinue
}

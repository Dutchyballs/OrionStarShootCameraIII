$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$panelPath = Join-Path $projectRoot 'Orion StarShoot Control.ps1'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $panelPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-List
    throw 'The Orion control panel has PowerShell syntax errors.'
}
Write-Output 'PANEL_PARSE_OK'

$contractTests = @(
    'test-preview-startup-guard.ps1',
    'test-bridge-keepalive-contract.ps1',
    'test-attach-retry-contract.ps1',
    'test-sensor-readiness-contract.ps1'
)

foreach ($testName in $contractTests) {
    $testPath = Join-Path $PSScriptRoot $testName
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $testPath -PanelPath $panelPath
    if ($LASTEXITCODE -ne 0) {
        throw "$testName failed with code $LASTEXITCODE."
    }
}

Write-Output 'ALL_ORION_SELF_TESTS_OK'

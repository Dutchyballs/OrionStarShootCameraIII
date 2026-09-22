param(
    [Parameter(Mandatory = $true)]
    [string]$PanelPath
)

$ErrorActionPreference = 'Stop'
$output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PanelPath -SelfTest 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Panel self-test failed: $([string]::Join([Environment]::NewLine, @($output)))"
}

$line = [string]::Join(' ', @($output))
Write-Output $line
if ($line -notmatch 'SENSOR_READY_TIMEOUT=30') {
    throw 'Panel does not allow the cold sensor up to 30 seconds to register.'
}

Write-Output 'SENSOR_READINESS_CONTRACT_TEST_OK'

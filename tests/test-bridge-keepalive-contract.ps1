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
if ($line -notmatch 'BRIDGE_KEEPALIVE=READY') {
    throw 'Panel does not own a camera-bridge keep-alive for its full lifetime.'
}

Write-Output 'BRIDGE_KEEPALIVE_CONTRACT_TEST_OK'

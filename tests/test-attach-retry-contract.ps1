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
if ($line -notmatch 'ATTACH_RETRY_LIMIT=3') {
    throw 'Panel does not retry the transient USB attach race three times.'
}

Write-Output 'ATTACH_RETRY_CONTRACT_TEST_OK'

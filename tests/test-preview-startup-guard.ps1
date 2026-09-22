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
if ($line -notmatch 'PREVIEW_STARTUP_GUARD=OK') {
    throw 'Panel does not verify that a preview process stays alive during startup.'
}
if ($line -notmatch 'PREVIEW_RETRY_LIMIT=2') {
    throw 'Panel does not advertise the required one automatic preview retry.'
}

Write-Output 'PREVIEW_STARTUP_GUARD_TEST_OK'

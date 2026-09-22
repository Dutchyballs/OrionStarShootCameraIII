param(
    [string]$PanelPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Orion StarShoot Control.ps1')
)

# Requires an installed WSL distro, but never attaches USB or opens a camera.
$ErrorActionPreference = 'Stop'
. $PanelPath -SelfTest
try {
    if (-not (Start-OrionBridgeKeepAlive)) {
        throw 'The panel could not launch its configured WSL distro.'
    }
    if (-not (Test-ProcessRunning $script:BridgeKeepAliveProcess)) {
        throw 'The WSL keep-alive exited unexpectedly.'
    }
    Write-Output 'WSL_PROCESS_LAUNCH_OK'
}
finally {
    Stop-OrionBridgeKeepAlive
}

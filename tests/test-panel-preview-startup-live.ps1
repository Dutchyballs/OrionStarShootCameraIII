param(
    [Parameter(Mandatory = $true)]
    [string]$PanelPath
)

$ErrorActionPreference = 'Stop'
. $PanelPath -SelfTest
$ErrorActionPreference = 'Continue'

try {
    if (-not (Connect-OrionCamera)) {
        throw 'The panel could not connect the Orion camera for the live startup test.'
    }

    for ($cycle = 1; $cycle -le 2; $cycle++) {
        Write-Output "PANEL_PREVIEW_CYCLE=$cycle START"
        $process = Start-OrionPreviewAttempt -Crosshair 'on'
        if (-not (Test-ProcessRunning $process)) {
            throw "Preview cycle $cycle did not stay alive through the startup guard."
        }
        Write-Output "PANEL_PREVIEW_CYCLE=$cycle VERIFIED_OPEN"

        $null = Invoke-OrionCommand -CameraArguments @('stop-preview') -IgnoreError
        if (-not $process.WaitForExit(10000)) {
            throw "Preview cycle $cycle did not exit cleanly."
        }
        try { $process.Dispose() } catch { }
        $script:PreviewProcess = $null
        Write-Output "PANEL_PREVIEW_CYCLE=$cycle CLOSED"
    }

    Start-Sleep -Seconds 12
    $bridgeState = (Get-OrionUsbDevice).State
    Write-Output "BRIDGE_AFTER_IDLE=$bridgeState"
    if ($bridgeState -ne 'Attached') {
        throw "Camera bridge did not stay attached while the panel was idle (state: $bridgeState)."
    }
    if (-not (Test-ProcessRunning $script:BridgeKeepAliveProcess)) {
        throw 'Camera bridge keep-alive process stopped while the panel was open.'
    }

    Write-Output 'PANEL_REPEATED_PREVIEW_STARTUP_TEST_OK'
}
finally {
    Stop-OrionBridgeKeepAlive
}

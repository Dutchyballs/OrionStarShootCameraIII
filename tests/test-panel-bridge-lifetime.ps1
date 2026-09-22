param(
    [Parameter(Mandatory = $true)]
    [string]$PanelPath,

    [int]$SettleSeconds = 20
)

$ErrorActionPreference = 'Stop'
$usbipdCommand = Get-Command usbipd.exe -ErrorAction SilentlyContinue
$usbipd = if ($null -ne $usbipdCommand) { $usbipdCommand.Source } else { Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe' }
$panel = $null

function Get-OrionState {
    $lines = & $usbipd list 2>&1
    foreach ($lineObject in $lines) {
        $line = [string]$lineObject
        if ($line -match '^\s*\S+\s+0e96:c001\s+' -and $line -match '\s+(Not shared|Shared|Attached)\s*$') {
            return $Matches[1]
        }
    }
    return 'Missing'
}

try {
    $panel = Start-Process -FilePath powershell.exe -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PanelPath)
    ) -PassThru

    $attached = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ((Get-OrionState) -eq 'Attached') {
            $attached = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $attached) { throw 'Panel did not attach the Orion camera.' }

    Start-Sleep -Seconds $SettleSeconds
    $finalState = Get-OrionState
    Write-Output "FINAL_USB_STATE=$finalState"
    if ($finalState -ne 'Attached') {
        throw "Camera bridge went to sleep while the panel stayed open (state: $finalState)."
    }
    Write-Output 'PANEL_BRIDGE_LIFETIME_TEST_OK'
}
finally {
    if ($null -ne $panel -and -not $panel.HasExited) {
        Stop-Process -Id $panel.Id -Force -ErrorAction SilentlyContinue
    }
}

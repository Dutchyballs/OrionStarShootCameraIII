[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$NoDialog,
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distro = $(if ($env:ORION_WSL_DISTRO) { $env:ORION_WSL_DISTRO } else { 'Ubuntu-24.04' })
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$panelPath = Join-Path $repo 'Orion StarShoot Control.ps1'
$cameraPath = Join-Path $repo 'orion-camera.sh'
if ($cameraPath -notmatch '^([A-Za-z]):\\(.*)$') { throw 'The camera installation must be on a local Windows drive.' }
$cameraScript = '/mnt/' + $Matches[1].ToLowerInvariant() + '/' + $Matches[2].Replace('\', '/')
$usbipd = Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe'
Import-Module (Join-Path $PSScriptRoot 'OrionPreviewRecovery.psm1') -Force
if (-not $PSCmdlet.ShouldProcess('Orion camera and its control panel', 'Stop preview, repair display if needed, reconnect and reopen')) { return }

$logDir = Join-Path $env:LOCALAPPDATA 'OrionStarShootCameraIII\logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logPath = Join-Path $logDir ('restart-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
$bridge = $null
$transcriptStarted = $false

function Get-RestartCamera {
    $lines = @(& $usbipd list 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the USB camera list.' }
    $matchesFound = @($lines | Where-Object { [string]$_ -match '^\s*\S+\s+0e96:c001\s+' })
    if ($matchesFound.Count -ne 1) { throw 'Exactly one Orion (0e96:c001) must be connected. If Windows lost its identity, unplug only the camera, wait ten seconds and reconnect.' }
    $line = [string]$matchesFound[0]
    $null = $line -match '^\s*(\S+)\s+'
    $busId = $Matches[1]
    if ($line -match '\s+Not shared\s*$') { throw 'Share this camera first using Bind Orion Camera as Administrator.cmd.' }
    [pscustomobject]@{ BusId = $busId; Attached = $line -match '\s+Attached\s*$' }
}

try {
    Start-Transcript -Path $logPath | Out-Null
    $transcriptStarted = $true
    $device = Get-RestartCamera
    # Hold WSL open while replacing the old panel's own keep-alive.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'wsl.exe'
    $startInfo.Arguments = "-d $Distro -u root -- sleep 2147483647"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $bridge = [System.Diagnostics.Process]::Start($startInfo)
    if ($bridge.WaitForExit(1500)) { throw 'The Linux camera environment could not start.' }

    & wsl.exe -d $Distro -u root -- bash $cameraScript can-restart
    if ($LASTEXITCODE -ne 0) { throw 'A recording is running. Stop it before restarting the camera.' }

    if ($device.Attached) {
        # This stops only the tracked preview. A recording or another client
        # keeps the device busy and aborts the restart without being killed.
        & wsl.exe -d $Distro -u root -- bash $cameraScript stop-preview
        if ($LASTEXITCODE -ne 0) { throw 'Camera is busy or could not stop safely. Stop recording and close other camera clients, then retry.' }
    }

    $panelPattern = '(?i)(?:^|\s)-File\s+(?:"' + [regex]::Escape($panelPath) + '"|' + [regex]::Escape($panelPath) + ')(?:\s|$)'
    $sessionId = (Get-Process -Id $PID).SessionId
    $panels = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" | Where-Object {
        $_.SessionId -eq $sessionId -and $_.ProcessId -ne $PID -and
        $_.CommandLine -match $panelPattern -and $_.CommandLine -notmatch '(?i)(?:^|\s)-SelfTest(?:\s|$)'
    })
    foreach ($panel in $panels) {
        & taskkill.exe /PID $panel.ProcessId /T /F
        if ($LASTEXITCODE -ne 0) { throw 'Could not close the previous Orion panel.' }
    }

    $null = Repair-OrionPreviewDisplay -Distro $Distro -CameraScript $cameraScript
    $device = Get-RestartCamera
    if ($device.Attached) {
        & $usbipd detach --busid $device.BusId
        if ($LASTEXITCODE -ne 0) { throw 'Could not detach the Orion camera safely.' }
        Start-Sleep -Milliseconds 700
    }
    $device = Get-RestartCamera
    & $usbipd attach --wsl --busid $device.BusId
    if ($LASTEXITCODE -ne 0) { throw 'Orion USB attachment failed. Check the restart log and camera lead.' }

    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $panelPath + '" -Distro ' + $Distro
    $newPanel = Start-Process powershell.exe -WindowStyle Normal -ArgumentList $arguments -PassThru
    if ($newPanel.WaitForExit(10000)) { throw 'The replacement camera panel stopped during startup.' }
    Write-Output 'ORION_RESTART_OK - panel reopened; press Live Preview.'
}
catch {
    $message = $_.Exception.Message + "`r`n`r`nRestart log: " + $logPath
    Write-Output $message
    if (-not $NoDialog) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($message, 'Orion camera restart', 'OK', 'Error') | Out-Null
    }
    exit 1
}
finally {
    if ($null -ne $bridge) {
        try {
            if (-not $bridge.HasExited) { $bridge.Kill(); $null = $bridge.WaitForExit(3000) }
            $bridge.Dispose()
        } catch { }
    }
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
}

param(
    [switch]$SelfTest,
    [string]$Distro = $(if ($env:ORION_WSL_DISTRO) { $env:ORION_WSL_DISTRO } else { 'Ubuntu-24.04' })
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CaptureDir = Join-Path $script:AppDir 'captures'
$usbipdCommand = Get-Command usbipd.exe -ErrorAction SilentlyContinue
$script:Usbipd = if ($null -ne $usbipdCommand) { $usbipdCommand.Source } else { Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe' }
$script:Distro = $Distro
# WSL 2.7 treats unnecessary quotes around a simple distro name literally
# when launched via ProcessStartInfo. Retain quoting for names that need it.
$script:DistroArgument = if ($Distro -match '^[A-Za-z0-9._-]+$') { $Distro } else { '"' + $Distro.Replace('"', '\"') + '"' }
$script:CameraScriptWindows = Join-Path $script:AppDir 'orion-camera.sh'
$script:CameraScriptWsl = $null
$script:PreviewProcess = $null
$script:RecordingProcess = $null
$script:RecordingOutput = $null
$script:RecordingStartedAt = $null
$script:RecordingEndsAt = $null
$script:RecordingSeconds = 0
$script:UpdatingExposureUi = $false
$script:CameraConnected = $false
$script:PreviewRetryLimit = 2
$script:BridgeKeepAliveProcess = $null
$script:AttachRetryLimit = 3
$script:SensorReadyTimeoutSeconds = 30
$script:LastCameraExitCode = 0

New-Item -ItemType Directory -Path $script:CaptureDir -Force | Out-Null

function Convert-ToWslPath {
    param([Parameter(Mandatory = $true)][string]$WindowsPath)
    $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
    if ($fullPath -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Only local Windows drive paths are supported: $fullPath"
    }
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2].Replace('\', '/')
    return "/mnt/$drive/$rest"
}

$script:CameraScriptWsl = Convert-ToWslPath $script:CameraScriptWindows

$background = [System.Drawing.Color]::FromArgb(20, 25, 34)
$surface = [System.Drawing.Color]::FromArgb(34, 43, 56)
$surfaceRaised = [System.Drawing.Color]::FromArgb(44, 56, 73)
$textPrimary = [System.Drawing.Color]::FromArgb(244, 247, 251)
$textSecondary = [System.Drawing.Color]::FromArgb(186, 197, 211)
$accent = [System.Drawing.Color]::FromArgb(87, 181, 255)
$success = [System.Drawing.Color]::FromArgb(80, 214, 143)
$warning = [System.Drawing.Color]::FromArgb(255, 191, 78)
$danger = [System.Drawing.Color]::FromArgb(222, 75, 91)

$fontName = 'Segoe UI Variable Text'
try {
    $null = New-Object System.Drawing.Font($fontName, 10)
}
catch {
    $fontName = 'Segoe UI'
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Orion StarShoot Planetary Deck'
$form.ClientSize = New-Object System.Drawing.Size(790, 748)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.BackColor = $background
$form.ForeColor = $textPrimary
$form.Font = New-Object System.Drawing.Font($fontName, 10)
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$title = New-Object System.Windows.Forms.Label
$title.Text = 'ORION STARSHOOT  -  PLANETARY DECK'
$title.Location = New-Object System.Drawing.Point(28, 18)
$title.Size = New-Object System.Drawing.Size(730, 34)
$title.Font = New-Object System.Drawing.Font($fontName, 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $accent
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Telescope-ready preview, exposure presets, snapshots and planetary AVI capture'
$subtitle.Location = New-Object System.Drawing.Point(30, 54)
$subtitle.Size = New-Object System.Drawing.Size(730, 24)
$subtitle.ForeColor = $textSecondary
$form.Controls.Add($subtitle)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(28, 88)
$statusPanel.Size = New-Object System.Drawing.Size(734, 76)
$statusPanel.BackColor = $surface
$form.Controls.Add($statusPanel)

$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = [char]0x25CF
$statusDot.Location = New-Object System.Drawing.Point(16, 13)
$statusDot.Size = New-Object System.Drawing.Size(25, 30)
$statusDot.Font = New-Object System.Drawing.Font($fontName, 15)
$statusPanel.Controls.Add($statusDot)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = 'Checking camera...'
$statusLabel.Location = New-Object System.Drawing.Point(46, 17)
$statusLabel.Size = New-Object System.Drawing.Size(660, 44)
$statusPanel.Controls.Add($statusLabel)

function Set-Status {
    param([string]$Text, [ValidateSet('info', 'good', 'busy', 'error')][string]$State = 'info')
    $statusLabel.Text = $Text
    switch ($State) {
        'good'  { $statusDot.ForeColor = $success }
        'busy'  { $statusDot.ForeColor = $warning }
        'error' { $statusDot.ForeColor = $danger }
        default { $statusDot.ForeColor = $accent }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Failure {
    param([string]$Message)
    Set-Status $Message 'error'
    if ($SelfTest) { throw $Message }
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Orion StarShoot Planetary Deck',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Invoke-OrionCommand {
    param(
        [Parameter(Mandatory = $true)][string[]]$CameraArguments,
        [switch]$IgnoreError
    )
    $nativeArguments = @('-d', $script:Distro, '-u', 'root', '--', 'bash', $script:CameraScriptWsl) + $CameraArguments
    $output = & wsl.exe @nativeArguments 2>&1
    $exitCode = $LASTEXITCODE
    $script:LastCameraExitCode = $exitCode
    if ($exitCode -ne 0 -and -not $IgnoreError) {
        $message = [string]::Join("`n", @($output))
        if ([string]::IsNullOrWhiteSpace($message)) { $message = "Camera command failed with code $exitCode." }
        throw $message
    }
    return @($output)
}

function Wait-OrionSensorReady {
    $deadline = [DateTime]::UtcNow.AddSeconds($script:SensorReadyTimeoutSeconds)
    do {
        $null = Invoke-OrionCommand -CameraArguments @('check') -IgnoreError
        if ($script:LastCameraExitCode -eq 0) { return $true }
        Start-Sleep -Milliseconds 500
    }
    while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

function Get-OrionUsbDevice {
    if (-not (Test-Path -LiteralPath $script:Usbipd)) {
        throw 'usbipd-win is not installed. Install it before connecting the camera.'
    }
    $lines = & $script:Usbipd list 2>&1
    foreach ($lineObject in $lines) {
        $line = [string]$lineObject
        if ($line -match '^\s*(\S+)\s+0e96:c001\s+') {
            $busId = $Matches[1]
            $state = 'Unknown'
            if ($line -match '\s+Not shared\s*$') { $state = 'Not shared' }
            elseif ($line -match '\s+Shared\s*$') { $state = 'Shared' }
            elseif ($line -match '\s+Attached\s*$') { $state = 'Attached' }
            return [pscustomobject]@{ BusId = $busId; State = $state; Line = $line }
        }
    }
    return $null
}

function Attach-OrionCameraWithRetry {
    param([Parameter(Mandatory = $true)][string]$BusId)

    $lastMessage = 'The camera did not reach the Attached state.'
    for ($attempt = 1; $attempt -le $script:AttachRetryLimit; $attempt++) {
        $device = Get-OrionUsbDevice
        if ($null -ne $device -and $device.State -eq 'Attached') { return $true }

        if (-not (Start-OrionBridgeKeepAlive)) {
            $lastMessage = 'Ubuntu camera environment could not stay running.'
        }
        else {
            $attachOutput = & $script:Usbipd attach --wsl --busid $BusId 2>&1
            $attachExitCode = $LASTEXITCODE
            $lastMessage = [string]::Join("`n", @($attachOutput))
            if ([string]::IsNullOrWhiteSpace($lastMessage)) {
                $lastMessage = "USB attach attempt $attempt failed with code $attachExitCode."
            }

            for ($readyAttempt = 0; $readyAttempt -lt 16; $readyAttempt++) {
                $device = Get-OrionUsbDevice
                if ($null -ne $device -and $device.State -eq 'Attached') { return $true }
                Start-Sleep -Milliseconds 250
            }
        }

        if ($attempt -lt $script:AttachRetryLimit) {
            Set-Status "Camera attach was not ready - retrying ($($attempt + 1) of $($script:AttachRetryLimit))..." 'busy'
            Start-Sleep -Milliseconds 800
        }
    }

    throw "The Orion camera could not attach after $($script:AttachRetryLimit) attempts. $lastMessage"
}

function Test-ProcessRunning {
    param($Process)
    if ($null -eq $Process) { return $false }
    try { return -not $Process.HasExited }
    catch { return $false }
}

function Test-ProcessStayedAlive {
    param(
        [Parameter(Mandatory = $true)]$Process,
        [int]$MinimumMilliseconds = 1200
    )
    $deadline = [DateTime]::UtcNow.AddMilliseconds($MinimumMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            if ($Process.HasExited) { return $false }
        }
        catch { return $false }
        Start-Sleep -Milliseconds 100
    }
    return (Test-ProcessRunning $Process)
}

function Start-OrionBridgeKeepAlive {
    if (Test-ProcessRunning $script:BridgeKeepAliveProcess) { return $true }

    if ($null -ne $script:BridgeKeepAliveProcess) {
        try { $script:BridgeKeepAliveProcess.Dispose() } catch { }
        $script:BridgeKeepAliveProcess = $null
    }

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'wsl.exe'
        $startInfo.Arguments = "-d $($script:DistroArgument) -u root -- sleep 2147483647"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $script:BridgeKeepAliveProcess = [System.Diagnostics.Process]::Start($startInfo)
        if (-not (Test-ProcessStayedAlive -Process $script:BridgeKeepAliveProcess -MinimumMilliseconds 1200)) {
            throw 'The camera bridge keep-alive stopped during startup.'
        }
        return $true
    }
    catch {
        if ($null -ne $script:BridgeKeepAliveProcess) {
            try { $script:BridgeKeepAliveProcess.Dispose() } catch { }
        }
        $script:BridgeKeepAliveProcess = $null
        return $false
    }
}

function Stop-OrionBridgeKeepAlive {
    if ($null -eq $script:BridgeKeepAliveProcess) { return }
    try {
        if (-not $script:BridgeKeepAliveProcess.HasExited) {
            $script:BridgeKeepAliveProcess.Kill()
            $script:BridgeKeepAliveProcess.WaitForExit(3000) | Out-Null
        }
    }
    catch { }
    try { $script:BridgeKeepAliveProcess.Dispose() } catch { }
    $script:BridgeKeepAliveProcess = $null
}

function Start-OrionPreviewAttempt {
    param([ValidateSet('on', 'off')][string]$Crosshair)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'wsl.exe'
    $startInfo.Arguments = "-d $($script:DistroArgument) -u root -- bash `"$($script:CameraScriptWsl)`" preview $Crosshair"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)

    if (-not (Test-ProcessStayedAlive -Process $process -MinimumMilliseconds 1400)) {
        $exitCode = 'unknown'
        try { $exitCode = $process.ExitCode } catch { }
        try { $process.Dispose() } catch { }
        throw "The preview process stopped during startup (code $exitCode)."
    }
    return $process
}

function Get-SafeTargetName {
    $name = $targetCombo.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Target' }
    $name = [System.Text.RegularExpressions.Regex]::Replace($name, '[^A-Za-z0-9_-]+', '_')
    return $name.Trim('_')
}

function Refresh-ExposureState {
    try {
        $lines = Invoke-OrionCommand -CameraArguments @('controls')
        $autoValue = $null
        $exposureValue = $null
        foreach ($lineObject in $lines) {
            $line = [string]$lineObject
            if ($line -match '^AUTO=(\d+)$') { $autoValue = [int]$Matches[1] }
            if ($line -match '^EXPOSURE=(\d+)$') { $exposureValue = [int]$Matches[1] }
        }
        $script:UpdatingExposureUi = $true
        if ($null -ne $exposureValue) {
            $exposureSlider.Value = [Math]::Max(0, [Math]::Min(255, $exposureValue))
            $exposureValueLabel.Text = [string]$exposureSlider.Value
        }
        if ($null -ne $autoValue) { $autoCheck.Checked = ($autoValue -eq 1) }
        $exposureSlider.Enabled = -not $autoCheck.Checked
        $script:UpdatingExposureUi = $false
    }
    catch {
        $script:UpdatingExposureUi = $false
    }
}

function Connect-OrionCamera {
    try {
        Set-Status 'Starting the camera bridge...' 'busy'
        if (-not (Start-OrionBridgeKeepAlive)) {
            throw 'Ubuntu camera environment could not stay running.'
        }

        $device = Get-OrionUsbDevice
        if ($null -eq $device) {
            throw 'Camera not found. Plug in the Orion camera, then press Connect.'
        }

        if ($device.State -eq 'Not shared') {
            Set-Status 'Windows approval is required once for this USB port...' 'busy'
            $admin = Start-Process -FilePath $script:Usbipd -ArgumentList @('bind', '--busid', $device.BusId) -Verb RunAs -Wait -PassThru
            if ($admin.ExitCode -ne 0) { throw 'Windows did not approve sharing the Orion camera.' }
            $device = Get-OrionUsbDevice
        }

        if ($device.State -ne 'Attached') {
            Set-Status 'Attaching the Orion camera...' 'busy'
            $null = Attach-OrionCameraWithRetry -BusId $device.BusId
        }

        Set-Status 'Waiting for the imaging sensor...' 'busy'
        if (Wait-OrionSensorReady) {
            $script:CameraConnected = $true
            Refresh-ExposureState
            Set-Status 'Camera connected - 1280x1024 sensor ready - 15 fps preview mode' 'good'
            Update-UiState
            return $true
        }
        throw 'The USB camera attached, but its imaging sensor did not become ready.'
    }
    catch {
        $script:CameraConnected = $false
        Show-Failure $_.Exception.Message
        Update-UiState
        return $false
    }
}

function Reset-OrionAttachment {
    try {
        $device = Get-OrionUsbDevice
        if ($null -eq $device) { return $false }
        if ($device.State -eq 'Attached') {
            & $script:Usbipd detach --busid $device.BusId 2>$null | Out-Null
            Start-Sleep -Milliseconds 700
        }
        if (-not (Start-OrionBridgeKeepAlive)) { return $false }
        $null = Attach-OrionCameraWithRetry -BusId $device.BusId
        if (Wait-OrionSensorReady) { return $true }
    }
    catch { }
    return $false
}

function Complete-PreviewCleanup {
    if ($null -ne $script:PreviewProcess) {
        try { $script:PreviewProcess.Dispose() } catch { }
        $script:PreviewProcess = $null
    }
    $previewButton.Text = 'Live Preview'
    $previewButton.BackColor = $surfaceRaised
    Set-Status 'Preview closed - releasing camera...' 'busy'
    try {
        $null = Invoke-OrionCommand -CameraArguments @('recover')
        $script:CameraConnected = $true
        Set-Status 'Preview closed - camera ready for the next job' 'good'
    }
    catch {
        Set-Status 'Preview closed - automatically resetting camera...' 'busy'
        if (Reset-OrionAttachment) {
            $script:CameraConnected = $true
            Set-Status 'Camera recovered automatically - ready' 'good'
        }
        else {
            $script:CameraConnected = $false
            Set-Status 'Automatic recovery failed - press Connect / Recover' 'error'
        }
    }
    Update-UiState
}

function Apply-ManualExposure {
    param([int]$Value, [string]$Label = 'Manual')
    if (-not $script:CameraConnected -and -not (Connect-OrionCamera)) { return }
    try {
        Set-Status "Applying $Label exposure ($Value)..." 'busy'
        $null = Invoke-OrionCommand -CameraArguments @('exposure', [string]$Value)
        $script:UpdatingExposureUi = $true
        $autoCheck.Checked = $false
        $exposureSlider.Enabled = $true
        $exposureSlider.Value = $Value
        $exposureValueLabel.Text = [string]$Value
        $script:UpdatingExposureUi = $false
        Set-Status "$Label starting exposure applied - adjust slider while watching preview" 'good'
    }
    catch { Show-Failure $_.Exception.Message }
}

function Apply-Preset {
    param([string]$Target, [int]$Exposure)
    $targetCombo.Text = $Target
    Apply-ManualExposure -Value $Exposure -Label $Target
}

function Update-RecordingEstimate {
    $seconds = [int]$durationBox.Value
    $estimatedMb = [Math]::Ceiling($seconds * 13.2)
    $sizeEstimateLabel.Text = "Estimated file: ~$estimatedMb MB  -  uncompressed colour AVI"
}

function Update-UiState {
    $previewRunning = Test-ProcessRunning $script:PreviewProcess
    $recordingRunning = Test-ProcessRunning $script:RecordingProcess
    $connectButton.Enabled = -not $previewRunning -and -not $recordingRunning
    $previewButton.Enabled = -not $recordingRunning
    $snapshotButton.Enabled = -not $previewRunning -and -not $recordingRunning
    $recordButton.Enabled = -not $previewRunning
    $durationBox.Enabled = -not $recordingRunning
    $targetCombo.Enabled = -not $recordingRunning
    $venusButton.Enabled = -not $recordingRunning
    $jupiterButton.Enabled = -not $recordingRunning
    $saturnButton.Enabled = -not $recordingRunning
    $moonButton.Enabled = -not $recordingRunning
    $autoCheck.Enabled = -not $recordingRunning
    $exposureSlider.Enabled = -not $recordingRunning -and -not $autoCheck.Checked
    $crosshairCheck.Enabled = -not $previewRunning -and -not $recordingRunning
}

function New-DeckButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, $Parent)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(74, 91, 113)
    $button.BackColor = $surfaceRaised
    $button.ForeColor = $textPrimary
    $Parent.Controls.Add($button)
    return $button
}

$exposurePanel = New-Object System.Windows.Forms.Panel
$exposurePanel.Location = New-Object System.Drawing.Point(28, 180)
$exposurePanel.Size = New-Object System.Drawing.Size(360, 294)
$exposurePanel.BackColor = $surface
$form.Controls.Add($exposurePanel)

$exposureHeader = New-Object System.Windows.Forms.Label
$exposureHeader.Text = 'TARGET & EXPOSURE'
$exposureHeader.Location = New-Object System.Drawing.Point(16, 13)
$exposureHeader.Size = New-Object System.Drawing.Size(320, 24)
$exposureHeader.Font = New-Object System.Drawing.Font($fontName, 11, [System.Drawing.FontStyle]::Bold)
$exposureHeader.ForeColor = $accent
$exposurePanel.Controls.Add($exposureHeader)

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = 'Target / filename:'
$targetLabel.Location = New-Object System.Drawing.Point(16, 48)
$targetLabel.Size = New-Object System.Drawing.Size(125, 24)
$exposurePanel.Controls.Add($targetLabel)

$targetCombo = New-Object System.Windows.Forms.ComboBox
$targetCombo.Location = New-Object System.Drawing.Point(145, 45)
$targetCombo.Size = New-Object System.Drawing.Size(195, 28)
$targetCombo.DropDownStyle = 'DropDown'
$null = $targetCombo.Items.AddRange(@('Venus', 'Jupiter', 'Saturn', 'Moon', 'Solar_System'))
$targetCombo.Text = 'Jupiter'
$exposurePanel.Controls.Add($targetCombo)

$presetLabel = New-Object System.Windows.Forms.Label
$presetLabel.Text = 'Starting presets:'
$presetLabel.Location = New-Object System.Drawing.Point(16, 82)
$presetLabel.Size = New-Object System.Drawing.Size(150, 22)
$presetLabel.ForeColor = $textSecondary
$exposurePanel.Controls.Add($presetLabel)

$venusButton = New-DeckButton -Text 'Venus' -X 16 -Y 106 -Width 76 -Height 34 -Parent $exposurePanel
$jupiterButton = New-DeckButton -Text 'Jupiter' -X 99 -Y 106 -Width 76 -Height 34 -Parent $exposurePanel
$saturnButton = New-DeckButton -Text 'Saturn' -X 182 -Y 106 -Width 76 -Height 34 -Parent $exposurePanel
$moonButton = New-DeckButton -Text 'Moon' -X 265 -Y 106 -Width 76 -Height 34 -Parent $exposurePanel

$autoCheck = New-Object System.Windows.Forms.CheckBox
$autoCheck.Text = 'Automatic exposure / gain'
$autoCheck.Location = New-Object System.Drawing.Point(16, 150)
$autoCheck.Size = New-Object System.Drawing.Size(230, 25)
$autoCheck.Checked = $true
$exposurePanel.Controls.Add($autoCheck)

$sliderLabel = New-Object System.Windows.Forms.Label
$sliderLabel.Text = 'Manual exposure'
$sliderLabel.Location = New-Object System.Drawing.Point(16, 181)
$sliderLabel.Size = New-Object System.Drawing.Size(125, 22)
$exposurePanel.Controls.Add($sliderLabel)

$exposureSlider = New-Object System.Windows.Forms.TrackBar
$exposureSlider.Location = New-Object System.Drawing.Point(16, 202)
$exposureSlider.Size = New-Object System.Drawing.Size(278, 45)
$exposureSlider.Minimum = 0
$exposureSlider.Maximum = 255
$exposureSlider.TickFrequency = 25
$exposureSlider.Value = 127
$exposureSlider.Enabled = $false
$exposurePanel.Controls.Add($exposureSlider)

$exposureValueLabel = New-Object System.Windows.Forms.Label
$exposureValueLabel.Text = '127'
$exposureValueLabel.Location = New-Object System.Drawing.Point(300, 205)
$exposureValueLabel.Size = New-Object System.Drawing.Size(45, 25)
$exposureValueLabel.TextAlign = 'MiddleCenter'
$exposureValueLabel.Font = New-Object System.Drawing.Font($fontName, 11, [System.Drawing.FontStyle]::Bold)
$exposureValueLabel.ForeColor = $warning
$exposurePanel.Controls.Add($exposureValueLabel)

$presetHint = New-Object System.Windows.Forms.Label
$presetHint.Text = 'Presets are safe starting points - fine-tune against the live planet.'
$presetHint.Location = New-Object System.Drawing.Point(16, 244)
$presetHint.Size = New-Object System.Drawing.Size(330, 40)
$presetHint.Font = New-Object System.Drawing.Font($fontName, 8.5)
$presetHint.ForeColor = $textSecondary
$exposurePanel.Controls.Add($presetHint)

$capturePanel = New-Object System.Windows.Forms.Panel
$capturePanel.Location = New-Object System.Drawing.Point(405, 180)
$capturePanel.Size = New-Object System.Drawing.Size(357, 294)
$capturePanel.BackColor = $surface
$form.Controls.Add($capturePanel)

$captureHeader = New-Object System.Windows.Forms.Label
$captureHeader.Text = 'CAMERA & CAPTURE'
$captureHeader.Location = New-Object System.Drawing.Point(16, 13)
$captureHeader.Size = New-Object System.Drawing.Size(320, 24)
$captureHeader.Font = New-Object System.Drawing.Font($fontName, 11, [System.Drawing.FontStyle]::Bold)
$captureHeader.ForeColor = $accent
$capturePanel.Controls.Add($captureHeader)

$connectButton = New-DeckButton -Text 'Connect / Recover Camera' -X 16 -Y 45 -Width 325 -Height 40 -Parent $capturePanel
$previewButton = New-DeckButton -Text 'Live Preview' -X 16 -Y 94 -Width 325 -Height 40 -Parent $capturePanel
$snapshotButton = New-DeckButton -Text 'Full-Resolution Snapshot' -X 16 -Y 143 -Width 325 -Height 40 -Parent $capturePanel
$openButton = New-DeckButton -Text 'Open Captures Folder' -X 16 -Y 192 -Width 325 -Height 40 -Parent $capturePanel

$crosshairCheck = New-Object System.Windows.Forms.CheckBox
$crosshairCheck.Text = 'Centre crosshair in live preview'
$crosshairCheck.Location = New-Object System.Drawing.Point(18, 239)
$crosshairCheck.Size = New-Object System.Drawing.Size(300, 24)
$crosshairCheck.Checked = $true
$capturePanel.Controls.Add($crosshairCheck)

$recordPanel = New-Object System.Windows.Forms.Panel
$recordPanel.Location = New-Object System.Drawing.Point(28, 490)
$recordPanel.Size = New-Object System.Drawing.Size(734, 178)
$recordPanel.BackColor = $surface
$form.Controls.Add($recordPanel)

$recordHeader = New-Object System.Windows.Forms.Label
$recordHeader.Text = 'PLANETARY RECORDING'
$recordHeader.Location = New-Object System.Drawing.Point(16, 13)
$recordHeader.Size = New-Object System.Drawing.Size(300, 24)
$recordHeader.Font = New-Object System.Drawing.Font($fontName, 11, [System.Drawing.FontStyle]::Bold)
$recordHeader.ForeColor = $accent
$recordPanel.Controls.Add($recordHeader)

$durationLabel = New-Object System.Windows.Forms.Label
$durationLabel.Text = 'Length:'
$durationLabel.Location = New-Object System.Drawing.Point(16, 46)
$durationLabel.Size = New-Object System.Drawing.Size(62, 24)
$recordPanel.Controls.Add($durationLabel)

$durationBox = New-Object System.Windows.Forms.NumericUpDown
$durationBox.Location = New-Object System.Drawing.Point(78, 43)
$durationBox.Size = New-Object System.Drawing.Size(72, 26)
$durationBox.Minimum = 1
$durationBox.Maximum = 300
$durationBox.Value = 30
$durationBox.TextAlign = 'Center'
$recordPanel.Controls.Add($durationBox)

$secondsLabel = New-Object System.Windows.Forms.Label
$secondsLabel.Text = 'seconds'
$secondsLabel.Location = New-Object System.Drawing.Point(157, 46)
$secondsLabel.Size = New-Object System.Drawing.Size(68, 24)
$recordPanel.Controls.Add($secondsLabel)

$sizeEstimateLabel = New-Object System.Windows.Forms.Label
$sizeEstimateLabel.Location = New-Object System.Drawing.Point(235, 46)
$sizeEstimateLabel.Size = New-Object System.Drawing.Size(300, 42)
$sizeEstimateLabel.ForeColor = $textSecondary
$recordPanel.Controls.Add($sizeEstimateLabel)

$recordButton = New-DeckButton -Text 'Record Colour AVI' -X 548 -Y 38 -Width 168 -Height 42 -Parent $recordPanel
$recordButton.BackColor = $danger

$recordProgress = New-Object System.Windows.Forms.ProgressBar
$recordProgress.Location = New-Object System.Drawing.Point(16, 98)
$recordProgress.Size = New-Object System.Drawing.Size(520, 22)
$recordProgress.Minimum = 0
$recordProgress.Maximum = 100
$recordPanel.Controls.Add($recordProgress)

$countdownLabel = New-Object System.Windows.Forms.Label
$countdownLabel.Text = 'Ready'
$countdownLabel.Location = New-Object System.Drawing.Point(548, 98)
$countdownLabel.Size = New-Object System.Drawing.Size(168, 28)
$countdownLabel.TextAlign = 'MiddleCenter'
$countdownLabel.Font = New-Object System.Drawing.Font($fontName, 10, [System.Drawing.FontStyle]::Bold)
$recordPanel.Controls.Add($countdownLabel)

$recordHint = New-Object System.Windows.Forms.Label
$recordHint.Text = '640x480 at ~15 fps - uncompressed AVI for planetary stacking - press Stop to finish early'
$recordHint.Location = New-Object System.Drawing.Point(16, 136)
$recordHint.Size = New-Object System.Drawing.Size(700, 30)
$recordHint.Font = New-Object System.Drawing.Font($fontName, 8.5)
$recordHint.ForeColor = $textSecondary
$recordPanel.Controls.Add($recordHint)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = 'Workflow: choose target -> preview -> tune exposure -> close preview -> record or snapshot'
$footer.Location = New-Object System.Drawing.Point(30, 682)
$footer.Size = New-Object System.Drawing.Size(730, 44)
$footer.ForeColor = $textSecondary
$form.Controls.Add($footer)

# Preserve the familiar two-column workflow, with room for wrapped labels.
# A minimum size prevents shrinking controls over each other; extra width goes
# to the capture controls, status text, recording estimate and progress bar.
$form.MinimumSize = $form.Size
foreach ($control in @($title, $subtitle, $statusPanel, $statusLabel, $capturePanel,
    $captureHeader, $connectButton, $previewButton, $snapshotButton, $openButton,
    $crosshairCheck, $recordPanel, $sizeEstimateLabel, $recordProgress, $recordHint, $footer)) {
    $control.Anchor = 'Top, Left, Right'
}
foreach ($control in @($recordButton, $countdownLabel)) { $control.Anchor = 'Top, Right' }
foreach ($label in @($title, $subtitle, $statusLabel, $exposureHeader, $captureHeader,
    $recordHeader, $presetHint, $sizeEstimateLabel, $recordHint, $footer)) {
    $label.UseMnemonic = $false
}

function Test-DeckLayout {
    $originalSize = $form.ClientSize
    $originalStatus = $statusLabel.Text
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
    try {
        $statusLabel.Text = 'Recording saved - 9999.9 MB - Solar_System_2026-09-22_12-34-56-789_640x480_colour.avi'
        foreach ($size in @([System.Drawing.Size]::new(790, 748), [System.Drawing.Size]::new(1100, 900), [System.Drawing.Size]::new(790, 748))) {
            $form.ClientSize = $size
            $form.PerformLayout()
            foreach ($label in @($title, $subtitle, $statusLabel, $exposureHeader, $captureHeader,
                $recordHeader, $presetHint, $sizeEstimateLabel, $recordHint, $footer)) {
                $required = [System.Windows.Forms.TextRenderer]::MeasureText($label.Text, $label.Font,
                    [System.Drawing.Size]::new($label.ClientSize.Width, 10000), $flags)
                if ($required.Height -gt $label.ClientSize.Height -or $required.Width -gt $label.ClientSize.Width) {
                    throw "Clipped panel label: $($label.Text)"
                }
                if (-not $label.Parent.ClientRectangle.Contains($label.Bounds)) {
                    throw "Panel label extends outside its container: $($label.Text)"
                }
            }
            foreach ($control in @($connectButton, $previewButton, $snapshotButton, $openButton,
                $recordButton, $durationBox, $recordProgress, $countdownLabel, $crosshairCheck)) {
                if (-not $control.Parent.ClientRectangle.Contains($control.Bounds)) {
                    throw "Panel control extends outside its container: $($control.Text)"
                }
            }
            if ($sizeEstimateLabel.Bottom -gt $recordProgress.Top -or $presetHint.Bottom -gt $exposurePanel.ClientSize.Height) {
                throw 'Wrapped panel text overlaps another control.'
            }
        }
    }
    finally {
        $form.ClientSize = $originalSize
        $statusLabel.Text = $originalStatus
    }
}

$connectButton.Add_Click({ Connect-OrionCamera | Out-Null })

$previewButton.Add_Click({
    if (Test-ProcessRunning $script:PreviewProcess) {
        Set-Status 'Stopping live preview...' 'busy'
        $null = Invoke-OrionCommand -CameraArguments @('stop-preview') -IgnoreError
        return
    }
    if (-not (Connect-OrionCamera)) { return }
    try {
        $crosshair = if ($crosshairCheck.Checked) { 'on' } else { 'off' }
        $lastPreviewError = $null
        for ($attempt = 1; $attempt -le $script:PreviewRetryLimit; $attempt++) {
            try {
                Set-Status "Opening live preview (attempt $attempt of $($script:PreviewRetryLimit))..." 'busy'
                $script:PreviewProcess = Start-OrionPreviewAttempt -Crosshair $crosshair
                $lastPreviewError = $null
                break
            }
            catch {
                $lastPreviewError = $_.Exception.Message
                $script:PreviewProcess = $null
                if ($attempt -lt $script:PreviewRetryLimit) {
                    Set-Status 'Preview did not appear - resetting the camera and retrying once...' 'busy'
                    $null = Invoke-OrionCommand -CameraArguments @('stop-preview') -IgnoreError
                    if (-not (Reset-OrionAttachment)) {
                        throw "Preview startup failed and the automatic camera reset did not complete. $lastPreviewError"
                    }
                }
            }
        }
        if ($null -ne $lastPreviewError -or -not (Test-ProcessRunning $script:PreviewProcess)) {
            throw "Live preview could not start after two attempts. $lastPreviewError"
        }
        $previewButton.Text = 'Stop Live Preview'
        $previewButton.BackColor = $danger
        Set-Status 'Live preview started - presets and exposure slider remain active' 'good'
        Update-UiState
    }
    catch {
        $script:PreviewProcess = $null
        $previewButton.Text = 'Live Preview'
        $previewButton.BackColor = $surfaceRaised
        Update-UiState
        Show-Failure $_.Exception.Message
    }
})

$snapshotButton.Add_Click({
    if (-not (Connect-OrionCamera)) { return }
    try {
        Set-Status 'Capturing a full-resolution image...' 'busy'
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
        $target = Get-SafeTargetName
        $output = Join-Path $script:CaptureDir "$target`_$stamp`_1280x1024.png"
        $wslOutput = Convert-ToWslPath $output
        $result = Invoke-OrionCommand -CameraArguments @('snapshot', $wslOutput)
        if (-not (Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -eq 0) { throw 'The snapshot did not produce an image file.' }
        Set-Status "Snapshot saved - $([System.IO.Path]::GetFileName($output))" 'good'
        Start-Process -FilePath $output | Out-Null
    }
    catch { Show-Failure $_.Exception.Message }
})

$openButton.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList @($script:CaptureDir) | Out-Null })

$venusButton.Add_Click({ Apply-Preset -Target 'Venus' -Exposure 20 })
$jupiterButton.Add_Click({ Apply-Preset -Target 'Jupiter' -Exposure 50 })
$saturnButton.Add_Click({ Apply-Preset -Target 'Saturn' -Exposure 105 })
$moonButton.Add_Click({ Apply-Preset -Target 'Moon' -Exposure 30 })

$autoCheck.Add_CheckedChanged({
    if ($script:UpdatingExposureUi) { return }
    try {
        if ($autoCheck.Checked) {
            if (-not $script:CameraConnected -and -not (Connect-OrionCamera)) { return }
            Set-Status 'Enabling automatic exposure / gain...' 'busy'
            $null = Invoke-OrionCommand -CameraArguments @('auto')
            $exposureSlider.Enabled = $false
            Set-Status 'Automatic exposure / gain enabled' 'good'
        }
        else {
            Apply-ManualExposure -Value $exposureSlider.Value -Label 'Manual'
        }
        Update-UiState
    }
    catch { Show-Failure $_.Exception.Message }
})

$exposureSlider.Add_ValueChanged({ $exposureValueLabel.Text = [string]$exposureSlider.Value })
$exposureSlider.Add_MouseUp({ Apply-ManualExposure -Value $exposureSlider.Value -Label 'Manual' })
$exposureSlider.Add_KeyUp({
    if ($_.KeyCode -in @('Left', 'Right', 'Up', 'Down', 'PageUp', 'PageDown', 'Home', 'End')) {
        Apply-ManualExposure -Value $exposureSlider.Value -Label 'Manual'
    }
})

$durationBox.Add_ValueChanged({ Update-RecordingEstimate })

$recordButton.Add_Click({
    if (Test-ProcessRunning $script:RecordingProcess) {
        Set-Status 'Stopping the recording safely...' 'busy'
        $null = Invoke-OrionCommand -CameraArguments @('stop') -IgnoreError
        return
    }
    if (-not (Connect-OrionCamera)) { return }
    try {
        $seconds = [int]$durationBox.Value
        $estimatedBytes = [int64]($seconds * 13.2 * 1MB)
        $drive = New-Object System.IO.DriveInfo -ArgumentList ([System.IO.Path]::GetPathRoot($script:CaptureDir))
        if ($drive.AvailableFreeSpace -lt ($estimatedBytes + 500MB)) {
            throw "Not enough free disk space for this recording. Shorten the duration or free some space."
        }

        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
        $target = Get-SafeTargetName
        $script:RecordingOutput = Join-Path $script:CaptureDir "$target`_$stamp`_640x480_colour.avi"
        $wslOutput = Convert-ToWslPath $script:RecordingOutput
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'wsl.exe'
        $startInfo.Arguments = "-d $($script:DistroArgument) -u root -- bash `"$($script:CameraScriptWsl)`" record `"$wslOutput`" $seconds"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $script:RecordingProcess = [System.Diagnostics.Process]::Start($startInfo)
        $script:RecordingSeconds = $seconds
        $script:RecordingStartedAt = Get-Date
        $script:RecordingEndsAt = $script:RecordingStartedAt.AddSeconds($seconds)
        $recordProgress.Value = 0
        $recordButton.Text = 'Stop Recording'
        $countdownLabel.Text = "$seconds s remaining"
        Set-Status "Recording $target - $seconds seconds..." 'busy'
        Update-UiState
    }
    catch { Show-Failure $_.Exception.Message }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if ($null -ne $script:PreviewProcess -and $script:PreviewProcess.HasExited) {
        Complete-PreviewCleanup
    }

    if (Test-ProcessRunning $script:RecordingProcess) {
        $elapsed = ((Get-Date) - $script:RecordingStartedAt).TotalSeconds
        $progress = [Math]::Max(0, [Math]::Min(100, [int](100 * $elapsed / $script:RecordingSeconds)))
        $recordProgress.Value = $progress
        $remaining = [Math]::Max(0, [Math]::Ceiling(($script:RecordingEndsAt - (Get-Date)).TotalSeconds))
        $countdownLabel.Text = "$remaining s remaining"
    }
    elseif ($null -ne $script:RecordingProcess) {
        $exitCode = $script:RecordingProcess.ExitCode
        $script:RecordingProcess.Dispose()
        $script:RecordingProcess = $null
        $recordButton.Text = 'Record Colour AVI'
        $recordProgress.Value = 100
        $countdownLabel.Text = 'Saved'
        Update-UiState
        if ($exitCode -eq 0 -and (Test-Path -LiteralPath $script:RecordingOutput) -and (Get-Item -LiteralPath $script:RecordingOutput).Length -gt 0) {
            $sizeMb = [Math]::Round((Get-Item -LiteralPath $script:RecordingOutput).Length / 1MB, 1)
            Set-Status "Recording saved - $sizeMb MB - $([System.IO.Path]::GetFileName($script:RecordingOutput))" 'good'
        }
        else {
            $countdownLabel.Text = 'Failed'
            Set-Status "Recording failed (code $exitCode) - close preview and try again" 'error'
        }
    }
})
$timer.Start()

$form.Add_FormClosing({
    if (Test-ProcessRunning $script:RecordingProcess) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'A recording is running. Stop it and close?',
            'Orion StarShoot Planetary Deck',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
            return
        }
        $null = Invoke-OrionCommand -CameraArguments @('stop') -IgnoreError
        $script:RecordingProcess.WaitForExit(5000) | Out-Null
    }
    if (Test-ProcessRunning $script:PreviewProcess) {
        $null = Invoke-OrionCommand -CameraArguments @('stop-preview') -IgnoreError
        $script:PreviewProcess.WaitForExit(5000) | Out-Null
    }
    Stop-OrionBridgeKeepAlive
})

Update-RecordingEstimate
Update-UiState
if ($SelfTest) {
    Test-DeckLayout
    $requiredLabels = @(
        $title.Text,
        $connectButton.Text,
        $previewButton.Text,
        $snapshotButton.Text,
        $recordButton.Text,
        $venusButton.Text,
        $jupiterButton.Text,
        $saturnButton.Text,
        $moonButton.Text
    )
    if ($requiredLabels -contains $null -or $requiredLabels -contains '') {
        throw 'One or more required Planetary Deck controls were not created.'
    }
    $quickProcess = Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-Command', 'exit 0') -WindowStyle Hidden -PassThru
    try {
        # Process startup can exceed the guard interval on a busy CI runner.
        # Establish an exited process before testing the rejection path.
        if (-not $quickProcess.WaitForExit(10000)) {
            throw 'The self-test exit process did not finish within 10 seconds.'
        }
        $quickRejected = -not (Test-ProcessStayedAlive -Process $quickProcess -MinimumMilliseconds 300)
    }
    finally {
        if (-not $quickProcess.HasExited) { $quickProcess.Kill(); $quickProcess.WaitForExit(3000) | Out-Null }
        $quickProcess.Dispose()
    }

    $steadyProcess = Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') -WindowStyle Hidden -PassThru
    try {
        $steadyAccepted = Test-ProcessStayedAlive -Process $steadyProcess -MinimumMilliseconds 300
    }
    finally {
        if (-not $steadyProcess.HasExited) { $steadyProcess.Kill(); $steadyProcess.WaitForExit(3000) | Out-Null }
        $steadyProcess.Dispose()
    }

    if (-not $quickRejected -or -not $steadyAccepted) {
        throw 'Preview startup guard did not distinguish a failed process from a running process.'
    }
    if ($null -eq (Get-Command Start-OrionBridgeKeepAlive -ErrorAction SilentlyContinue)) {
        throw 'Camera bridge keep-alive function was not created.'
    }
    "SELF_TEST_OK CONTROLS=$($requiredLabels.Count) ESTIMATE=$($sizeEstimateLabel.Text) PREVIEW_STARTUP_GUARD=OK PREVIEW_RETRY_LIMIT=$($script:PreviewRetryLimit) BRIDGE_KEEPALIVE=READY ATTACH_RETRY_LIMIT=$($script:AttachRetryLimit) SENSOR_READY_TIMEOUT=$($script:SensorReadyTimeoutSeconds) LAYOUT=OK"
    $timer.Stop()
    $form.Dispose()
    return
}
$form.Add_Shown({ Connect-OrionCamera | Out-Null })
[void]$form.ShowDialog()

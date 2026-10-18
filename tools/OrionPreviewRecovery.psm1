function Invoke-OrionWsl {
    param([string[]]$Arguments)
    $output = @(& wsl.exe @Arguments 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Get-OrionPreviewDisplayState {
    param([string]$Distro, [string]$CameraScript)
    $result = Invoke-OrionWsl -Arguments @('-d', $Distro, '-u', 'root', '--', 'bash', $CameraScript, 'display-state')
    if ($result.ExitCode -ne 0) { throw 'Could not check the Linux preview display.' }
    $state = ([string]::Join("`n", @($result.Output))).Trim()
    if ($state -notin @('0', '1', 'unavailable')) { throw 'Unexpected preview display status.' }
    return $state
}

function Repair-OrionPreviewDisplay {
    param([string]$Distro, [string]$CameraScript)
    $state = Get-OrionPreviewDisplayState -Distro $Distro -CameraScript $CameraScript
    if ($state -ne '0') { return $false }

    # This restarts WSLg's compositor, not WSL, USB or any camera driver.
    # Other Linux GUI windows can close; see docs/WINDOWS_SETUP.md.
    $result = Invoke-OrionWsl -Arguments @('-d', $Distro, '--system', '--exec', 'pkill', '-TERM', '-x', 'weston')
    if ($result.ExitCode -ne 0) { throw 'The Linux preview display could not be restarted.' }
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 250
        if ((Get-OrionPreviewDisplayState -Distro $Distro -CameraScript $CameraScript) -eq '1') {
            return $true
        }
    }
    throw 'The Linux display restarted but its rendering check is still failing. See the restart log.'
}

Export-ModuleMember -Function Get-OrionPreviewDisplayState, Repair-OrionPreviewDisplay

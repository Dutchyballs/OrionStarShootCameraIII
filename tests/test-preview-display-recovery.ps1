param([string]$PanelPath)
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\OrionPreviewRecovery.psm1'
$module = Import-Module $modulePath -Force -PassThru

# Substitute only the native WSL boundary: no GUI, USB or real process is touched.
& $module {
    function script:Invoke-OrionWsl {
        param([string[]]$Arguments)
        if ($Arguments -contains 'display-state') {
            $value = if ($script:States.Count -gt 1) { $script:States.Dequeue() } else { $script:States.Peek() }
            return [pscustomobject]@{ ExitCode = 0; Output = @($value) }
        }
        $expected = @('-d', 'Ubuntu-24.04', '--system', '--exec', 'pkill', '-TERM', '-x', 'weston')
        if (($Arguments -join '|') -ne ($expected -join '|')) { throw 'Recovery attempted an unexpected system command.' }
        $script:Restarts++
        return [pscustomobject]@{ ExitCode = $script:RestartExitCode; Output = @() }
    }
}

function Set-TestState {
    param([string[]]$States, [int]$RestartExitCode = 0)
    & $module {
        param($values, $exitCode)
        $script:States = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($value in $values) { $script:States.Enqueue($value) }
        $script:Restarts = 0
        $script:RestartExitCode = $exitCode
    } $States $RestartExitCode
}

Set-TestState @('1')
if (Repair-OrionPreviewDisplay -Distro Ubuntu-24.04 -CameraScript '/test/camera.sh') { throw 'Healthy display was repaired unnecessarily.' }
if ((& $module { $script:Restarts }) -ne 0) { throw 'Healthy display was restarted.' }

Set-TestState @('0', '0', '1')
if (-not (Repair-OrionPreviewDisplay -Distro Ubuntu-24.04 -CameraScript '/test/camera.sh')) { throw 'Broken display did not recover.' }
if ((& $module { $script:Restarts }) -ne 1) { throw 'Recovery must restart only once.' }

Set-TestState @('0') -RestartExitCode 1
$rejected = $false
try { $null = Repair-OrionPreviewDisplay -Distro Ubuntu-24.04 -CameraScript '/test/camera.sh' } catch { $rejected = $true }
if (-not $rejected) { throw 'Failed compositor restart was reported as successful.' }

Set-TestState @('0')
$rejected = $false
try { $null = Repair-OrionPreviewDisplay -Distro Ubuntu-24.04 -CameraScript '/test/camera.sh' } catch { $rejected = $true }
if (-not $rejected -or (& $module { $script:Restarts }) -ne 1) { throw 'Unhealthy display did not fail after its bounded retry.' }

Set-TestState @('unavailable')
if (Repair-OrionPreviewDisplay -Distro Ubuntu-24.04 -CameraScript '/test/camera.sh') { throw 'Unavailable WSLg state should not trigger a restart.' }
if ((& $module { $script:Restarts }) -ne 0) { throw 'Non-WSLg display was restarted.' }
Write-Output 'PREVIEW_DISPLAY_RECOVERY_TEST_OK CASES=5'

param(
    [string]$Distro = $(if ($env:ORION_WSL_DISTRO) { $env:ORION_WSL_DISTRO } else { 'Ubuntu-24.04' })
)

$ErrorActionPreference = 'Stop'
$cameraScriptWindows = Join-Path (Split-Path -Parent $PSScriptRoot) 'orion-camera.sh'
if ($cameraScriptWindows -notmatch '^([A-Za-z]):\\(.*)$') {
    throw 'Run this diagnostic from a local Windows drive.'
}
$cameraScript = '/mnt/{0}/{1}' -f $Matches[1].ToLowerInvariant(), $Matches[2].Replace('\', '/')

function Invoke-WslCamera {
    param([string[]]$CameraArguments)
    & wsl.exe -d $Distro -u root -- bash $cameraScript @CameraArguments
    if ($LASTEXITCODE -ne 0) { throw "Camera command failed: $($CameraArguments -join ' ')" }
}

$ready = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    & wsl.exe -d $Distro -u root -- bash $cameraScript check 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }
    Start-Sleep -Milliseconds 500
}
if (-not $ready) { throw 'Camera sensor did not become ready for preview diagnostics.' }

for ($cycle = 1; $cycle -le 2; $cycle++) {
    Write-Output "WINDOWS_PREVIEW_CYCLE=$cycle START"
    $preview = Start-Process -FilePath wsl.exe -ArgumentList @(
        '-d', ('"{0}"' -f $Distro), '-u', 'root', '--',
        'bash', ('"{0}"' -f $cameraScript), 'preview', 'on'
    ) -WindowStyle Hidden -PassThru

    Start-Sleep -Seconds 5
    $aliveAtFiveSeconds = -not $preview.HasExited
    $rdpWindows = @(Get-Process msrdc -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
    Write-Output "WRAPPER_ALIVE=$aliveAtFiveSeconds"
    Write-Output "WSLG_VISIBLE_WINDOWS=$($rdpWindows.Count)"
    foreach ($window in $rdpWindows) {
        Write-Output "WSLG_TITLE=$($window.MainWindowTitle)"
    }
    if (-not $aliveAtFiveSeconds) {
        throw "Preview wrapper exited before cycle $cycle could be used."
    }

    Invoke-WslCamera -CameraArguments @('stop-preview')
    if (-not $preview.WaitForExit(10000)) {
        throw "Preview wrapper did not exit after cycle $cycle stopped."
    }
    Write-Output "WINDOWS_PREVIEW_CYCLE=$cycle CLOSED"
    Start-Sleep -Seconds 2
}

Write-Output 'WINDOWS_REPEATED_PREVIEW_DIAGNOSTIC_OK'

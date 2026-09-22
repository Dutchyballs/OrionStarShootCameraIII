$ErrorActionPreference = 'Stop'

$logPath = Join-Path $PSScriptRoot 'setup-wsl-camera-bridge.log'
Start-Transcript -Path $logPath -Force

try {
    Write-Output 'Enabling Windows Subsystem for Linux...'
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart

    Write-Output 'Enabling Virtual Machine Platform...'
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart

    Write-Output 'Installing the official WSL package...'
    winget install --id Microsoft.WSL --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "WSL package installation failed with exit code $LASTEXITCODE"
    }

    Write-Output 'Installing the official usbipd-win USB bridge...'
    winget install --id dorssel.usbipd-win --exact --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "usbipd-win installation failed with exit code $LASTEXITCODE"
    }

    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'setup-wsl-camera-bridge.complete') -Value (Get-Date -Format o)
    Write-Output 'SETUP COMPLETE'
}
catch {
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'setup-wsl-camera-bridge.failed') -Value ($_ | Out-String)
    throw
}
finally {
    Stop-Transcript
}

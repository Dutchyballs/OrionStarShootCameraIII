$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'Requesting Windows administrator approval...'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    $elevated = Start-Process -FilePath powershell.exe -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $elevated.ExitCode
}

$command = Get-Command usbipd.exe -ErrorAction SilentlyContinue
$usbipd = if ($null -ne $command) { $command.Source } else { Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe' }
if (-not (Test-Path -LiteralPath $usbipd)) {
    throw 'usbipd-win is not installed. Install it before sharing the camera.'
}

$lines = & $usbipd list 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Unable to list USB devices with usbipd-win.' }
$busIds = @(
    foreach ($line in $lines) {
        if ([string]$line -match '^\s*(\S+)\s+0e96:c001\s+') { $Matches[1] }
    }
)
if ($busIds.Count -eq 0) { throw 'Orion camera 0e96:c001 was not found. Connect it and try again.' }
if ($busIds.Count -gt 1) { throw 'More than one Orion camera was found. Connect only the camera you want to share.' }
Write-Output "Sharing the Orion camera on USB port $($busIds[0])..."
& $usbipd bind --busid $busIds[0]
$result = $LASTEXITCODE
& $usbipd list
exit $result

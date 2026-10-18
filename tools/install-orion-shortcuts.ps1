$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { throw 'The Windows Desktop folder could not be found.' }
$shell = New-Object -ComObject WScript.Shell
foreach ($item in @(
    @{ Name = 'Orion StarShoot Camera'; File = 'Launch Orion StarShoot.cmd' },
    @{ Name = 'Restart Orion Camera'; File = 'Restart Orion Camera.cmd' }
)) {
    $target = Join-Path $repo $item.File
    $path = Join-Path $desktop ($item.Name + '.lnk')
    $shortcut = $shell.CreateShortcut($path)
    if ((Test-Path -LiteralPath $path) -and $shortcut.TargetPath -ne $target) {
        throw "Preserving existing shortcut with another target: $path"
    }
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $repo
    $shortcut.Description = if ($item.Name -like 'Restart*') { 'Stop preview, reconnect only Orion, and reopen its panel. Stop recording first.' } else { 'Open the Orion StarShoot camera panel.' }
    $shortcut.Save()
    Write-Output "SHORTCUT_READY=$path"
}

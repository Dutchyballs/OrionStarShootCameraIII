$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$failed = $false
foreach ($file in Get-ChildItem -LiteralPath $projectRoot -Filter '*.ps1' -Recurse -File) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count -gt 0) {
        $parseErrors | Format-List
        $failed = $true
    }
    else { Write-Output "PARSE_OK=$($file.Name)" }
}
if ($failed) { throw 'One or more PowerShell files contain syntax errors.' }
Write-Output 'ALL_POWERSHELL_SYNTAX_OK'

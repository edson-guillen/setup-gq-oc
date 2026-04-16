[CmdletBinding()]
param(
    [switch]$WSL,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThruArgs
)

$env:SETUP_GQ_OC_REPO_DIR = $PSScriptRoot

$target = if ($WSL) {
    Join-Path $PSScriptRoot 'bootstrap\windows.ps1'
} else {
    Join-Path $PSScriptRoot 'bootstrap\windows-native.ps1'
}

& $target @PassThruArgs
exit $LASTEXITCODE

param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ScriptArgs = @()
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib/powershell-utils.ps1")
Invoke-HarnessBashScript -ScriptName "validate.sh" -ScriptArguments $ScriptArgs

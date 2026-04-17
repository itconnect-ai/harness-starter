param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ScriptArgs = @()
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib/package-runner.ps1")
. (Join-Path $PSScriptRoot "lib/git-utils.ps1")

Repair-HarnessWindowsEnvironment
Set-Location ((& git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace((Get-Location).Path)) {
  Set-Location (Split-Path -Parent $PSScriptRoot)
}

Write-Host "======================================"
Write-Host " Smoke Test Start"
Write-Host "======================================"

if (-not (Test-HarnessPackageJson)) {
  Write-Host "SKIPPED: no package.json (template state)"
  exit 0
}

if (-not [string]::IsNullOrWhiteSpace($env:HARNESS_SMOKE_CMD)) {
  Invoke-Expression $env:HARNESS_SMOKE_CMD
  exit $LASTEXITCODE
}

if (Test-HarnessPackageScript -Name "test:e2e") {
  Invoke-Expression "$(Get-HarnessRunPrefix) test:e2e"
  exit $LASTEXITCODE
}

if (Test-HarnessPackageScript -Name "test") {
  Write-Host "No test:e2e script found. Running test script as smoke fallback."
  Invoke-Expression "$(Get-HarnessRunPrefix) test"
  exit $LASTEXITCODE
}

Write-Host "SKIPPED: no HARNESS_SMOKE_CMD, test:e2e, or test script"
exit 0

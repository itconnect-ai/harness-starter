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

# timeout (초). 0 = 무제한.
$smokeTimeout = 600
if (-not [string]::IsNullOrWhiteSpace($env:HARNESS_SMOKE_TIMEOUT)) {
  $parsed = 0
  if ([int]::TryParse($env:HARNESS_SMOKE_TIMEOUT, [ref]$parsed)) { $smokeTimeout = $parsed }
}

function Invoke-SmokeWithTimeout {
  param([Parameter(Mandatory = $true)][string]$Command, [int]$TimeoutSeconds)

  if ($TimeoutSeconds -le 0) {
    Invoke-Expression $Command
    return $LASTEXITCODE
  }

  $job = Start-Job -ScriptBlock {
    param($cmd, $cwd)
    Set-Location $cwd
    Invoke-Expression $cmd
    return [int]$global:LASTEXITCODE
  } -ArgumentList $Command, (Get-Location).Path

  $finished = Wait-Job -Job $job -Timeout $TimeoutSeconds
  if ($null -eq $finished) {
    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    Write-Host "Smoke test exceeded ${TimeoutSeconds}s and was killed."
    return 124
  }

  $code = Receive-Job -Job $job -ErrorAction SilentlyContinue
  Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
  if ($code -is [array]) { $code = $code[-1] }
  if ($null -eq $code) { return 0 }
  return [int]$code
}

# 우선순위:
#   1. HARNESS_SMOKE_CMD (명시 우회)
#   2. test:e2e 스크립트 (있으면)
#   3. vitest/jest binary 직접 호출 (npm run test 호출은 watch 행 위험)
$cmd = $null
if (-not [string]::IsNullOrWhiteSpace($env:HARNESS_SMOKE_CMD)) {
  $cmd = $env:HARNESS_SMOKE_CMD
  Write-Host " Running HARNESS_SMOKE_CMD..."
} elseif (Test-HarnessPackageScript -Name "test:e2e") {
  $cmd = "$(Get-HarnessRunPrefix) test:e2e"
  Write-Host " Running $cmd..."
} elseif (Test-HarnessNodeBin -Name "vitest") {
  $cmd = "npx vitest run"
  Write-Host " Running vitest run (smoke fallback)..."
} elseif (Test-HarnessNodeBin -Name "jest") {
  $cmd = "npx jest --runInBand --ci"
  Write-Host " Running jest (smoke fallback)..."
} else {
  Write-Host "SKIPPED: no HARNESS_SMOKE_CMD, test:e2e script, or vitest/jest binary"
  exit 0
}

$exit = Invoke-SmokeWithTimeout -Command $cmd -TimeoutSeconds $smokeTimeout
if ($exit -ne 0) {
  Write-Host ""
  Write-Host "Smoke Test FAILED (exit: $exit)"
  exit $exit
}

Write-Host ""
Write-Host "======================================"
Write-Host " Smoke Test PASSED"
Write-Host "======================================"

param(
  [Parameter(Mandatory = $true)]
  [int]$Epic
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "../lib/git-utils.ps1")

Repair-HarnessWindowsEnvironment

function Stop-Setup2 {
  Write-Host "README.md의 Setup 2를 먼저 완료하세요"
  exit 1
}

Set-Location ((& git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
if ($LASTEXITCODE -ne 0) { Stop-Setup2 }

$branch = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
if ($branch -notin @("main", "develop")) { Stop-Setup2 }

& git rev-parse --verify develop *> $null
if ($LASTEXITCODE -ne 0) { Stop-Setup2 }

& git remote get-url origin *> $null
if ($LASTEXITCODE -ne 0) { Stop-Setup2 }

$remoteDevelop = Test-HarnessGitHubRemoteRef -Ref "develop"
if (-not $remoteDevelop.Ok) { Stop-Setup2 }

if (-not (Test-Path -LiteralPath ".agents/skills/bmad-create-story")) { Stop-Setup2 }
if (-not (Test-Path -LiteralPath ".agents/skills/bmad-dev-story")) { Stop-Setup2 }

$epicsPath = "_bmad-output/planning-artifacts/epics.md"
if (-not (Test-Path -LiteralPath $epicsPath -PathType Leaf)) { Stop-Setup2 }
$epics = Get-Content -LiteralPath $epicsPath -Raw
if ($epics -notmatch "(?m)^#{1,6}\s*Epic\s+$Epic\b|Epic\s+$Epic\s*:") { Stop-Setup2 }

if (-not (Test-Path -LiteralPath "_bmad-output/implementation-artifacts/sprint-status.yaml" -PathType Leaf)) { Stop-Setup2 }

Write-Host "Loop A preflight passed for Epic $Epic"
exit 0

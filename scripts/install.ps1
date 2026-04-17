# scripts/install.ps1
#
# PowerShell 환경에서 install.sh를 Git Bash로 안전하게 호출하는 래퍼.
# Windows 사용자가 `curl | bash`를 PowerShell에 그대로 쓸 수 없어서 필요.
#
# 원격 1줄 실행 (PowerShell에서):
#   iwr https://raw.githubusercontent.com/itconnect-ai/harness-test/main/scripts/install.ps1 -UseBasicParsing | iex
#
# 또는 다운로드 후 실행:
#   iwr https://raw.githubusercontent.com/itconnect-ai/harness-test/main/scripts/install.ps1 -OutFile install.ps1
#   .\install.ps1 -DryRun
#   .\install.ps1
#   .\install.ps1 -Force
#   .\install.ps1 -Branch develop

param(
  [switch]$DryRun,
  [switch]$Force,
  [string]$Branch = "main",
  [string]$Repo = "itconnect-ai/harness-test",
  [string]$Target = $PWD
)

$ErrorActionPreference = "Stop"

# ── Git Bash 찾기 ──
$candidates = @(
  "C:\Program Files\Git\bin\bash.exe",
  "C:\Program Files (x86)\Git\bin\bash.exe",
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)

$bashPath = $null
foreach ($candidate in $candidates) {
  if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
  if (Test-Path $candidate -PathType Leaf) {
    $bashPath = $candidate
    break
  }
}

if (-not $bashPath) {
  $gitBash = Get-Command bash -ErrorAction SilentlyContinue
  if ($gitBash -and $gitBash.Source -match '\\Git\\(usr\\)?bin\\bash\.exe$') {
    $bashPath = $gitBash.Source
  }
}

if (-not $bashPath) {
  Write-Error @"
Git Bash를 찾을 수 없습니다.

설치: https://git-scm.com/download/win
  winget install --id Git.Git -e --source winget

설치 후 PowerShell을 재시작하고 이 스크립트를 다시 실행하세요.

WSL은 Docker Desktop 연동 이슈로 지원하지 않습니다
(docker/for-win#14867).
"@
  exit 1
}

# ── 인자 조립 ──
$scriptArgs = @()
if ($DryRun) { $scriptArgs += "--dry-run" }
if ($Force)  { $scriptArgs += "--force" }
$scriptArgs += "--branch"; $scriptArgs += $Branch
$scriptArgs += "--repo";   $scriptArgs += $Repo
$scriptArgs += "--target"; $scriptArgs += $Target

$scriptArgsEscaped = ($scriptArgs | ForEach-Object { "'$_'" }) -join " "

# ── install.sh 다운로드 → Git Bash로 실행 ──
$installUrl = "https://raw.githubusercontent.com/$Repo/$Branch/scripts/install.sh"
$tempScript = Join-Path $env:TEMP "harness-install-$(Get-Date -Format 'yyyyMMddHHmmss').sh"

Write-Host "Downloading install.sh from $installUrl..."
try {
  Invoke-WebRequest -Uri $installUrl -OutFile $tempScript -UseBasicParsing
} catch {
  Write-Error "install.sh 다운로드 실패: $_"
  exit 1
}

# Git Bash에서 실행
$tempScriptBashPath = $tempScript -replace '\\', '/' -replace '^([A-Za-z]):', '/${1}'
$tempScriptBashPath = $tempScriptBashPath.ToLower()
# Windows 경로 C:\... → /c/...
if ($tempScript -match '^([A-Za-z]):(.*)$') {
  $drive = $Matches[1].ToLowerInvariant()
  $rest = ($Matches[2] -replace '\\', '/')
  $tempScriptBashPath = "/$drive$rest"
}

$bashCommand = "bash '$tempScriptBashPath' $scriptArgsEscaped"

try {
  & $bashPath -lc $bashCommand
  $exitCode = $LASTEXITCODE
} finally {
  if (Test-Path $tempScript) { Remove-Item $tempScript -Force }
}

exit $exitCode

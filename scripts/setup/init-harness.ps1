param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
  Write-Error "git repo 아님. 'git init' 또는 git clone 후 실행하세요."
  exit 1
}

Set-Location $repoRoot.Trim()

Write-Host "=== 하네스 자동 초기화 ==="
if ($DryRun) {
  Write-Host "(dry-run 모드 - 실제 변경하지 않음)"
}
Write-Host ""

Write-Host "[1/2] Git hooks 설치"
$installHooks = Join-Path "scripts/setup" "install-git-hooks.ps1"
if (-not (Test-Path -LiteralPath $installHooks -PathType Leaf)) {
  Write-Host "  install-git-hooks.ps1 없음 - skip" -ForegroundColor Yellow
} elseif ($DryRun) {
  Write-Host "  [DRY RUN] ./scripts/setup/install-git-hooks.ps1 실행 예정"
} else {
  try {
    & $installHooks | ForEach-Object { Write-Host "  $_" }
    Write-Host "  hooks 활성화"
  } catch {
    Write-Host "  hooks 설정 실패 - 위 로그 확인" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "[2/2] GitHub repo 보안 설정"

$skipReason = ""
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  $skipReason = "gh CLI 미설치"
} else {
  & gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    $skipReason = "gh 인증 미완료 ('gh auth login' 필요)"
  }
}

if ([string]::IsNullOrWhiteSpace($skipReason)) {
  & git remote get-url origin *> $null
  if ($LASTEXITCODE -ne 0) {
    $skipReason = "git origin 미설정 (GitHub repo 생성 + 'git remote add origin' 필요)"
  }
}

$setupRepo = Join-Path "scripts/setup" "setup-repo.ps1"
if (-not [string]::IsNullOrWhiteSpace($skipReason)) {
  Write-Host "  SKIP - $skipReason"
  Write-Host ""
  Write-Host "  전제 조건 충족 후 수동 실행:"
  Write-Host "    ./scripts/setup/setup-repo.ps1"
} elseif (-not (Test-Path -LiteralPath $setupRepo -PathType Leaf)) {
  Write-Host "  setup-repo.ps1 없음 - skip" -ForegroundColor Yellow
} elseif ($DryRun) {
  & $setupRepo -DryRun | ForEach-Object { Write-Host "  $_" }
} else {
  try {
    & $setupRepo | ForEach-Object { Write-Host "  $_" }
    Write-Host "  repo 보안 설정 완료"
  } catch {
    Write-Host "  일부 설정 실패 - 위 로그 확인. private repo는 GHAS 라이선스 필요할 수 있음" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "=== 하네스 초기화 완료 ==="
Write-Host ""
Write-Host "다음 단계:"
Write-Host "  1. BMAD 설치:        npx bmad-method install"
Write-Host "  2. BMAD 기획/설계:   Claude Code로 PRD/architecture/epics 생성"
Write-Host "  3. 프로젝트 초기화:  README.md의 4단계 프롬프트 실행"

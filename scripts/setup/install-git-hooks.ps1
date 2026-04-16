param()

$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $repoRoot

if (-not (Test-Path ".githooks")) {
  Write-Error ".githooks/ 디렉토리가 없습니다. 이 스크립트는 template 원본에서만 동작합니다."
  exit 1
}

git config core.hooksPath .githooks

Write-Host "Git hooks installed:" -ForegroundColor Green
Write-Host "  - pre-commit: staged 파일 eslint + .env 차단 + 대형 커밋 경고"
Write-Host "  - commit-msg: Conventional Commits 형식 검증"
Write-Host ""
Write-Host "비활성화: git config --unset core.hooksPath"

param(
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Error @"
gh CLI 필요.

설치: https://cli.github.com
  Windows: winget install GitHub.cli
  macOS:   brew install gh
  Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md
"@
  exit 1
}

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Error "gh 인증 필요. 'gh auth login' 실행 후 재시도."
  exit 1
}

$repo = & gh repo view --json owner,name -q '.owner.login + "/" + .name' 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) {
  Write-Error "현재 디렉토리가 GitHub repo가 아니거나 origin이 설정되지 않음."
  exit 1
}
$repo = $repo.Trim()

Write-Host "=== Setting up repository: $repo ==="
Write-Host ""

if ($DryRun) {
  Write-Host "[DRY RUN] 실제 변경하지 않음. 아래 단계를 적용 예정:"
  Write-Host "  1. Secret Scanning + Push Protection 활성화"
  Write-Host "  2. main 브랜치 protection 설정"
  Write-Host "  3. develop 브랜치 protection 설정 (브랜치 존재 시)"
  exit 0
}

Write-Host "[1/3] Secret Scanning + Push Protection..."
& gh api -X PATCH "/repos/$repo" `
  -F 'security_and_analysis[secret_scanning][status]=enabled' `
  -F 'security_and_analysis[secret_scanning_push_protection][status]=enabled' *> $null
if ($LASTEXITCODE -eq 0) {
  Write-Host "  enabled"
} else {
  Write-Host "  활성화 실패 (private repo는 GitHub Enterprise 또는 GHAS 라이선스 필요)" -ForegroundColor Yellow
}

function Set-BranchProtection {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Branch,
    [Parameter(Mandatory = $true)]
    [bool]$RequireCodeOwnerReviews
  )

  $payload = [pscustomobject]@{
    required_status_checks = [pscustomobject]@{
      strict = $true
      contexts = @("quality-gate", "gitleaks", "codeql")
    }
    enforce_admins = $false
    required_pull_request_reviews = [pscustomobject]@{
      required_approving_review_count = 1
      dismiss_stale_reviews = $true
      require_code_owner_reviews = $RequireCodeOwnerReviews
    }
    restrictions = $null
    allow_force_pushes = $false
    allow_deletions = $false
    required_conversation_resolution = $true
  }

  $tmp = Join-Path ([IO.Path]::GetTempPath()) "branch-protection-$Branch-$(Get-Date -Format 'yyyyMMddHHmmss').json"
  try {
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp
    & gh api -X PUT "/repos/$repo/branches/$Branch/protection" --input $tmp *> $null
    return ($LASTEXITCODE -eq 0)
  } finally {
    if (Test-Path -LiteralPath $tmp) {
      Remove-Item -LiteralPath $tmp -Force
    }
  }
}

Write-Host ""
Write-Host "[2/3] main 브랜치 protection..."
if (Set-BranchProtection -Branch "main" -RequireCodeOwnerReviews $false) {
  Write-Host "  applied"
} else {
  Write-Host "  설정 실패 - main 브랜치가 없거나 권한 부족" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[3/3] develop 브랜치 protection..."
& gh api "/repos/$repo/branches/develop" *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "  develop 브랜치 없음 - skip (나중에 develop 생성 후 이 스크립트 재실행)"
} elseif (Set-BranchProtection -Branch "develop" -RequireCodeOwnerReviews $false) {
  Write-Host "  applied"
} else {
  Write-Host "  설정 실패" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 완료 ==="
Write-Host ""
Write-Host "확인 방법:"
Write-Host "  https://github.com/$repo/settings/branches"
Write-Host "  https://github.com/$repo/settings/security_analysis"
Write-Host ""
Write-Host "주의: 'quality-gate', 'gitleaks', 'codeql'은 각 workflow의 job 이름입니다."

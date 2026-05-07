# scripts/install.ps1
#
# Harness Engineering Starter Kit의 필수 파일을 Windows PowerShell에서 native로 설치합니다.
# Git Bash는 필요하지 않습니다.
#
# 원격 1줄 실행 (PowerShell에서):
#   iwr https://raw.githubusercontent.com/itconnect-ai/harness-starter/main/scripts/install.ps1 -UseBasicParsing | iex
#
# 또는 다운로드 후 실행:
#   iwr https://raw.githubusercontent.com/itconnect-ai/harness-starter/main/scripts/install.ps1 -OutFile install.ps1
#   .\install.ps1 -DryRun
#   .\install.ps1
#   .\install.ps1 -Force
#   .\install.ps1 -Branch develop

param(
  [switch]$DryRun,
  [switch]$Force,
  [string]$Branch = "main",
  [string]$Repo = "itconnect-ai/harness-starter",
  [string]$Target = $PWD
)

$ErrorActionPreference = "Stop"

$essentialPaths = @(
  "CLAUDE.md",
  "AGENTS.md",
  "REVIEW.md",
  "README-brownfield.md",
  ".gitattributes",
  ".gitleaks.toml",
  "docs/agents",
  "docs/checklists",
  "docs/future-upgrades",
  "docs/decisions/README.md",
  "docs/org/docker-port-registry.template.md",
  "templates",
  "scripts",
  ".claude/hooks",
  ".claude/settings.json",
  ".githooks",
  ".github/workflows",
  ".github/dependabot.yml",
  "state/learning-loop.json",
  "state/progress-template.json",
  "state/README.md",
  "feedback/incident-template.yaml",
  "feedback/incidents/README.md",
  "reviews/README.md",
  "plans/README.md",
  "private/README.md"
)

function Copy-HarnessPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,
    [Parameter(Mandatory = $true)]
    [string]$TargetRoot,
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  $src = Join-Path $SourceRoot $RelativePath
  $dest = Join-Path $TargetRoot $RelativePath

  if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "  source missing: $RelativePath" -ForegroundColor Yellow
    return "missing"
  }

  $exists = Test-Path -LiteralPath $dest
  if ($exists -and -not $Force) {
    Write-Host "  exists, skip (use -Force to overwrite): $RelativePath"
    return "exists"
  }

  if ($DryRun) {
    if ($exists) {
      Write-Host "  [DRY RUN] overwrite: $RelativePath"
    } else {
      Write-Host "  [DRY RUN] copy:      $RelativePath"
    }
    return "copied"
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
  if ((Get-Item -LiteralPath $src).PSIsContainer) {
    if ($exists) {
      Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Copy-Item -LiteralPath $src -Destination $dest -Recurse
  } else {
    Copy-Item -LiteralPath $src -Destination $dest -Force:$Force
  }

  if ($exists) {
    Write-Host "  ok $RelativePath (overwritten)"
    return "overwrote"
  }

  Write-Host "  ok $RelativePath"
  return "copied"
}

if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
  Write-Error "target 디렉토리 없음: $Target"
  exit 1
}

$targetRoot = (Resolve-Path -LiteralPath $Target).Path
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "harness-install-$(Get-Date -Format 'yyyyMMddHHmmss')"
$zipPath = Join-Path $tempRoot "template.zip"
$extractRoot = Join-Path $tempRoot "extract"
$url = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"

Write-Host "=============================================="
Write-Host " Harness Engineering Starter - 필수 파일 설치"
Write-Host "=============================================="
Write-Host "  Template: github.com/$Repo@$Branch"
Write-Host "  Target:   $targetRoot"
if ($DryRun) { Write-Host "  Mode:     DRY RUN" }
if ($Force) { Write-Host "  Force:    기존 파일 덮어쓰기" }
Write-Host ""

New-Item -ItemType Directory -Force -Path $tempRoot, $extractRoot | Out-Null

try {
  Write-Host "[1/3] Downloading zip..."
  Write-Host "      $url"
  Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

  Write-Host "[2/3] Extracting..."
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
  $sourceRoot = Get-ChildItem -LiteralPath $extractRoot -Directory | Select-Object -First 1
  if ($null -eq $sourceRoot) {
    throw "zip 구조 예상과 다름"
  }

  Write-Host "[3/3] Installing files..."
  Write-Host ""

  $copied = 0
  $overwrote = 0
  $skippedExists = 0
  $skippedMissing = 0

  foreach ($path in $essentialPaths) {
    $result = Copy-HarnessPath -SourceRoot $sourceRoot.FullName -TargetRoot $targetRoot -RelativePath $path
    switch ($result) {
      "copied" { $copied += 1 }
      "overwrote" { $copied += 1; $overwrote += 1 }
      "exists" { $skippedExists += 1 }
      "missing" { $skippedMissing += 1 }
    }
  }

  Write-Host ""
  Write-Host "=============================================="
  Write-Host " 완료"
  Write-Host "=============================================="
  Write-Host "  copied:            $copied"
  Write-Host "  overwrote:         $overwrote"
  Write-Host "  skipped (exists):  $skippedExists"
  Write-Host "  skipped (missing): $skippedMissing"
  Write-Host ""

  if ($DryRun) {
    Write-Host "DRY RUN 완료. 실제 설치하려면 -DryRun 제거."
  } elseif ($copied -gt 0) {
    Write-Host "다음 단계:"
    Write-Host "  1. ./scripts/setup/init-harness.ps1"
    Write-Host "  2. npx bmad-method install"
    Write-Host "  3. README.md 4단계 프롬프트를 Claude Code에서 실행"
  }
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}

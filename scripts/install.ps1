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

  # CodeQL 언어 감지 + security.yml 갱신
  # 기본 [javascript-typescript]은 JS/TS가 아닌 프로젝트에서 SAST가 무의미함.
  # 마커 파일로 언어를 감지해 matrix를 자동 갱신. 사용자가 이미 커스터마이징한
  # 경우(라인이 기본값과 다름)는 손대지 않음.
  $langDetectNote = ""
  $securityYml = Join-Path $targetRoot ".github/workflows/security.yml"
  if (-not $DryRun -and (Test-Path -LiteralPath $securityYml)) {
    $detected = New-Object System.Collections.Generic.List[string]

    if (Test-Path -LiteralPath (Join-Path $targetRoot "package.json")) {
      $detected.Add("javascript-typescript") | Out-Null
    }
    $pythonMarkers = @("pyproject.toml", "setup.py", "requirements.txt", "Pipfile")
    foreach ($m in $pythonMarkers) {
      if (Test-Path -LiteralPath (Join-Path $targetRoot $m)) {
        if (-not $detected.Contains("python")) { $detected.Add("python") | Out-Null }
        break
      }
    }
    if (Test-Path -LiteralPath (Join-Path $targetRoot "go.mod")) {
      $detected.Add("go") | Out-Null
    }
    $hasGradle = (Test-Path -LiteralPath (Join-Path $targetRoot "pom.xml")) -or
                 (@(Get-ChildItem -LiteralPath $targetRoot -Filter "*.gradle" -ErrorAction SilentlyContinue).Count -gt 0) -or
                 (@(Get-ChildItem -LiteralPath $targetRoot -Filter "*.gradle.kts" -ErrorAction SilentlyContinue).Count -gt 0)
    if ($hasGradle) { $detected.Add("java-kotlin") | Out-Null }
    $hasDotnet = (@(Get-ChildItem -LiteralPath $targetRoot -Filter "*.csproj" -ErrorAction SilentlyContinue).Count -gt 0) -or
                 (@(Get-ChildItem -LiteralPath $targetRoot -Filter "*.sln" -ErrorAction SilentlyContinue).Count -gt 0)
    if ($hasDotnet) { $detected.Add("csharp") | Out-Null }
    if (Test-Path -LiteralPath (Join-Path $targetRoot "Gemfile")) {
      $detected.Add("ruby") | Out-Null
    }
    if (Test-Path -LiteralPath (Join-Path $targetRoot "Package.swift")) {
      $detected.Add("swift") | Out-Null
    }

    if ($detected.Count -gt 0) {
      $matrixCsv = ($detected -join ", ")
      $content = Get-Content -LiteralPath $securityYml -Raw
      $defaultPattern = "(?m)^(\s*)language:\s*\[javascript-typescript\]\s*$"
      if ($content -match $defaultPattern) {
        $newContent = [regex]::Replace($content, $defaultPattern, "`${1}language: [$matrixCsv]")
        Set-Content -LiteralPath $securityYml -Value $newContent -NoNewline -Encoding UTF8
        $langDetectNote = "감지된 CodeQL 언어 -> matrix [$matrixCsv] 적용"
      } else {
        $langDetectNote = "security.yml language matrix 사용자 커스터마이징 감지 -> 보존 (감지: [$matrixCsv])"
      }
    } else {
      $langDetectNote = "언어 마커 파일 미감지 -> security.yml [javascript-typescript] 기본값 유지 (수동 조정 필요할 수 있음)"
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
  if ($langDetectNote -ne "") {
    Write-Host "  CodeQL: $langDetectNote"
  }
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

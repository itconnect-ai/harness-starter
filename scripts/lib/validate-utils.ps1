Set-StrictMode -Version Latest

$script:ValidateOutputMode = if ([string]::IsNullOrWhiteSpace($env:VALIDATE_OUTPUT_MODE)) { "summary" } else { $env:VALIDATE_OUTPUT_MODE }
$script:ValidateLogDir = ""
$script:ValidateRunType = ""
$script:ValidateTotalSteps = 0
$script:ValidatePassedSteps = 0
$script:ValidateFailedStep = ""
$script:ValidateFailedCode = 0
$script:ValidateStartTime = Get-Date

# 단계별 timeout (초). 0 = 무제한. 환경변수로 오버라이드.
function Get-HarnessStepTimeout {
  param([Parameter(Mandatory = $true)][string]$StepName)

  $envMap = @{
    "install"          = "VALIDATE_INSTALL_TIMEOUT"
    "typecheck"        = "VALIDATE_TYPECHECK_TIMEOUT"
    "lint"             = "VALIDATE_LINT_TIMEOUT"
    "test"             = "VALIDATE_TEST_TIMEOUT"
    "regression-test"  = "VALIDATE_TEST_TIMEOUT"
    "related-tests"    = "VALIDATE_TEST_TIMEOUT"
    "build"            = "VALIDATE_BUILD_TIMEOUT"
  }
  $defaults = @{
    "install"          = 1800
    "typecheck"        = 600
    "lint"             = 300
    "test"             = 1200
    "regression-test"  = 1200
    "related-tests"    = 1200
    "build"            = 1200
  }

  $envName = $envMap[$StepName]
  if ($envName) {
    $val = [Environment]::GetEnvironmentVariable($envName)
    if (-not [string]::IsNullOrWhiteSpace($val)) {
      $parsed = 0
      if ([int]::TryParse($val, [ref]$parsed)) { return $parsed }
    }
    return $defaults[$StepName]
  }

  $val = [Environment]::GetEnvironmentVariable("VALIDATE_DEFAULT_TIMEOUT")
  if (-not [string]::IsNullOrWhiteSpace($val)) {
    $parsed = 0
    if ([int]::TryParse($val, [ref]$parsed)) { return $parsed }
  }
  return 600
}

function Get-HarnessRepoRoot {
  $repo = (& git rev-parse --show-toplevel 2>$null)
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($repo)) {
    return $repo.Trim()
  }

  return (Resolve-Path -LiteralPath ".").Path
}

function Initialize-HarnessValidation {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RunType
  )

  $script:ValidateRunType = $RunType
  $script:ValidateStartTime = Get-Date
  $script:ValidateTotalSteps = 0
  $script:ValidatePassedSteps = 0
  $script:ValidateFailedStep = ""
  $script:ValidateFailedCode = 0

  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $validateRoot = Join-Path "state" "validate"
  $runDir = Join-Path $validateRoot "$RunType-$timestamp"
  $latest = Join-Path $validateRoot "latest"

  New-Item -ItemType Directory -Force -Path $runDir | Out-Null
  if (Test-Path -LiteralPath $latest) {
    Remove-Item -LiteralPath $latest -Recurse -Force
  }

  $linked = $false
  try {
    New-Item -ItemType SymbolicLink -Path $latest -Target (Resolve-Path -LiteralPath $runDir).Path -ErrorAction Stop | Out-Null
    $linked = $true
  } catch {
    try {
      New-Item -ItemType Junction -Path $latest -Target (Resolve-Path -LiteralPath $runDir).Path -ErrorAction Stop | Out-Null
      $linked = $true
    } catch {
      $linked = $false
    }
  }

  $script:ValidateLogDir = $runDir

  if ($script:ValidateOutputMode -eq "summary") {
    Write-Host "======================================"
    Write-Host " Validation Start ($RunType-level)"
    Write-Host " Mode: summary (set VALIDATE_OUTPUT_MODE=verbose for full output)"
    if ($linked) {
      Write-Host " Logs: state\validate\latest\"
    } else {
      Write-Host " Logs: $runDir\"
    }
    Write-Host "======================================"
  }
}

function Invoke-HarnessCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [Parameter(Mandatory = $true)]
    [string]$LogFile,
    [int]$TimeoutSeconds = 0
  )

  # timeout 적용: PowerShell Job으로 격리해 hard cap 보장.
  # vitest watch, eslint 무한 루프, npm registry hang 등 어떤 외부 원인으로도
  # 영구 행에 빠지지 않도록 한다. 0이면 무가드 실행.
  if ($TimeoutSeconds -gt 0) {
    $job = Start-Job -ScriptBlock {
      param($cmd, $log, $cwd)
      Set-Location $cwd
      try {
        Invoke-Expression $cmd *> $log
        return [int]$global:LASTEXITCODE
      } catch {
        $_ | Out-String | Add-Content -LiteralPath $log
        return 1
      }
    } -ArgumentList $Command, $LogFile, (Get-Location).Path

    $finished = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if ($null -eq $finished) {
      Stop-Job -Job $job -ErrorAction SilentlyContinue
      Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
      Add-Content -LiteralPath $LogFile -Value @"

-- HARNESS TIMEOUT ----------------------
  Step exceeded ${TimeoutSeconds}s and was killed.
  Tune via env: VALIDATE_*_TIMEOUT (0 = unlimited).
"@
      return 124
    }

    $exitFromJob = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    if ($exitFromJob -is [array]) { $exitFromJob = $exitFromJob[-1] }
    if ($null -eq $exitFromJob) { return 0 }
    return [int]$exitFromJob
  }

  $global:LASTEXITCODE = 0
  try {
    if ($script:ValidateOutputMode -eq "verbose") {
      Invoke-Expression $Command 2>&1 | Tee-Object -FilePath $LogFile
    } else {
      Invoke-Expression $Command *> $LogFile
    }

    if ($null -ne $global:LASTEXITCODE -and $global:LASTEXITCODE -ne 0) {
      return [int]$global:LASTEXITCODE
    }
    return 0
  } catch {
    $_ | Out-String | Add-Content -LiteralPath $LogFile
    return 1
  }
}

function Invoke-HarnessStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StepNumber,
    [Parameter(Mandatory = $true)]
    [string]$StepName,
    [Parameter(Mandatory = $true)]
    [string]$Command
  )

  $script:ValidateTotalSteps += 1
  $logFile = Join-Path $script:ValidateLogDir "$StepNumber-$StepName.log"
  $start = Get-Date

  if ($script:ValidateOutputMode -eq "summary") {
    Write-Host ("[{0}] {1,-20} " -f $StepNumber, $StepName) -NoNewline
  } else {
    Write-Host ""
    Write-Host "[$StepNumber] $StepName..."
  }

  $tmout = Get-HarnessStepTimeout -StepName $StepName
  $exitCode = Invoke-HarnessCommand -Command $Command -LogFile $logFile -TimeoutSeconds $tmout
  $elapsed = [int]((Get-Date) - $start).TotalSeconds

  if ($exitCode -eq 0) {
    $script:ValidatePassedSteps += 1
    if ($script:ValidateOutputMode -eq "summary") {
      Write-Host "PASSED (${elapsed}s)"
    } else {
      Write-Host "[$StepNumber] ${StepName}: PASSED (${elapsed}s)"
    }
    return
  }

  $script:ValidateFailedStep = $StepName
  $script:ValidateFailedCode = $exitCode
  if ($script:ValidateOutputMode -eq "summary") {
    Write-Host "FAILED (${elapsed}s)"
    Write-HarnessFailureSummary -StepNumber $StepNumber -StepName $StepName -ExitCode $exitCode -LogFile $logFile
  } else {
    Write-Host "[$StepNumber] ${StepName}: FAILED (exit: $exitCode, ${elapsed}s)"
    Write-Host "  Log: $logFile"
  }

  throw "Validation step failed: $StepName"
}

function Invoke-HarnessStepSkip {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StepNumber,
    [Parameter(Mandatory = $true)]
    [string]$StepName,
    [string]$Reason = "skipped"
  )

  $script:ValidateTotalSteps += 1
  $script:ValidatePassedSteps += 1
  if ($script:ValidateOutputMode -eq "summary") {
    Write-Host ("[{0}] {1,-20} SKIPPED ({2})" -f $StepNumber, $StepName, $Reason)
  } else {
    Write-Host ""
    Write-Host "[$StepNumber] $StepName... SKIPPED ($Reason)"
  }
}

function Write-HarnessFailureSummary {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StepNumber,
    [Parameter(Mandatory = $true)]
    [string]$StepName,
    [Parameter(Mandatory = $true)]
    [int]$ExitCode,
    [Parameter(Mandatory = $true)]
    [string]$LogFile
  )

  Write-Host ""
  Write-Host "-- Failure Detail ----------------------"
  Write-Host "  Step:      [$StepNumber] $StepName"
  Write-Host "  Exit code: $ExitCode"
  Write-Host "  Log:       $LogFile"

  if (Test-Path -LiteralPath $LogFile) {
    $lines = Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue
    $tailCount = [Math]::Min(50, $lines.Count)
    Write-Host "  Last $tailCount lines:"
    $lines | Select-Object -Last $tailCount | ForEach-Object { Write-Host "    $_" }
  }

  Write-Host "----------------------------------------"
}

function Complete-HarnessValidation {
  $elapsed = [int]((Get-Date) - $script:ValidateStartTime).TotalSeconds
  Write-Host ""

  if (-not [string]::IsNullOrWhiteSpace($script:ValidateFailedStep)) {
    Write-Host "======================================"
    Write-Host " Validation FAILED"
    Write-Host "  Failed at: $($script:ValidateFailedStep) (exit: $($script:ValidateFailedCode))"
    Write-Host "  Steps:     $($script:ValidatePassedSteps)/$($script:ValidateTotalSteps) passed"
    Write-Host "  Duration:  ${elapsed}s"
    Write-Host "  Logs:      $($script:ValidateLogDir)\"
    Write-Host "======================================"
    return 1
  }

  Write-Host "======================================"
  Write-Host " Validation PASSED"
  Write-Host "  Steps:    $($script:ValidatePassedSteps)/$($script:ValidateTotalSteps) passed"
  Write-Host "  Duration: ${elapsed}s"
  Write-Host "  Logs:     $($script:ValidateLogDir)\"
  Write-Host "======================================"
  return 0
}

function Get-HarnessSearchFiles {
  param(
    [string]$Path = "src",
    [string[]]$Include = @("*.ts", "*.tsx", "*.js", "*.jsx")
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return @()
  }

  # 우선 git ls-files를 시도 — .gitignore를 자동 적용해 node_modules 등 노이즈를
  # 사전 제거. Get-ChildItem -Recurse는 모든 파일을 enumerate한 뒤 사후 필터라
  # 대형 monorepo에서 분 단위 소요. git 기반은 수 초 이내.
  # git이 없거나 저장소가 아니면 Get-ChildItem fallback (이전 동작과 동일).
  $gitOK = $false
  try {
    & git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) { $gitOK = $true }
  } catch {
    $gitOK = $false
  }

  if ($gitOK) {
    $tracked = @()
    $untracked = @()
    try {
      $tracked = @(& git ls-files -- $Path 2>$null)
      $untracked = @(& git ls-files --others --exclude-standard -- $Path 2>$null)
    } catch {
      # git 호출 실패 시 fallback 경로로 전환
      $gitOK = $false
    }

    if ($gitOK) {
      $allPaths = @($tracked + $untracked) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

      # 확장자 필터 (Include 패턴 "*.ts" → 접미사 ".ts" 비교)
      $suffixes = $Include | ForEach-Object { $_.TrimStart('*') }
      $matched = $allPaths | Where-Object {
        $candidate = $_
        $hit = $false
        foreach ($suf in $suffixes) {
          if ($candidate.EndsWith($suf, [System.StringComparison]::OrdinalIgnoreCase)) {
            $hit = $true
            break
          }
        }
        $hit
      }

      # FileInfo로 변환 (Select-String이 .FullName/.Path를 사용).
      # 삭제된 파일은 Get-Item이 null을 반환하므로 사후 필터링.
      return $matched |
        ForEach-Object { Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue } |
        Where-Object { $null -ne $_ }
    }
  }

  # Fallback: Get-ChildItem with noise filter
  $noise = @(
    ".git", "node_modules", ".venv", "venv", "dist", "build", "coverage",
    ".next", ".turbo", ".cache", ".tmp", "playwright-report", "test-results",
    "__pycache__"
  )

  return Get-ChildItem -LiteralPath $Path -Recurse -File -Include $Include -ErrorAction SilentlyContinue |
    Where-Object {
      $fullName = $_.FullName
      -not ($noise | Where-Object { $fullName -match [regex]::Escape([IO.Path]::DirectorySeparatorChar + $_ + [IO.Path]::DirectorySeparatorChar) })
    }
}

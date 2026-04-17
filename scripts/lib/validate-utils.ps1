Set-StrictMode -Version Latest

$script:ValidateOutputMode = if ([string]::IsNullOrWhiteSpace($env:VALIDATE_OUTPUT_MODE)) { "summary" } else { $env:VALIDATE_OUTPUT_MODE }
$script:ValidateLogDir = ""
$script:ValidateRunType = ""
$script:ValidateTotalSteps = 0
$script:ValidatePassedSteps = 0
$script:ValidateFailedStep = ""
$script:ValidateFailedCode = 0
$script:ValidateStartTime = Get-Date

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
    [string]$LogFile
  )

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

  $exitCode = Invoke-HarnessCommand -Command $Command -LogFile $logFile
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

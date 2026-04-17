param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ScriptArgs = @()
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib/validate-utils.ps1")
. (Join-Path $PSScriptRoot "lib/package-runner.ps1")
. (Join-Path $PSScriptRoot "lib/git-utils.ps1")

Repair-HarnessWindowsEnvironment
Set-Location (Get-HarnessRepoRoot)

try {
  Initialize-HarnessValidation -RunType "quick"

  $baseRef = $env:VALIDATE_BASE_REF
  if ([string]::IsNullOrWhiteSpace($baseRef)) {
    foreach ($ref in @("origin/develop", "develop", "origin/main", "main")) {
      & git rev-parse --verify $ref *> $null
      if ($LASTEXITCODE -eq 0) {
        $baseRef = $ref
        break
      }
    }
  }

  $hasPackageJson = Test-HarnessPackageJson

  if (-not $hasPackageJson) {
    Invoke-HarnessStepSkip -StepNumber "01" -StepName "typecheck" -Reason "no package.json (template state)"
  } else {
    $typecheck = Get-HarnessScriptCommand -ScriptName "typecheck" -OverrideEnvName "HARNESS_TYPECHECK_CMD"
    if ([string]::IsNullOrWhiteSpace($typecheck)) {
      Invoke-HarnessStepSkip -StepNumber "01" -StepName "typecheck" -Reason "no typecheck script"
    } else {
      Invoke-HarnessStep -StepNumber "01" -StepName "typecheck" -Command $typecheck
    }
  }

  if (-not $hasPackageJson) {
    Invoke-HarnessStepSkip -StepNumber "02" -StepName "lint" -Reason "no package.json (template state)"
  } else {
    $lint = Get-HarnessScriptCommand -ScriptName "lint" -OverrideEnvName "HARNESS_LINT_CMD"
    if ([string]::IsNullOrWhiteSpace($lint)) {
      Invoke-HarnessStepSkip -StepNumber "02" -StepName "lint" -Reason "no lint script"
    } else {
      Invoke-HarnessStep -StepNumber "02" -StepName "lint" -Command $lint
    }
  }

  if (-not $hasPackageJson) {
    Invoke-HarnessStepSkip -StepNumber "03" -StepName "related-tests" -Reason "no package.json (template state)"
  } elseif ([string]::IsNullOrWhiteSpace($baseRef)) {
    Invoke-HarnessStepSkip -StepNumber "03" -StepName "related-tests" -Reason "no base ref found (develop/main)"
  } else {
    $changed = @(& git diff --name-only $baseRef -- "*.ts" "*.tsx" "*.js" "*.jsx" 2>$null)
    if ($changed.Count -eq 0) {
      Invoke-HarnessStepSkip -StepNumber "03" -StepName "related-tests" -Reason "no changed source files vs $baseRef"
    } else {
      $related = Get-HarnessRelatedTestCommand -BaseRef $baseRef
      if ([string]::IsNullOrWhiteSpace($related)) {
        throw "Story-level validation requires vitest/jest or HARNESS_RELATED_TEST_CMD. Full-suite fallback is intentionally disabled."
      }
      Invoke-HarnessStep -StepNumber "03" -StepName "related-tests" -Command $related
    }
  }

  $exitCode = Complete-HarnessValidation
  exit $exitCode
} catch {
  if ([string]::IsNullOrWhiteSpace($script:ValidateFailedStep)) {
    $script:ValidateFailedStep = "validate-quick"
    $script:ValidateFailedCode = 1
    Write-Error $_
  }
  Complete-HarnessValidation | Out-Null
  exit 1
}

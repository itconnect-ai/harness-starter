Set-StrictMode -Version Latest

function Test-HarnessPackageJson {
  return (Test-Path -LiteralPath "package.json" -PathType Leaf)
}

function Get-HarnessPackageJson {
  if (-not (Test-HarnessPackageJson)) {
    return $null
  }

  try {
    return Get-Content -LiteralPath "package.json" -Raw | ConvertFrom-Json
  } catch {
    throw "package.json을 읽거나 파싱하지 못했습니다: $($_.Exception.Message)"
  }
}

function Get-HarnessPackageManager {
  if (Test-Path -LiteralPath "pnpm-lock.yaml" -PathType Leaf) { return "pnpm" }
  if (Test-Path -LiteralPath "yarn.lock" -PathType Leaf) { return "yarn" }
  if ((Test-Path -LiteralPath "bun.lockb" -PathType Leaf) -or (Test-Path -LiteralPath "bun.lock" -PathType Leaf)) { return "bun" }
  if (Test-Path -LiteralPath "package-lock.json" -PathType Leaf) { return "npm" }
  return "npm"
}

function Test-HarnessPackageScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $packageJson = Get-HarnessPackageJson
  if ($null -eq $packageJson -or $null -eq $packageJson.scripts) {
    return $false
  }

  return ($packageJson.scripts.PSObject.Properties.Name -contains $Name)
}

function Get-HarnessRunPrefix {
  $manager = Get-HarnessPackageManager
  switch ($manager) {
    "pnpm" { return "pnpm run" }
    "yarn" { return "yarn" }
    "bun" { return "bun run" }
    default { return "npm run" }
  }
}

function Get-HarnessInstallCommand {
  if (-not [string]::IsNullOrWhiteSpace($env:HARNESS_INSTALL_CMD)) {
    return $env:HARNESS_INSTALL_CMD
  }

  switch (Get-HarnessPackageManager) {
    "pnpm" { return "pnpm install --prefer-offline" }
    "yarn" { return "yarn install" }
    "bun" { return "bun install" }
    default { return "npm install --prefer-offline" }
  }
}

function Get-HarnessScriptCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName,
    [string]$OverrideEnvName
  )

  if (-not [string]::IsNullOrWhiteSpace($OverrideEnvName)) {
    $override = [Environment]::GetEnvironmentVariable($OverrideEnvName)
    if (-not [string]::IsNullOrWhiteSpace($override)) {
      return $override
    }
  }

  if (-not (Test-HarnessPackageScript -Name $ScriptName)) {
    return $null
  }

  return "$(Get-HarnessRunPrefix) $ScriptName"
}

function Test-HarnessNodeBin {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $true }

  $windowsBin = Join-Path "node_modules/.bin" "$Name.cmd"
  $unixBin = Join-Path "node_modules/.bin" $Name
  return ((Test-Path -LiteralPath $windowsBin -PathType Leaf) -or (Test-Path -LiteralPath $unixBin -PathType Leaf))
}

function Get-HarnessTestCommand {
  # 우선순위: HARNESS_TEST_CMD > vitest binary > jest binary > npm run test
  # binary 직접 호출이 1순위인 이유: package.json의 "test" 스크립트가
  # "vitest" 단독(인자 없음)이면 watch 모드로 진입해 무한 행 발생.
  # binary 직접 호출은 항상 run-once 모드를 강제한다.
  if (-not [string]::IsNullOrWhiteSpace($env:HARNESS_TEST_CMD)) {
    return $env:HARNESS_TEST_CMD
  }

  if (Test-HarnessNodeBin -Name "vitest") {
    return "npx vitest run"
  }

  if (Test-HarnessNodeBin -Name "jest") {
    return "npx jest --runInBand --ci"
  }

  return Get-HarnessScriptCommand -ScriptName "test" -OverrideEnvName ""
}

function Get-HarnessRegressionTestCommand {
  if (-not [string]::IsNullOrWhiteSpace($env:HARNESS_REGRESSION_TEST_CMD)) {
    return $env:HARNESS_REGRESSION_TEST_CMD
  }

  if (Test-HarnessNodeBin -Name "vitest") {
    return "npx vitest run tests/regression/"
  }

  if (Test-HarnessNodeBin -Name "jest") {
    return "npx jest --runInBand --testPathPattern=tests/regression/"
  }

  return $null
}

function Get-HarnessRelatedTestCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BaseRef,
    [string[]]$ChangedFiles = @()
  )

  if (-not [string]::IsNullOrWhiteSpace($env:HARNESS_RELATED_TEST_CMD)) {
    return $env:HARNESS_RELATED_TEST_CMD
  }

  $changedJoined = ""
  if ($ChangedFiles -and $ChangedFiles.Count -gt 0) {
    $changedJoined = ($ChangedFiles -join " ")
  }

  if (Test-HarnessNodeBin -Name "vitest") {
    if ([string]::IsNullOrWhiteSpace($changedJoined)) {
      return "npx vitest run"
    }
    return "npx vitest related --run --reporter=verbose $changedJoined"
  }

  if (Test-HarnessNodeBin -Name "jest") {
    if ([string]::IsNullOrWhiteSpace($changedJoined)) {
      return "npx jest --runInBand --passWithNoTests"
    }
    return "npx jest --findRelatedTests $changedJoined --passWithNoTests"
  }

  return $null
}

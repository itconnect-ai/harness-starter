Set-StrictMode -Version Latest

function Format-BashArgument {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $escaped = $Value.Replace("'", "'`"`'`"`'")
  return "'" + $escaped + "'"
}

function Convert-WindowsPathToGitBashPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $resolved = (Resolve-Path -LiteralPath $Path).Path
  if ($resolved -match '^([A-Za-z]):\\(.*)$') {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = ($Matches[2] -replace '\\', '/')
    return "/$drive/$rest"
  }

  return ($resolved -replace '\\', '/')
}

function Get-BashFlavor {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BashPath
  )

  $uname = & $BashPath -lc "uname -s" 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($uname)) {
    return "unknown"
  }

  $uname = $uname.Trim()
  if ($uname -match '^Linux$') {
    return "wsl"
  }

  if ($uname -match 'MINGW|MSYS|CYGWIN') {
    return "git-bash"
  }

  return "unknown"
}

function Get-RepoRootForBash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BashPath,
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $bashFlavor = Get-BashFlavor -BashPath $BashPath
  switch ($bashFlavor) {
    "wsl" {
      $repoRootUnix = & $BashPath -lc "wslpath -a $(Format-BashArgument -Value $RepoRoot)" 2>$null
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($repoRootUnix)) {
        return $repoRootUnix.Trim()
      }
      throw "WSL bash는 감지됐지만 repo 경로를 변환하지 못했습니다."
    }
    "git-bash" {
      return Convert-WindowsPathToGitBashPath -Path $RepoRoot
    }
    default {
      throw "지원되지 않는 bash 환경입니다. Git Bash 또는 WSL bash를 사용하세요."
    }
  }
}

function Find-GitBashExecutable {
  # Windows에서 Git Bash 경로 후보를 명시적으로 탐색합니다.
  # PATH에 있는 'bash.exe'가 WSL일 수 있으므로 Git Bash를 우선합니다.

  $candidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  )

  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    if (Test-Path $candidate -PathType Leaf) {
      return $candidate
    }
  }

  # PATH에서 bash를 찾되, git-bash 경로인지 확인
  $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
  if ($bashCmd -and $bashCmd.Source -match '\\Git\\(usr\\)?bin\\bash\.exe$') {
    return $bashCmd.Source
  }

  return $null
}

function Invoke-HarnessBashScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName,
    [string[]]$ScriptArguments = @(),
    [switch]$AllowWsl  # 명시 opt-in. 기본은 Git Bash 강제.
  )

  $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

  # Windows에서는 Git Bash를 우선. WSL은 기본 거부.
  # 이유:
  #   1. WSL2는 Windows Docker Desktop과 연동 시 부작용 (docker/for-win#14867)
  #   2. WSL에서 실행 시 Docker가 자동 설치되는 경우 발생
  #   3. 경로 변환(/mnt/c/...) 오버헤드로 느림
  # WSL을 꼭 써야 하면 -AllowWsl 플래그 또는 $env:HAENSS_ALLOW_WSL=1 환경변수.

  $allowWslEnv = $env:HAENSS_ALLOW_WSL -eq "1"
  $allowWsl = $AllowWsl.IsPresent -or $allowWslEnv

  $bashPath = Find-GitBashExecutable

  if (-not $bashPath) {
    if ($allowWsl) {
      # WSL 허용된 경우에만 fallback
      $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
      if ($bashCmd) {
        $bashPath = $bashCmd.Source
      }
    }
  }

  if (-not $bashPath) {
    $msg = @(
      "Git Bash를 찾을 수 없습니다.",
      "",
      "Windows에서는 Git for Windows(Git Bash 포함)를 설치하세요:",
      "  https://git-scm.com/download/win",
      "",
      "WSL을 사용해야 한다면 (권장하지 않음):",
      "  PowerShell:    `$env:HAENSS_ALLOW_WSL='1'; ./scripts/validate.ps1",
      "  영구 설정:     [Environment]::SetEnvironmentVariable('HAENSS_ALLOW_WSL','1','User')",
      "",
      "WSL 거부 이유: Docker Desktop 연동 부작용(docker/for-win#14867),",
      "  경로 변환 오버헤드, 예기치 않은 Docker 자동 설치 이슈."
    ) -join "`n"
    throw $msg
  }

  # Git Bash가 아니면 경고 (WSL opt-in인 경우에만 도달)
  $flavor = Get-BashFlavor -BashPath $bashPath
  if ($flavor -eq "wsl" -and -not $allowWsl) {
    $msg = @(
      "PATH의 'bash'가 WSL로 감지되었지만 HAENSS_ALLOW_WSL=1이 아닙니다.",
      "Git Bash를 설치하거나 opt-in 하세요 (위 안내 참조)."
    ) -join "`n"
    throw $msg
  }

  if ($flavor -eq "wsl") {
    Write-Warning "WSL bash를 사용 중 (HAENSS_ALLOW_WSL=1). Docker 연동 이슈 가능."
  }

  $repoRootForBash = Get-RepoRootForBash -BashPath $bashPath -RepoRoot $repoRoot
  $escapedArgs = @($ScriptArguments | ForEach-Object { Format-BashArgument -Value $_ })

  $bashCommand = "cd $(Format-BashArgument -Value $repoRootForBash) && ./scripts/$ScriptName"
  if ($escapedArgs.Count -gt 0) {
    $bashCommand += " " + ($escapedArgs -join " ")
  }

  & $bashPath -lc $bashCommand
  exit $LASTEXITCODE
}

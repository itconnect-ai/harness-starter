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

function Invoke-HarnessBashScript {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName,
    [string[]]$ScriptArguments = @()
  )

  $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  $bash = Get-Command bash -ErrorAction SilentlyContinue

  if (-not $bash) {
    throw "bash를 찾을 수 없습니다. Windows에서는 WSL 또는 Git Bash를 설치한 뒤 다시 실행하세요."
  }

  $repoRootForBash = Get-RepoRootForBash -BashPath $bash.Source -RepoRoot $repoRoot
  $escapedArgs = @($ScriptArguments | ForEach-Object { Format-BashArgument -Value $_ })

  $bashCommand = "cd $(Format-BashArgument -Value $repoRootForBash) && ./scripts/$ScriptName"
  if ($escapedArgs.Count -gt 0) {
    $bashCommand += " " + ($escapedArgs -join " ")
  }

  & $bash.Source -lc $bashCommand
  exit $LASTEXITCODE
}

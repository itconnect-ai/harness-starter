param(
  [switch]$Strict
)

$ErrorActionPreference = "Continue"

. (Join-Path $PSScriptRoot "lib/git-utils.ps1")

Repair-HarnessWindowsEnvironment

$failures = 0

function Write-Check {
  param(
    [string]$Name,
    [bool]$Ok,
    [string]$Detail
  )

  if ($Ok) {
    Write-Host ("[OK]   {0,-28} {1}" -f $Name, $Detail)
  } else {
    Write-Host ("[WARN] {0,-28} {1}" -f $Name, $Detail) -ForegroundColor Yellow
    $script:failures += 1
  }
}

function Format-SafeUrl {
  param(
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
  return ($Value -replace '(https://)([^/@\s]+)@', '$1***@')
}

Write-Host "======================================"
Write-Host " Harness Doctor (Windows/Codex)"
Write-Host "======================================"
Write-Host "Note: doctor warnings are diagnostics. Phase A is blocked only when the"
Write-Host "project validate entrypoint fails, for example ./scripts/validate-quick.ps1."
Write-Host "Raw node/npm/npx/bun failures outside harness entrypoints are not validation gates."
Write-Host ""

Write-Check "PowerShell" ($PSVersionTable.PSVersion.Major -ge 7) "version $($PSVersionTable.PSVersion)"
Write-Check "Operating system" $IsWindows $(if ($IsWindows) { "Windows" } else { "non-Windows" })

foreach ($name in @("SystemRoot", "WINDIR", "ComSpec", "APPDATA", "LOCALAPPDATA")) {
  $value = [Environment]::GetEnvironmentVariable($name)
  Write-Check "env:$name" (-not [string]::IsNullOrWhiteSpace($value)) $(if ($value) { $value } else { "missing" })
}

$git = Get-Command git -ErrorAction SilentlyContinue
Write-Check "git" ($null -ne $git) $(if ($git) { $git.Source } else { "not found" })
if ($git) {
  $version = & git --version 2>&1
  Write-Check "git version" ($LASTEXITCODE -eq 0) ($version -join " ")

  $sslBackend = & git config --global --get http.sslBackend 2>$null
  Write-Check "git ssl backend" $true $(if ($sslBackend) { $sslBackend } else { "default (fallback uses openssl when needed)" })

  $origin = & git remote get-url origin 2>$null
  Write-Check "origin remote" ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($origin)) $(if ($origin) { Format-SafeUrl -Value $origin } else { "not configured" })
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
Write-Check "gh" ($null -ne $gh) $(if ($gh) { $gh.Source } else { "not found" })
if ($gh) {
  try {
    $ghState = Initialize-HarnessGitHubCli -RequireAuth
    Write-Check "gh auth token" $ghState.HasToken "token available via GH_TOKEN or git credential helper"

    if ($git) {
      $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
        $remoteBranch = Test-HarnessGitHubRemoteRef -Ref $branch.Trim()
        Write-Check "gh api current ref" $remoteBranch.Ok $(if ($remoteBranch.Ok) { "$($remoteBranch.RepoSlug)/$($remoteBranch.Ref)" } else { $remoteBranch.Output -join " " })
      }
    }
  } catch {
    Write-Check "gh api current ref" $false $_.Exception.Message
  }
}

$node = Get-Command node -ErrorAction SilentlyContinue
Write-Check "node" ($null -ne $node) $(if ($node) { $node.Source } else { "not found" })
if ($node) {
  $nodeVersion = & node --version 2>&1
  Write-Check "node version" ($LASTEXITCODE -eq 0) ($nodeVersion -join " ")
  $spawn = & node -e "const r=require('node:child_process').spawnSync(process.execPath,['-v'],{stdio:'pipe'}); process.exit(r.status ?? 1)" 2>&1
  Write-Check "node child_process" ($LASTEXITCODE -eq 0) $(if ($LASTEXITCODE -eq 0) { "spawnSync ok" } else { "WARN only unless validate entrypoint fails: " + ($spawn -join " ") })
}

$npm = Get-Command npm -ErrorAction SilentlyContinue
Write-Check "npm" ($null -ne $npm) $(if ($npm) { $npm.Source } else { "not found" })

$bash = Get-Command bash -ErrorAction SilentlyContinue
Write-Check "bash optional" $true $(if ($bash) { $bash.Source } else { "not required for native PowerShell entrypoints" })

Write-Host "======================================"
if ($Strict -and $failures -gt 0) {
  Write-Host "Doctor completed with $failures warning(s). Strict mode fails." -ForegroundColor Yellow
  exit 1
}

Write-Host "Doctor completed with $failures warning(s)."
exit 0

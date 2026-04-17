Set-StrictMode -Version Latest

function Test-HarnessWindows {
  $isWindowsVariable = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
  if ($null -ne $isWindowsVariable) {
    return [bool]$isWindowsVariable.Value
  }

  return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Repair-HarnessWindowsEnvironment {
  if (-not (Test-HarnessWindows)) { return }

  $defaults = @{
    SystemRoot = "C:\WINDOWS"
    WINDIR = "C:\WINDOWS"
    ComSpec = "C:\WINDOWS\System32\cmd.exe"
    SystemDrive = "C:"
    ProgramData = "C:\ProgramData"
    ALLUSERSPROFILE = "C:\ProgramData"
  }

  foreach ($key in $defaults.Keys) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key))) {
      [Environment]::SetEnvironmentVariable($key, $defaults[$key], "Process")
    }
  }

  $userProfile = [Environment]::GetEnvironmentVariable("USERPROFILE")
  if ([string]::IsNullOrWhiteSpace($userProfile)) {
    $homeDrive = [Environment]::GetEnvironmentVariable("HOMEDRIVE")
    $homePath = [Environment]::GetEnvironmentVariable("HOMEPATH")
    if (-not [string]::IsNullOrWhiteSpace($homeDrive) -and -not [string]::IsNullOrWhiteSpace($homePath)) {
      $userProfile = "$homeDrive$homePath"
      [Environment]::SetEnvironmentVariable("USERPROFILE", $userProfile, "Process")
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
      $env:APPDATA = Join-Path $userProfile "AppData\Roaming"
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
      $env:LOCALAPPDATA = Join-Path $userProfile "AppData\Local"
    }
  }
}

function Invoke-HarnessGit {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [switch]$AllowOpenSslFallback
  )

  Repair-HarnessWindowsEnvironment
  $env:GIT_TERMINAL_PROMPT = "0"

  $output = & git @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -eq 0 -or -not $AllowOpenSslFallback) {
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
  }

  $retryOutput = & git -c http.sslBackend=openssl @Arguments 2>&1
  return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $retryOutput }
}

function Get-HarnessOriginUrl {
  $result = Invoke-HarnessGit -Arguments @("remote", "get-url", "origin") -AllowOpenSslFallback
  if ($result.ExitCode -ne 0) {
    throw "origin remote를 찾을 수 없습니다.`n$($result.Output -join "`n")"
  }
  return (($result.Output | Select-Object -First 1) -as [string]).Trim()
}

function Get-HarnessGitHubRepoSlug {
  param(
    [string]$RemoteUrl
  )

  if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
    $RemoteUrl = Get-HarnessOriginUrl
  }

  if ($RemoteUrl -match '^git@github\.com:(?<slug>[^/]+/[^/]+?)(?:\.git)?$') {
    return $Matches["slug"]
  }

  if ($RemoteUrl -match '^ssh://git@github\.com/(?<slug>[^/]+/[^/]+?)(?:\.git)?$') {
    return $Matches["slug"]
  }

  try {
    $uri = [Uri]$RemoteUrl
    if ($uri.Host -ne "github.com") {
      throw "Remote host is '$($uri.Host)', not github.com."
    }

    $slug = $uri.AbsolutePath.Trim("/")
    if ($slug.EndsWith(".git")) {
      $slug = $slug.Substring(0, $slug.Length - 4)
    }
    if ($slug -match '^[^/]+/[^/]+$') {
      return $slug
    }
  } catch {
    # Fall through to the common error below.
  }

  throw "origin remote is not a supported GitHub URL: $RemoteUrl"
}

function Get-HarnessGitHubTokenFromCredential {
  Repair-HarnessWindowsEnvironment
  $previousPrompt = $env:GIT_TERMINAL_PROMPT
  $env:GIT_TERMINAL_PROMPT = "0"

  try {
    $queries = @(
      { "protocol=https`nhost=github.com`n" | git credential-store get 2>$null },
      { "protocol=https`nhost=github.com`n" | git credential fill 2>$null }
    )

    foreach ($query in $queries) {
      $output = & $query
      if ($LASTEXITCODE -ne 0 -or -not $output) {
        continue
      }

      $password = (($output | Where-Object { $_ -like "password=*" } | Select-Object -First 1) -replace '^password=', '')
      if (-not [string]::IsNullOrWhiteSpace($password)) {
        return $password
      }
    }
  } finally {
    if ($null -eq $previousPrompt) {
      Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
    } else {
      $env:GIT_TERMINAL_PROMPT = $previousPrompt
    }
  }

  return $null
}

function Initialize-HarnessGitHubCli {
  param(
    [string]$ConfigDir,
    [switch]$RequireAuth
  )

  Repair-HarnessWindowsEnvironment

  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if (-not $gh) {
    if ($RequireAuth) {
      throw "GitHub CLI (gh) is not installed or not on PATH."
    }
    return [pscustomobject]@{ Ok = $false; GhPath = $null; ConfigDir = $null; HasToken = $false; Message = "gh not found" }
  }

  if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
    $repoRoot = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
      $repoRoot = (Resolve-Path ".").Path
    }
    $ConfigDir = Join-Path ([string]$repoRoot) ".gh-codex"
  }

  New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
  $env:GH_CONFIG_DIR = $ConfigDir

  if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
    $token = Get-HarnessGitHubTokenFromCredential
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $env:GH_TOKEN = $token
    }
  }

  $hasToken = -not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)
  if ($RequireAuth -and -not $hasToken) {
    throw "GitHub token not found. Run 'gh auth login' or provide a GitHub PAT."
  }

  return [pscustomobject]@{ Ok = $true; GhPath = $gh.Source; ConfigDir = $ConfigDir; HasToken = $hasToken; Message = "gh ready" }
}

function Test-HarnessGitHubRemoteRef {
  param(
    [string]$Ref = "develop"
  )

  try {
    $repoSlug = Get-HarnessGitHubRepoSlug
    Initialize-HarnessGitHubCli -RequireAuth | Out-Null
    $remoteRef = & gh api "repos/$repoSlug/git/ref/heads/$Ref" --jq ".ref" 2>&1
    $exitCode = $LASTEXITCODE
    $expected = "refs/heads/$Ref"

    return [pscustomobject]@{
      Ok       = ($exitCode -eq 0 -and $remoteRef -eq $expected)
      RepoSlug = $repoSlug
      Ref      = $remoteRef
      Output   = $remoteRef
      ExitCode = $exitCode
    }
  } catch {
    return [pscustomobject]@{
      Ok       = $false
      RepoSlug = $null
      Ref      = $null
      Output   = $_.Exception.Message
      ExitCode = 1
    }
  }
}

function Get-HarnessCredentialStoreUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteUrl
  )

  if ($RemoteUrl -notmatch '^https://([^/]+)/(.+?)(\.git)?$') {
    return $null
  }

  $hostName = $Matches[1]
  $path = $Matches[2] -replace '\.git$', ''
  $query = "protocol=https`nhost=$hostName`npath=$path`n"
  $cred = $query | git credential-store get
  if ($LASTEXITCODE -ne 0 -or $null -eq $cred) {
    $query = "protocol=https`nhost=$hostName`n"
    $cred = $query | git credential-store get
  }

  $user = (($cred | Where-Object { $_ -like "username=*" }) -replace "^username=", "")
  $pass = (($cred | Where-Object { $_ -like "password=*" }) -replace "^password=", "")
  if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) {
    return $null
  }

  $escapedUser = [uri]::EscapeDataString($user)
  $escapedPass = [uri]::EscapeDataString($pass)
  return [pscustomobject]@{
    Url = "https://$escapedUser`:$escapedPass@$hostName/$path.git"
    Secret = $pass
  }
}

function Redact-HarnessOutput {
  param(
    [object[]]$Output,
    [string]$Secret
  )

  if ([string]::IsNullOrWhiteSpace($Secret)) {
    return $Output
  }

  $escaped = [regex]::Escape($Secret)
  return $Output | ForEach-Object { (($_ -as [string]) -replace $escaped, "***REDACTED***") }
}

function Invoke-HarnessGitFetch {
  param(
    [string]$Ref = "develop"
  )

  $result = Invoke-HarnessGit -Arguments @("fetch", "origin", $Ref) -AllowOpenSslFallback
  if ($result.ExitCode -eq 0) { return $result }

  $remote = Get-HarnessOriginUrl
  $credential = Get-HarnessCredentialStoreUrl -RemoteUrl $remote
  if ($null -eq $credential) { return $result }

  $output = & git -c http.sslBackend=openssl -c credential.helper= -c credential.https://github.com.helper= fetch $credential.Url $Ref 2>&1
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = (Redact-HarnessOutput -Output $output -Secret $credential.Secret)
  }
}

function Invoke-HarnessGitPush {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Branch
  )

  $result = Invoke-HarnessGit -Arguments @("push", "-u", "origin", $Branch) -AllowOpenSslFallback
  if ($result.ExitCode -eq 0) { return $result }

  $remote = Get-HarnessOriginUrl
  $credential = Get-HarnessCredentialStoreUrl -RemoteUrl $remote
  if ($null -eq $credential) { return $result }

  $output = & git -c http.sslBackend=openssl -c credential.helper= -c credential.https://github.com.helper= push $credential.Url "HEAD:refs/heads/$Branch" 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -eq 0) {
    $fetchOutput = & git -c http.sslBackend=openssl -c credential.helper= -c credential.https://github.com.helper= fetch $credential.Url "$Branch`:refs/remotes/origin/$Branch" 2>&1
    $output += $fetchOutput
    if ($LASTEXITCODE -eq 0) {
      $upstreamOutput = & git branch --set-upstream-to="origin/$Branch" $Branch 2>&1
      $output += $upstreamOutput
    }
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = (Redact-HarnessOutput -Output $output -Secret $credential.Secret)
  }
}

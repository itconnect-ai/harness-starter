Set-StrictMode -Version Latest

function Repair-HarnessWindowsEnvironment {
  if (-not $IsWindows) { return }

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

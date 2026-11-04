#Requires -Version 5.1
<#
One-shot Windows setup for auto-yt-dlp: Python, ffmpeg (both via winget when
missing), the app's venv + yt-dlp.exe, the `aytdlp` command, and the tray
icon. Counterpart of install.sh (macOS). Safe to re-run: finished steps are
skipped, the rest is refreshed (e.g. after pulling updates or moving the repo).

  powershell -ExecutionPolicy Bypass -File install.ps1 [-NoTray] [-NoStart]
  (or double-click install.cmd)

  -NoTray    skip the tray icon and its Start Menu shortcut
  -NoStart   don't start the server when done
#>
[CmdletBinding()]
param(
    [switch]$NoTray,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$RepoDir = $PSScriptRoot
$Scripts = Join-Path $RepoDir 'scripts'
$AytdlpPs1 = Join-Path $Scripts 'aytdlp.ps1'
$TrayPs1 = Join-Path $Scripts 'tray\aytdlp-tray.ps1'
$StateDir = Join-Path $env:LOCALAPPDATA 'aytdlp'
$PowerShell = Join-Path $PSHOME 'powershell.exe'

function Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "  + $msg" -ForegroundColor Green }
function Note($msg) { Write-Host "  - $msg" }
function Die($msg)  { Write-Host "  ! $msg" -ForegroundColor Red; exit 1 }
filter Indent       { "    $_" }

if ($env:OS -ne 'Windows_NT') { Die 'install.ps1 is Windows-only; use install.sh on macOS or see "Manual setup" in README.md' }

# Run a program with no console window; returns its exit code and stdout.
function Invoke-Quiet([string]$File, [string]$Arguments) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $File
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return @{ Code = 127; Out = '' } }
    $out = $p.StandardOutput.ReadToEnd()
    $null = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Out = $out }
}

# Pick up PATH entries that winget just added, without opening a new terminal.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user;$env:Path"
}

function Test-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Test-ServerRunning {
    return ((& $AytdlpPs1 status --json) -like '*"running":true*')
}

$StoppedServer = $false
function Stop-ServerForUpdate([string]$Why) {
    if (-not (Test-ServerRunning)) { return }
    Note "stopping the running server to $Why"
    & $AytdlpPs1 stop | Out-Null
    $script:StoppedServer = $true
}

# A terminal opened before an earlier run (or before winget installed
# something) still has the old PATH; look at what's actually registered.
Update-SessionPath

# ---------------------------------------------------------------------------
Step 'Python 3.10+'

# The pinned requirements (click 8.3) need 3.10+. The Microsoft Store's
# python.exe placeholder fails this probe, so it's skipped like any other
# unusable candidate.
$VersionProbe = '-c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)"'

function Find-Python {
    $candidates = New-Object System.Collections.ArrayList
    [void]$candidates.Add(@{ File = 'py'; Prefix = '-3 ' })
    $found = Invoke-Quiet 'where.exe' 'python python3'
    foreach ($line in ($found.Out -split "`r?`n")) {
        $line = $line.Trim()
        if ($line) { [void]$candidates.Add(@{ File = $line; Prefix = '' }) }
    }
    foreach ($c in $candidates) {
        if ((Invoke-Quiet $c.File ($c.Prefix + $VersionProbe)).Code -ne 0) { continue }
        $exe = (Invoke-Quiet $c.File ($c.Prefix + '-c "import sys; print(sys.executable)"')).Out.Trim()
        if ($exe -and (Test-Path $exe)) { return $exe }
    }
    return $null
}

$PythonExe = Find-Python
if (-not $PythonExe) {
    if (-not (Test-Winget)) {
        Die 'Python 3.10+ not found and winget is unavailable; install Python from https://www.python.org/downloads/windows/ and re-run'
    }
    Note 'Python 3.10+ not found; installing it with winget'
    & winget install -e --id Python.Python.3.13 --accept-package-agreements --accept-source-agreements
    Update-SessionPath
    $PythonExe = Find-Python
    if (-not $PythonExe) { Die 'no usable Python 3.10+ after the winget install; open a new terminal and re-run' }
    Ok 'installed Python'
}
Ok "$((Invoke-Quiet $PythonExe '--version').Out.Trim()) at $PythonExe"

# ---------------------------------------------------------------------------
Step 'ffmpeg'

if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Ok "found $((Get-Command ffmpeg).Source)"
} else {
    if (-not (Test-Winget)) {
        Die 'ffmpeg not found and winget is unavailable; install it from https://www.gyan.dev/ffmpeg/builds/ (add its bin folder to PATH) and re-run'
    }
    Note 'ffmpeg not found; installing it with winget'
    & winget install -e --id Gyan.FFmpeg --accept-package-agreements --accept-source-agreements
    Update-SessionPath
    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Die 'ffmpeg still not on PATH after the winget install; open a new terminal and re-run' }
    Ok 'installed ffmpeg'
}

# ---------------------------------------------------------------------------
Step 'App environment'

$Venv = Join-Path $RepoDir 'venv'
$VenvPython = Join-Path $Venv 'Scripts\python.exe'
# Rebuild the venv if it's broken (its Python was removed, the repo moved) or
# was made from a Python older than 3.10.
if ((Test-Path $VenvPython) -and ((Invoke-Quiet $VenvPython $VersionProbe).Code -eq 0)) {
    Ok 'reusing venv'
} else {
    Stop-ServerForUpdate 'rebuild its venv'   # Windows won't delete a running pythonw.exe
    if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }
    & $PythonExe -m venv $Venv
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $VenvPython)) { Die 'could not create the venv' }
    Ok 'created venv'
}

function Install-Requirements {
    & $VenvPython -m pip install -q --disable-pip-version-check -r (Join-Path $RepoDir 'requirements.txt')
    return ($LASTEXITCODE -eq 0)
}
if (-not (Install-Requirements)) {
    # Windows locks the .pyd files a running server has loaded, so an upgrade
    # of a pinned package needs the server out of the way.
    if (-not (Test-ServerRunning)) { Die 'pip install failed' }
    Stop-ServerForUpdate 'update its packages'
    if (-not (Install-Requirements)) { Die 'pip install failed' }
}
Ok 'installed Python packages'

$YtDlpExe = Join-Path $RepoDir 'bin\yt-dlp.exe'
try {
    & (Join-Path $Scripts 'update_ytdlp.ps1') | Indent
    Ok 'yt-dlp ready'
} catch {
    if (Test-Path $YtDlpExe) {
        Note "couldn't check for a newer yt-dlp; keeping the current one"
    } else {
        Die "couldn't download yt-dlp ($($_.Exception.Message)); check your network and re-run"
    }
}

# ---------------------------------------------------------------------------
Step 'aytdlp command'

$ShimDir = Join-Path $StateDir 'bin'
New-Item -ItemType Directory -Force -Path $ShimDir | Out-Null
$Shim = Join-Path $ShimDir 'aytdlp.cmd'
@"
@echo off
"$PowerShell" -NoProfile -ExecutionPolicy Bypass -File "$AytdlpPs1" %*
exit /b %ERRORLEVEL%
"@ | Set-Content -Path $Shim -Encoding ascii
Ok "wrote $Shim -> $AytdlpPs1"

# Add a folder to the user PATH in the registry, keeping any %VAR% entries
# unexpanded, and tell Explorer / new terminals about it. Returns $true if added.
function Add-UserPath([string]$Dir) {
    $raw = [string](Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $entries = @($raw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $expanded = @($entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
    if ($expanded -contains $Dir.TrimEnd('\')) { return $false }
    Set-ItemProperty -Path 'HKCU:\Environment' -Name Path -Value (($entries + $Dir) -join ';') -Type ExpandString
    Add-Type -Namespace AytdlpInstall -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $result = [UIntPtr]::Zero
    # HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG
    [AytdlpInstall.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null
    return $true
}

if (Add-UserPath $ShimDir) {
    Note "added $ShimDir to your PATH; open a new terminal to use ``aytdlp``"
} else {
    Ok "$ShimDir is on PATH"
}
if (-not (($env:Path -split ';') -contains $ShimDir)) { $env:Path = "$env:Path;$ShimDir" }

# ---------------------------------------------------------------------------
if (-not $NoTray) {
    Step 'Tray icon'

    & $TrayPs1 -WriteIcon (Join-Path $StateDir 'aytdlp.ico')
    $StartMenuLink = Join-Path ([Environment]::GetFolderPath('Programs')) 'auto-yt-dlp.lnk'
    & $TrayPs1 -WriteShortcut $StartMenuLink
    Ok 'added "auto-yt-dlp" to the Start Menu'
    # Keep an existing "Start with Windows" entry pointing at this checkout.
    $StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'auto-yt-dlp.lnk'
    if (Test-Path $StartupLink) {
        & $TrayPs1 -WriteShortcut $StartupLink
        Ok 'refreshed the Startup shortcut'
    }

    # Relaunch a running tray so it picks up this version of the scripts.
    $running = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*aytdlp-tray.ps1*' })
    foreach ($p in $running) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue
    }
    Start-Process -FilePath $PowerShell -WindowStyle Hidden `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TrayPs1`""
    if ($running.Count -gt 0) { Ok 'restarted the tray icon' } else { Ok 'launched the tray icon' }
}

# ---------------------------------------------------------------------------
if (-not $NoStart) {
    Step 'Server'
    if (Test-ServerRunning) {
        Note 'already running; run `aytdlp restart` to load updated code'
    } else {
        & $AytdlpPs1 start | Indent
        if ($LASTEXITCODE -ne 0) { Note 'server didn''t start; see `aytdlp logs`' }
    }
} elseif ($StoppedServer) {
    Step 'Server'
    Note 'the server was stopped during setup; run `aytdlp start` to bring it back'
}

# ---------------------------------------------------------------------------
Step 'Done'
Write-Host @"
  aytdlp open                     open the web UI (starts the server if needed)
  aytdlp start | stop | restart   control the background server
  aytdlp status | logs            check on it
"@
if (-not $NoTray) {
    Write-Host '  Tray: click the circle-arrow icon by the clock (it may sit behind the ^ overflow)'
    Write-Host '  for Start / Stop / Open in Browser. "Start with Windows" keeps it after a reboot.'
}

#Requires -Version 5.1
# aytdlp (Windows) - start/stop the auto-yt-dlp Flask app as a detached
# background server. Counterpart of scripts/aytdlp (macOS). State lives in
# %LOCALAPPDATA%\aytdlp\ (run.pid, port, log); install.ps1 puts an `aytdlp`
# shim on PATH that runs this script.
#
#   aytdlp {start|stop|restart|status [--json]|open|logs [n]}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoDir = Split-Path -Parent $PSScriptRoot
$Pythonw = Join-Path $RepoDir 'venv\Scripts\pythonw.exe'
$App = Join-Path $RepoDir 'app.py'

$StateDir = Join-Path $env:LOCALAPPDATA 'aytdlp'
$PidFile = Join-Path $StateDir 'run.pid'
$PortFile = Join-Path $StateDir 'port'
$LogFile = Join-Path $StateDir 'log'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

# 0.0.0.0 binds every interface (LAN / Tailscale) but isn't browsable as a host;
# default to loopback and map 0.0.0.0 -> localhost for URLs.
$BindHost = if ($env:AYTDLP_HOST) { $env:AYTDLP_HOST } else { '127.0.0.1' }
$Port = if ($env:AYTDLP_PORT) { [int]$env:AYTDLP_PORT } else { 5000 }
$UrlHost = if ($BindHost -eq '0.0.0.0') { 'localhost' } else { $BindHost }

function Write-Err([string]$Message) { [Console]::Error.WriteLine($Message) }

function Get-ServerProcess {
    # The pid file alone isn't proof: Windows reuses pids quickly, so also
    # check that the pid still belongs to a python process.
    if (-not (Test-Path $PidFile)) { return $null }
    $id = (Get-Content $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1) -as [int]
    if (-not $id) { return $null }
    $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -like 'python*') { return $proc }
    return $null
}

function Read-Port {
    $saved = (Get-Content $PortFile -ErrorAction SilentlyContinue | Select-Object -First 1) -as [int]
    if ($saved) { return $saved }
    return $Port
}

function Invoke-Start {
    $proc = Get-ServerProcess
    if ($proc) {
        Write-Output "already running on :$(Read-Port) (pid $($proc.Id))"
        return
    }
    if (-not (Test-Path $Pythonw)) {
        Write-Err "venv python missing: $Pythonw"
        Write-Err 'create it first:  python -m venv venv; venv\Scripts\pip install -r requirements.txt  (or run install.ps1)'
        exit 1
    }
    Set-Content -Path $LogFile -Value '' -NoNewline

    # pythonw has no console, so nothing pops up and closing the terminal that
    # ran `aytdlp start` leaves the server alone; app.py sends its output to
    # YTDLP_WEB_LOG instead. -PassThru returns the real python process, so
    # stop kills the server itself rather than a wrapper.
    $env:YTDLP_WEB_HOST = $BindHost
    $env:YTDLP_WEB_PORT = "$Port"
    $env:YTDLP_WEB_DEBUG = '0'
    $env:YTDLP_WEB_LOG = $LogFile
    $proc = Start-Process -FilePath $Pythonw -ArgumentList "`"$App`"" -WorkingDirectory $RepoDir -PassThru
    Set-Content -Path $PidFile -Value $proc.Id
    Set-Content -Path $PortFile -Value $Port

    $url = "http://${UrlHost}:$Port"
    for ($i = 0; $i -lt 120; $i++) {
        try {
            Invoke-WebRequest -Uri "$url/api/health" -UseBasicParsing -TimeoutSec 2 | Out-Null
            Write-Output "started on $url (pid $($proc.Id))"
            return
        } catch { }
        if ($proc.HasExited) {
            Write-Err 'failed to start - last log lines:'
            Get-Content $LogFile -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Err $_ }
            Remove-Item $PidFile -ErrorAction SilentlyContinue
            exit 1
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Err "started (pid $($proc.Id)) but health check timed out - see $LogFile"
}

function Invoke-Stop {
    $proc = Get-ServerProcess
    if (-not $proc) {
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        Write-Output 'not running'
        return
    }
    # /T also takes down any yt-dlp / ffmpeg a download left running. Routed
    # through cmd so taskkill's chatter never lands in PowerShell's error stream.
    & cmd.exe /c "taskkill /PID $($proc.Id) /T /F >nul 2>&1"
    for ($i = 0; $i -lt 25; $i++) {
        if ($proc.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $PidFile -ErrorAction SilentlyContinue
    Write-Output 'stopped'
}

function Invoke-Status([bool]$AsJson) {
    $proc = Get-ServerProcess
    if ($proc) {
        $port = Read-Port
        $url = "http://${UrlHost}:$port"
        if ($AsJson) { Write-Output ('{{"running":true,"pid":{0},"port":{1},"url":"{2}"}}' -f $proc.Id, $port, $url) }
        else { Write-Output "running on $url (pid $($proc.Id))" }
    } else {
        if ($AsJson) { Write-Output '{"running":false}' } else { Write-Output 'not running' }
    }
}

function Invoke-Open {
    if (-not (Get-ServerProcess)) { Invoke-Start }
    Start-Process "http://${UrlHost}:$(Read-Port)"
}

function Invoke-Logs([int]$Lines) {
    if (Test-Path $LogFile) { Get-Content $LogFile -Tail $Lines } else { Write-Output 'no log yet' }
}

$command = if ($args.Count -gt 0) { [string]$args[0] } else { 'status' }
$option = if ($args.Count -gt 1) { [string]$args[1] } else { '' }
switch ($command) {
    'start'   { Invoke-Start }
    'stop'    { Invoke-Stop }
    'restart' { Invoke-Stop; Invoke-Start }
    'status'  { Invoke-Status ($option -eq '--json') }
    'open'    { Invoke-Open }
    'logs'    { Invoke-Logs $(if ($option) { [int]$option } else { 40 }) }
    default   { Write-Err 'usage: aytdlp {start|stop|restart|status [--json]|open|logs [n]}'; exit 1 }
}

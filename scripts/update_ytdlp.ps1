#Requires -Version 5.1
# Windows counterpart of update_ytdlp.sh: fetches the latest yt-dlp release
# into bin\yt-dlp.exe (skipped when the recorded version already matches).
# app.py runs this on every launch; install.ps1 runs it once during setup.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest crawl
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$BinDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin'
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
$Exe = Join-Path $BinDir 'yt-dlp.exe'
$VersionFile = Join-Path $BinDir '.ytdlp_version'
$ApiUrl = 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'

# 32-bit Windows gets the x86 build; x64 and ARM64 (via emulation) use yt-dlp.exe.
$Is32Bit = ($env:PROCESSOR_ARCHITECTURE -eq 'x86') -and (-not $env:PROCESSOR_ARCHITEW6432)
$AssetName = if ($Is32Bit) { 'yt-dlp_x86.exe' } else { 'yt-dlp.exe' }

Write-Output 'Fetching latest yt-dlp release info...'
$LatestTag = (Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing).tag_name
if (-not $LatestTag) { throw 'could not read the latest release tag from GitHub' }

if ((Test-Path $VersionFile) -and (Test-Path $Exe)) {
    $Current = Get-Content $VersionFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Current -eq $LatestTag) {
        Write-Output "yt-dlp is already up to date ($Current)"
        exit 0
    }
}

$DownloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/download/$LatestTag/$AssetName"
Write-Output "Downloading yt-dlp $LatestTag ($AssetName)..."
# Download beside the target and swap it in, so an interrupted download never
# leaves a half-written yt-dlp.exe behind.
$Tmp = "$Exe.download"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $Tmp -UseBasicParsing
Move-Item -Force -Path $Tmp -Destination $Exe

Set-Content -Path $VersionFile -Value $LatestTag -Encoding ascii
Write-Output "yt-dlp $LatestTag installed to $Exe"
& $Exe --version

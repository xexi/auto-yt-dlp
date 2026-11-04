#Requires -Version 5.1
# auto-yt-dlp tray icon (Windows) - counterpart of the SwiftBar menubar plugin.
# Shows whether the server is running and offers Start / Stop / Restart /
# Open in Browser, all routed through scripts\aytdlp.ps1. install.ps1 adds a
# Start Menu shortcut that launches this hidden; the menu's "Start with
# Windows" item puts the same shortcut in the Startup folder.
#
#   aytdlp-tray.ps1                        run the tray icon (one instance at a time)
#   aytdlp-tray.ps1 -WriteIcon <file.ico>  write the app icon used by shortcuts, then exit
#   aytdlp-tray.ps1 -WriteShortcut <.lnk>  write a shortcut that launches the tray, then exit

param(
    [string]$WriteIcon,
    [string]$WriteShortcut
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptPath = $MyInvocation.MyCommand.Path
$Aytdlp = Join-Path (Split-Path -Parent $PSScriptRoot) 'aytdlp.ps1'
$StateDir = Join-Path $env:LOCALAPPDATA 'aytdlp'
$IcoFile = Join-Path $StateDir 'aytdlp.ico'
$PowerShell = Join-Path $PSHOME 'powershell.exe'
$StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'auto-yt-dlp.lnk'

# --- icon ---------------------------------------------------------------------
# A circle with a down arrow: grey outline while idle, filled blue when the
# server is running. Drawn at runtime so there's no image file to ship.
function New-IconBitmap([int]$Size, [bool]$Running) {
    $bmp = [System.Drawing.Bitmap]::new($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $blue = [System.Drawing.Color]::FromArgb(47, 128, 237)
    $grey = [System.Drawing.Color]::FromArgb(138, 143, 152)
    $stroke = [single][Math]::Max(1.5, $Size * 0.1)
    $pad = [single]($Size * 0.04)

    if ($Running) {
        $brush = [System.Drawing.SolidBrush]::new($blue)
        $g.FillEllipse($brush, $pad, $pad, [single]($Size - 2 * $pad), [single]($Size - 2 * $pad))
        $arrowColor = [System.Drawing.Color]::White
    } else {
        $ring = [System.Drawing.Pen]::new($grey, $stroke)
        $inset = [single]($pad + $stroke / 2)
        $g.DrawEllipse($ring, $inset, $inset, [single]($Size - 2 * $inset), [single]($Size - 2 * $inset))
        $arrowColor = $grey
    }

    $pen = [System.Drawing.Pen]::new($arrowColor, $stroke)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $cx = [single]($Size / 2)
    $top = [single]($Size * 0.27)
    $bottom = [single]($Size * 0.70)
    $wing = [single]($Size * 0.19)
    $g.DrawLine($pen, $cx, $top, $cx, $bottom)
    $g.DrawLines($pen, [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($cx - $wing, $bottom - $wing),
        [System.Drawing.PointF]::new($cx, $bottom),
        [System.Drawing.PointF]::new($cx + $wing, $bottom - $wing)
    ))
    $g.Dispose()
    return $bmp
}

function New-TrayIcon([bool]$Running, [int]$Size) {
    $bmp = New-IconBitmap $Size $Running
    # FromHandle doesn't own the HICON; both icons live for the whole run, so
    # the handle is simply never freed.
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Write-IcoFile([string]$Path) {
    # Classic .ico: one 32-bit BGRA bitmap per size (plus an empty AND mask,
    # since the alpha channel does the masking). Explorer picks the closest.
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $images = foreach ($size in $sizes) {
        $bmp = New-IconBitmap $size $true
        $rect = [System.Drawing.Rectangle]::new(0, 0, $size, $size)
        $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $pixels = [byte[]]::new($data.Stride * $size)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
        $bmp.UnlockBits($data)
        $maskRow = [int](($size + 31) / 32) * 4
        $ms = [System.IO.MemoryStream]::new()
        $w = [System.IO.BinaryWriter]::new($ms)
        # BITMAPINFOHEADER; height counts the XOR and AND bitmaps together.
        $w.Write([uint32]40); $w.Write([int32]$size); $w.Write([int32]($size * 2))
        $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
        $w.Write([uint32]($size * $size * 4 + $maskRow * $size))
        $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
        for ($y = $size - 1; $y -ge 0; $y--) { $w.Write($pixels, $y * $data.Stride, $size * 4) }   # rows bottom-up
        $w.Write([byte[]]::new($maskRow * $size))
        $w.Flush()
        , $ms.ToArray()
    }
    $writer = [System.IO.BinaryWriter]::new([System.IO.File]::Create($Path))
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)   # ICONDIR: reserved, type (1 = icon), count
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $dim = [byte]($sizes[$i] % 256)                                              # 0 means 256
        $writer.Write($dim); $writer.Write($dim); $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($img in $images) { $writer.Write($img) }
    $writer.Close()
}

function New-TrayShortcut([string]$Path) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = $PowerShell
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    $lnk.WorkingDirectory = Split-Path -Parent $ScriptPath
    $lnk.WindowStyle = 7   # start minimized, so the console is gone before it's ever drawn
    $lnk.Description = 'auto-yt-dlp tray icon'
    if (Test-Path $IcoFile) { $lnk.IconLocation = "$IcoFile,0" }
    $lnk.Save()
}

if ($WriteIcon) {
    $dir = Split-Path -Parent $WriteIcon
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Write-IcoFile $WriteIcon
}
if ($WriteShortcut) {
    $dir = Split-Path -Parent $WriteShortcut
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    New-TrayShortcut $WriteShortcut
}
if ($WriteIcon -or $WriteShortcut) { exit 0 }

# --- one instance at a time -----------------------------------------------------
$mutex = [System.Threading.Mutex]::new($false, 'Local\auto-yt-dlp-tray')
try { $acquired = $mutex.WaitOne(0, $false) }
catch [System.Threading.AbandonedMutexException] { $acquired = $true }   # previous instance was killed; it's ours now
if (-not $acquired) { exit 0 }

# Without this Windows renders the icon at 16px and upscales it (blurry) on HiDPI displays.
Add-Type -Namespace AytdlpTray -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[AytdlpTray.Native]::SetProcessDPIAware() | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

$iconSize = [System.Windows.Forms.SystemInformation]::SmallIconSize.Width
$icons = @{
    on  = New-TrayIcon $true $iconSize
    off = New-TrayIcon $false $iconSize
}

# --- menu -----------------------------------------------------------------------
$notify = [System.Windows.Forms.NotifyIcon]::new()
$menu = [System.Windows.Forms.ContextMenuStrip]::new()
$miStatus = $menu.Items.Add('Checking...')
$miStatus.Enabled = $false
$miOpen = $menu.Items.Add('Open in Browser')
$miStart = $menu.Items.Add('Start')
$miStop = $menu.Items.Add('Stop')
$miRestart = $menu.Items.Add('Restart')
$menu.Items.Add('-') | Out-Null
$miLogin = $menu.Items.Add('Start with Windows')
$menu.Items.Add('-') | Out-Null
$miQuit = $menu.Items.Add('Quit')
$notify.ContextMenuStrip = $menu

$script:pending = $null       # the hidden PowerShell running the last Start/Stop/Restart/Open
$script:pendingVerb = ''

function Get-Status {
    try { return (& $Aytdlp status --json | ConvertFrom-Json) }
    catch { return [pscustomobject]@{ running = $false } }
}

function Update-Ui {
    try {
        $status = Get-Status
        $running = [bool]$status.running
        $notify.Icon = $(if ($running) { $icons.on } else { $icons.off })
        if ($running) {
            $notify.Text = "auto-yt-dlp: running on :$($status.port)"
            $miStatus.Text = "Running on $($status.url)"
        } else {
            $notify.Text = 'auto-yt-dlp: not running'
            $miStatus.Text = 'Not running'
        }
        $miStart.Visible = -not $running
        $miStop.Visible = $running
        $miRestart.Visible = $running
        $miLogin.Checked = Test-Path $StartupLink
    } catch { }
}

function Invoke-Aytdlp([string]$Verb) {
    # Run through a hidden PowerShell so a slow start (health check, yt-dlp
    # update) never freezes the tray; the timer below picks up the result.
    if ($script:pending -and -not $script:pending.HasExited) { return }
    try {
        $script:pendingVerb = $Verb
        $script:pending = Start-Process -FilePath $PowerShell -WindowStyle Hidden -PassThru `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$Aytdlp`" $Verb"
    } catch {
        $notify.ShowBalloonTip(6000, 'auto-yt-dlp', "Couldn't run 'aytdlp ${Verb}': $($_.Exception.Message)", [System.Windows.Forms.ToolTipIcon]::Error)
    }
}

$miOpen.add_Click({ Invoke-Aytdlp 'open' })
$miStart.add_Click({ Invoke-Aytdlp 'start' })
$miStop.add_Click({ Invoke-Aytdlp 'stop' })
$miRestart.add_Click({ Invoke-Aytdlp 'restart' })
$miLogin.add_Click({
    try {
        if (Test-Path $StartupLink) { Remove-Item $StartupLink -Force } else { New-TrayShortcut $StartupLink }
    } catch { }
    $miLogin.Checked = Test-Path $StartupLink
})
$miQuit.add_Click({
    $timer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$menu.add_Opening({ Update-Ui })

# Left-click opens the same menu as right-click (NotifyIcon only wires up the latter).
$showMenu = [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [System.Reflection.BindingFlags]'NonPublic, Instance')
$notify.add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $showMenu.Invoke($notify, $null) }
})

# One tick a second: finish off a pending action promptly, otherwise poll every 10 s.
$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 1000
$script:tick = 0
$timer.add_Tick({
    $script:tick++
    if ($script:pending) {
        if ($script:pending.HasExited) {
            $code = $script:pending.ExitCode
            $verb = $script:pendingVerb
            $script:pending = $null
            Update-Ui
            if ($code -ne 0) {
                $notify.ShowBalloonTip(6000, 'auto-yt-dlp', "'aytdlp $verb' failed - run 'aytdlp logs' in a terminal for details", [System.Windows.Forms.ToolTipIcon]::Error)
            }
        }
    } elseif ($script:tick % 10 -eq 0) {
        Update-Ui
    }
})

Update-Ui
$notify.Visible = $true
$timer.Start()
[System.Windows.Forms.Application]::Run()
$timer.Dispose()
$mutex.ReleaseMutex()

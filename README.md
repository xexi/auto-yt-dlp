# auto-yt-dlp

A simple, self-contained YouTube downloader web app. Paste a link, pick your format, and download — no CLI needed.

Built with Flask and [yt-dlp](https://github.com/yt-dlp/yt-dlp). The app automatically fetches the latest yt-dlp release on every launch so you're always up to date.

## Features

- **Video download** — MP4 with selectable quality (360p to 4K)
- **Audio download** — Extract audio as MP3
- **Subtitles** — Browse manual and auto-generated captions, pick languages, download as SRT files (zipped when several languages are picked) or embedded in video
- **Auto-update** — yt-dlp binary is checked and updated every time the server starts
- **Dark UI** — Clean, minimal interface that works on desktop and mobile

## Quick Start (macOS)

```bash
git clone https://github.com/your-username/auto-yt-dlp.git
cd auto-yt-dlp
./install.sh
```

That one command sets up everything, skipping anything you already have:

1. **Homebrew** — offers to install it if missing
2. **Python 3.10+** and **ffmpeg** (needed for MP3 conversion and merging video+audio) via Homebrew
3. **App environment** — creates `venv/`, installs Python packages, downloads the latest yt-dlp
4. **`aytdlp` command** — linked into `~/bin` (added to your PATH if needed)
5. **Menubar toggle** — installs [SwiftBar](https://swiftbar.app), sets its plugin folder
   (`~/SwiftBarPlugins` unless you already picked one), and adds the auto-yt-dlp plugin
6. **Starts the server** at http://127.0.0.1:5000

Options: `--no-menubar` skips SwiftBar, `--no-start` leaves the server stopped.
Re-run `./install.sh` any time — after `git pull` or moving the repo — to refresh the setup.

## Quick Start (Windows)

Double-click **`install.cmd`** in the cloned folder, or from a terminal:

```powershell
git clone https://github.com/your-username/auto-yt-dlp.git
cd auto-yt-dlp
powershell -ExecutionPolicy Bypass -File install.ps1
```

That one command sets up everything, skipping anything you already have:

1. **Python 3.10+** and **ffmpeg** — installed with [winget](https://learn.microsoft.com/windows/package-manager/winget/)
   if missing (the Microsoft Store's `python.exe` placeholder is ignored)
2. **App environment** — creates `venv\`, installs Python packages, downloads the latest `yt-dlp.exe`
3. **`aytdlp` command** — a shim in `%LOCALAPPDATA%\aytdlp\bin`, added to your user PATH
4. **Tray icon** — adds an **auto-yt-dlp** Start Menu entry and launches the icon
5. **Starts the server** at http://127.0.0.1:5000

Options: `-NoTray` skips the tray icon, `-NoStart` leaves the server stopped.
Re-run the installer any time — after `git pull` or moving the repo — to refresh the setup.
Only Windows PowerShell 5.1 (built into Windows 10/11) is required; no admin rights are needed.

## Manual setup (Linux / anywhere else)

Requires **Python 3.10+** and **ffmpeg** (`sudo apt install ffmpeg`, `winget install Gyan.FFmpeg`).

```bash
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py                   # yt-dlp is downloaded automatically on first launch
```

Open **http://127.0.0.1:5000** in your browser.

## Everyday use (macOS)

The `aytdlp` helper runs the server detached, so no terminal stays pinned open.
Control it from anywhere:

```sh
aytdlp start            # boot the server in the background, wait until it's ready
aytdlp status           # "running on http://127.0.0.1:5000 (pid …)"
aytdlp open             # open the UI in your browser (starts it first if needed)
aytdlp stop
aytdlp restart
aytdlp logs             # tail the server log
```

State (pid, port, log) lives in `~/.aytdlp/`. `aytdlp status --json` powers the menubar.

**Menubar:** the icon flips between idle and running, with Start / Stop / Restart /
Open in Browser actions. Turn on SwiftBar → Preferences → **Launch at Login** to keep
it after a reboot. If `aytdlp` lives somewhere unusual, set `AYTDLP_BIN` to its
absolute path in the plugin's env.

**Port / host:** defaults to `127.0.0.1:5000`. Override per-run with env vars —
`AYTDLP_PORT=5050 aytdlp start`, or `AYTDLP_HOST=0.0.0.0 aytdlp start` to expose it on
the LAN / Tailscale. Note: macOS's AirPlay Receiver also listens on `*:5000`; the
app still works because it binds the more specific `127.0.0.1` (and `aytdlp open`
uses that address), but `localhost:5000` may hit AirPlay instead — use `127.0.0.1`,
pick another port, or turn off AirPlay Receiver in System Settings.

## Everyday use (Windows)

The same `aytdlp` commands work from PowerShell or Command Prompt (open a new
terminal after installing so it's on your PATH):

```powershell
aytdlp start            # boot the server in the background, wait until it's ready
aytdlp status           # "running on http://127.0.0.1:5000 (pid …)"
aytdlp open             # open the UI in your browser (starts it first if needed)
aytdlp stop
aytdlp restart
aytdlp logs             # tail the server log
```

The server runs under `pythonw.exe`, so no console window ever appears and closing
your terminal leaves it alone. State (pid, port, log) lives in `%LOCALAPPDATA%\aytdlp\`.

**Tray icon:** a circle-arrow icon by the clock (Windows may tuck it behind the `^`
overflow — drag it onto the taskbar to keep it visible). It fills in blue while the
server runs; click it for Start / Stop / Restart / Open in Browser. Tick **Start with
Windows** in its menu to keep the icon after a reboot. Launch it again any time from
the Start Menu entry **auto-yt-dlp**.

**Port / host:** `$env:AYTDLP_PORT = 5050; aytdlp start` (PowerShell) or
`set AYTDLP_PORT=5050 && aytdlp start` (cmd). `AYTDLP_HOST=0.0.0.0` exposes it on the
LAN / Tailscale; Windows Firewall will ask once whether to allow `pythonw.exe`.

## How It Works

1. Paste a YouTube URL and click **Fetch**
2. Preview the video — title, thumbnail, channel, duration
3. Choose your format:
   - **MP4 Video** — pick a quality (best, 1080p, 720p, etc.)
   - **MP3 Audio** — extracts and converts audio
   - **Subtitles Only** — downloads caption files (one .srt, or a .zip for several languages)
4. Optionally select subtitle languages to embed or download
5. Click **Download** — the file is saved straight to your browser

## Project Structure

```
auto-yt-dlp/
├── install.sh              # One-shot macOS setup (deps, venv, aytdlp, SwiftBar menubar)
├── install.ps1             # One-shot Windows setup (deps via winget, venv, aytdlp, tray icon)
├── install.cmd             # Double-click wrapper for install.ps1
├── app.py                  # Flask server + yt-dlp integration
├── requirements.txt        # Python dependencies (pinned)
├── templates/
│   └── index.html          # Web UI
├── static/
│   └── style.css           # Styling
├── scripts/
│   ├── update_ytdlp.sh     # Fetches latest yt-dlp binary from GitHub (macOS/Linux)
│   ├── update_ytdlp.ps1    # Same, for Windows (yt-dlp.exe)
│   ├── aytdlp              # start/stop/status control wrapper (macOS/Linux)
│   ├── aytdlp.ps1          # Same, for Windows (pythonw, state in %LOCALAPPDATA%\aytdlp)
│   ├── menubar/
│   │   └── aytdlp.10s.sh   # SwiftBar menubar plugin
│   └── tray/
│       └── aytdlp-tray.ps1 # Windows tray icon (WinForms, no extra dependencies)
├── bin/                    # yt-dlp binary lives here (auto-managed, gitignored)
└── downloads/              # Temp files during download (auto-cleaned, gitignored)
```

## Updating yt-dlp Manually

The app auto-updates on launch, but you can also run:

```bash
./scripts/update_ytdlp.sh                                      # macOS / Linux
powershell -ExecutionPolicy Bypass -File scripts\update_ytdlp.ps1   # Windows
```

## License

MIT

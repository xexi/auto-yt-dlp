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

## Manual setup (Linux / Windows)

Requires **Python 3.10+** and **ffmpeg** (`sudo apt install ffmpeg`, `choco install ffmpeg`).

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
├── app.py                  # Flask server + yt-dlp integration
├── requirements.txt        # Python dependencies (pinned)
├── templates/
│   └── index.html          # Web UI
├── static/
│   └── style.css           # Styling
├── scripts/
│   ├── update_ytdlp.sh     # Fetches latest yt-dlp binary from GitHub
│   ├── aytdlp              # start/stop/status control wrapper (detached server)
│   └── menubar/
│       └── aytdlp.10s.sh   # SwiftBar menubar plugin
├── bin/                    # yt-dlp binary lives here (auto-managed, gitignored)
└── downloads/              # Temp files during download (auto-cleaned, gitignored)
```

## Updating yt-dlp Manually

The app auto-updates on launch, but you can also run:

```bash
./scripts/update_ytdlp.sh
```

## License

MIT

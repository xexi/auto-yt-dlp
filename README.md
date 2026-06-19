# auto-yt-dlp

A simple, self-contained YouTube downloader web app. Paste a link, pick your format, and download — no CLI needed.

Built with Flask and [yt-dlp](https://github.com/yt-dlp/yt-dlp). The app automatically fetches the latest yt-dlp release on every launch so you're always up to date.

## Features

- **Video download** — MP4 with selectable quality (360p to 4K)
- **Audio download** — Extract audio as MP3
- **Subtitles** — Browse manual and auto-generated captions, pick languages, download as separate SRT files or embedded in video
- **Auto-update** — yt-dlp binary is checked and updated every time the server starts
- **Dark UI** — Clean, minimal interface that works on desktop and mobile

## Requirements

- **Python 3.9+**
- **ffmpeg** — needed for MP3 conversion and merging video+audio streams

  ```bash
  # macOS
  brew install ffmpeg

  # Ubuntu / Debian
  sudo apt install ffmpeg

  # Windows (via chocolatey)
  choco install ffmpeg
  ```

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/your-username/auto-yt-dlp.git
cd auto-yt-dlp

# 2. Create a virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt

# 3. Run the app (yt-dlp will be downloaded automatically on first launch)
python app.py
```

Open **http://localhost:5000** in your browser.

## Run it like an app (macOS)

For day-to-day use you don't want a terminal pinned open. The `aytdlp` helper runs
the server detached and gives you a menubar toggle (via [SwiftBar](https://swiftbar.app)).

```sh
# one-time: symlink `aytdlp` into ~/bin and drop the SwiftBar plugin in place
./scripts/install-local.sh
```

Then control it from anywhere:

```sh
aytdlp start            # boot the server in the background, wait until it's ready
aytdlp status           # "running on http://127.0.0.1:5000 (pid …)"
aytdlp open             # open the UI in your browser (starts it first if needed)
aytdlp stop
aytdlp restart
aytdlp logs             # tail the server log
```

State (pid, port, log) lives in `~/.aytdlp/`. `aytdlp status --json` powers the menubar.

**Menubar:** `brew install --cask swiftbar`, launch it, point it at a plugin folder
(e.g. `~/SwiftBarPlugins`). `install-local.sh` copies `scripts/menubar/aytdlp.10s.sh`
there for you — hit SwiftBar → **Refresh All**. The icon flips between idle and
running, with Start / Stop / Restart / Open in Browser actions. If `aytdlp` lives
somewhere unusual, set `AYTDLP_BIN` to its absolute path in the plugin's env.

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
   - **Subtitles Only** — downloads caption files
4. Optionally select subtitle languages to embed or download
5. Click **Download** — the file is saved straight to your browser

## Project Structure

```
auto-yt-dlp/
├── app.py                  # Flask server + yt-dlp integration
├── requirements.txt        # Python dependencies (pinned)
├── templates/
│   └── index.html          # Web UI
├── static/
│   └── style.css           # Styling
├── scripts/
│   ├── update_ytdlp.sh     # Fetches latest yt-dlp binary from GitHub
│   ├── aytdlp              # start/stop/status control wrapper (detached server)
│   ├── install-local.sh    # Links `aytdlp` into ~/bin + installs SwiftBar plugin
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

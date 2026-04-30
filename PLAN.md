# Plan: Hybrid library + Tailscale access

## Goal

Run the app on one host (Mac), access from any device on the tailnet, with files
persisting on the host as a library and opt-in transfer to the requesting device.

## Decisions made

- **No Nuitka / PyInstaller.** Per-OS builds, code-signing, and ffmpeg bundling
  cost more than they're worth for personal use.
- **Hybrid storage model.** Default flow saves to host library (no re-transfer
  over Tailscale). "Download to this device" is an explicit second action.
- **Tailscale handles network/auth.** No HTTPS, no login layer, no port
  forwarding. Just bind Flask to `0.0.0.0`.

## Changes

### 1. Backend (`app.py`)

- Rename `downloads/` -> `library/` (persistent, not per-job temp).
- Drop the per-job `uuid` subdirectory + `cleanup_dir` flow for the default
  download path. Files land directly in `library/` with their real titles.
- Replace `/api/download` response: instead of `send_file`, return JSON
  `{ ok: true, filename: "..." }` once yt-dlp finishes.
- Add `GET /api/library` -> list of `{name, size, mtime, duration?}`.
- Add `GET /files/<name>` -> serve with Range headers (so `<video>` scrubbing
  and "Download to this device" both work). Use `send_from_directory` with
  `conditional=True`.
- Add `DELETE /api/library/<name>` -> remove a file.
- Bind to all interfaces: `app.run(host="0.0.0.0", port=5000)`.
- Bump subprocess timeout 600 -> 1800 for long 4K videos.

### 2. Frontend (`templates/index.html`, `static/`)

- Default button: "Save to library" (was "Download").
- New library panel below the form:
  - List of saved files with thumbnail-less rows (name + size + date).
  - Per-row actions: **Play** (opens `<video>` in modal), **Download to this
    device** (hits `/files/<name>` with `?download=1`), **Delete**.
- Range-aware video element for in-browser playback.

### 3. yt-dlp updater

- Leave `scripts/update_ytdlp.sh` as-is for now. It runs at startup and works.
  Only port to Python if we ever revisit packaging.

### 4. Runtime / ops (optional, do later)

- `pip install waitress`, run via `waitress-serve --host 0.0.0.0 --port 5000 app:app`.
- `caffeinate -i` wrapper or Settings -> Battery -> prevent sleep.
- `launchd` plist for auto-start on login.
- Tailscale MagicDNS so `http://<host>:5000` works without remembering IPs.

## Out of scope

- Authentication (Tailscale ACLs cover this).
- HTTPS (Tailscale tunnel is encrypted).
- Multi-user library separation.
- Cross-OS distribution / compiled binaries.
- ffmpeg bundling (system dependency, warn if missing — already done).

## Open questions

- Library size cap / auto-prune policy? Or unbounded until manual delete?
- Should "Save to library" allow renaming before save, or always use yt-dlp's
  `%(title)s` template?

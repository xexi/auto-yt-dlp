import io
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
import zipfile
from pathlib import Path

from flask import Flask, jsonify, request, send_file, render_template

# Detached launches (scripts/aytdlp.ps1 runs the server under pythonw, which
# has no console) point this at their log file; everything printed or logged
# from here on lands there.
_log_path = os.environ.get("YTDLP_WEB_LOG")
if _log_path:
    sys.stdout = sys.stderr = open(_log_path, "a", buffering=1, encoding="utf-8", errors="replace")

app = Flask(__name__)

BASE_DIR = Path(__file__).resolve().parent
YTDLP = BASE_DIR / "bin" / ("yt-dlp.exe" if os.name == "nt" else "yt-dlp")
# On Windows a console child would otherwise flash a window for every
# yt-dlp / ffmpeg run when the server itself has no console (pythonw).
SUBPROCESS_FLAGS = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
DOWNLOADS = BASE_DIR / "downloads"
# Per-job scratch space. Anything here at startup is left over from a
# download that was interrupted (server killed or restarted mid-job).
shutil.rmtree(DOWNLOADS, ignore_errors=True)
DOWNLOADS.mkdir(exist_ok=True)

URL_RE = re.compile(
    r"^https?://(www\.)?(youtube\.com/(watch\?|shorts/|playlist\?)|youtu\.be/)"
)


def cleanup_dir(directory: Path):
    # Best effort: a file still held open (or being scanned by antivirus on
    # Windows) must not turn into a second error; leftovers are wiped at startup.
    shutil.rmtree(directory, ignore_errors=True)


class JobFile(io.FileIO):
    """Read-only file that removes its job directory once the response has
    finished streaming (the WSGI server closes the file afterwards).
    Deleting up front and relying on the open handle only works on POSIX;
    Windows refuses to unlink an open file."""

    def __init__(self, path: Path, job_dir: Path):
        super().__init__(path, "rb")
        self.job_dir = job_dir

    def close(self):
        super().close()
        cleanup_dir(self.job_dir)


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/health")
def health():
    return jsonify(ok=True)


@app.route("/api/info", methods=["POST"])
def video_info():
    url = request.json.get("url", "").strip()
    if not URL_RE.match(url):
        return jsonify(error="Invalid YouTube URL"), 400

    result = subprocess.run(
        [str(YTDLP), "--dump-json", "--no-download", url],
        capture_output=True, text=True, timeout=30, **SUBPROCESS_FLAGS,
    )
    if result.returncode != 0:
        return jsonify(error=result.stderr.strip() or "Failed to fetch video info"), 500

    data = json.loads(result.stdout)

    # Extract available video heights
    heights = sorted(
        {f["height"] for f in data.get("formats", [])
         if f.get("height") and f.get("vcodec", "none") != "none"},
    )
    qualities = [f"{h}p" for h in heights]

    # Extract available subtitle languages
    subs = data.get("subtitles", {})
    auto_subs = data.get("automatic_captions", {})
    sub_langs = sorted(subs.keys())

    # Only include the video's original language for auto-captions
    # (other languages are auto-translated and often fail with 429)
    video_lang = (data.get("language") or "").split("-")[0]  # "en-US" -> "en"
    auto_sub_langs = sorted(
        lang for lang in auto_subs
        if lang == video_lang and lang not in subs
    )

    return jsonify(
        title=data.get("title"),
        thumbnail=data.get("thumbnail"),
        duration=data.get("duration"),
        channel=data.get("channel"),
        qualities=qualities,
        subtitle_langs=sub_langs,
        auto_subtitle_langs=auto_sub_langs,
    )


@app.route("/api/download", methods=["POST"])
def download():
    url = request.json.get("url", "").strip()
    fmt = request.json.get("format", "mp4")
    quality = request.json.get("quality", "best")
    subtitles = request.json.get("subtitles", [])
    sub_type = request.json.get("sub_type", "manual")

    if not URL_RE.match(url):
        return jsonify(error="Invalid YouTube URL"), 400

    job_id = uuid.uuid4().hex
    job_dir = DOWNLOADS / job_id
    job_dir.mkdir(parents=True)

    output_template = str(job_dir / "%(title)s.%(ext)s")

    # Network resilience flags to handle YouTube throttling
    net_opts = [
        "--retries", "30",
        "--fragment-retries", "30",
        "--retry-sleep", "exp=1:20",
        "--http-chunk-size", "10M",
    ]

    try:
        if fmt == "mp3":
            cmd = [
                str(YTDLP), *net_opts, "-x", "--audio-format", "mp3",
                "-o", output_template, url,
            ]
        else:
            if quality == "best":
                fmt_spec = "bestvideo+bestaudio/best"
            else:
                h = quality.replace("p", "")
                fmt_spec = f"bestvideo[height<={h}]+bestaudio/best[height<={h}]"
            cmd = [
                str(YTDLP), *net_opts, "-f", fmt_spec,
                "--merge-output-format", "mp4",
                "-o", output_template, url,
            ]
            if subtitles:
                langs = ",".join(subtitles)
                if sub_type == "auto":
                    cmd[1:1] = ["--write-auto-sub", "--sub-lang", langs, "--embed-subs"]
                else:
                    cmd[1:1] = ["--write-sub", "--sub-lang", langs, "--embed-subs"]

        if fmt == "sub_only":
            langs = ",".join(subtitles)
            sub_flags = ["--write-auto-sub"] if sub_type == "auto" else ["--write-sub"]
            cmd = [
                str(YTDLP), *net_opts, *sub_flags, "--sub-lang", langs,
                "--sub-format", "srt/best", "--convert-subs", "srt",
                "--skip-download", "-o", output_template, url,
            ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600, **SUBPROCESS_FLAGS)
        if result.returncode != 0:
            cleanup_dir(job_dir)
            return jsonify(error=result.stderr.strip() or "Download failed"), 500

        # Find the output file(s)
        files = sorted(job_dir.iterdir())
        if not files:
            cleanup_dir(job_dir)
            return jsonify(error="No output file produced"), 500

        if len(files) == 1:
            out_file = files[0]
        else:
            # Several outputs (one .srt per language for subtitles-only):
            # bundle them into a zip named after the shared title, e.g.
            # "Title.en.srt" + "Title.ko.srt" -> "Title.zip".
            title = os.path.commonprefix([p.name for p in files]).rsplit(".", 1)[0].strip()
            out_file = job_dir / f"{title or 'download'}.zip"
            with zipfile.ZipFile(out_file, "w", zipfile.ZIP_DEFLATED) as zf:
                for p in files:
                    zf.write(p, arcname=p.name)

        # JobFile deletes the job dir when the server closes it after
        # streaming. (response.call_on_close never fires for send_file
        # responses, which used to leave every download behind in downloads/.)
        f = JobFile(out_file, job_dir)
        size = os.fstat(f.fileno()).st_size
        response = send_file(f, as_attachment=True, download_name=out_file.name)
        response.content_length = size
        return response

    except subprocess.TimeoutExpired:
        cleanup_dir(job_dir)
        return jsonify(error="Download timed out"), 504
    except Exception as e:
        cleanup_dir(job_dir)
        return jsonify(error=str(e)), 500


def ensure_ytdlp():
    scripts = BASE_DIR / "scripts"
    if os.name == "nt":
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
               "-File", str(scripts / "update_ytdlp.ps1")]
    else:
        cmd = ["bash", str(scripts / "update_ytdlp.sh")]
    print("Checking for yt-dlp updates...")
    result = subprocess.run(
        cmd, capture_output=True, text=True, timeout=60, **SUBPROCESS_FLAGS,
    )
    print(result.stdout.strip())
    if result.returncode != 0:
        print(f"Update script failed: {result.stderr.strip()}")
        if not YTDLP.exists():
            print(f"ERROR: yt-dlp not found at {YTDLP}")
            exit(1)


ensure_ytdlp()
if not shutil.which("ffmpeg"):
    print("WARNING: ffmpeg not found — MP3 conversion and video merging may fail")
print(f"yt-dlp binary: {YTDLP}")

if __name__ == "__main__":
    host = os.environ.get("YTDLP_WEB_HOST", "127.0.0.1")
    port = int(os.environ.get("YTDLP_WEB_PORT", "5000"))
    debug = os.environ.get("YTDLP_WEB_DEBUG", "1") != "0"
    app.run(host=host, port=port, debug=debug)

#!/usr/bin/env bash
set -euo pipefail

# One-shot macOS setup for auto-yt-dlp: Homebrew, Python, ffmpeg, the app's
# venv + yt-dlp binary, the `aytdlp` command, and the SwiftBar menubar toggle.
# Safe to re-run: finished steps are skipped, the rest is refreshed (e.g. after
# pulling updates or moving the repo).

usage() {
  cat <<'EOF'
usage: ./install.sh [--no-menubar] [--no-start]

  --no-menubar   skip SwiftBar and the menubar plugin
  --no-start     don't start the server when done
EOF
}

MENUBAR=1
START=1
for arg in "$@"; do
  case "$arg" in
    --no-menubar) MENUBAR=0 ;;
    --no-start)   START=0 ;;
    -h|--help)    usage; exit 0 ;;
    *)            usage >&2; exit 1 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$REPO_DIR/scripts"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
note() { printf '  • %s\n' "$*"; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }
indent() { sed 's/^/    /'; }

[ "$(uname -s)" = "Darwin" ] || die "install.sh is macOS-only; see \"Manual setup\" in README.md"

# ---------------------------------------------------------------------------
step "Homebrew"

# A fresh Homebrew isn't on PATH until the shell profile is reloaded.
load_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  local p
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$p" ]; then eval "$("$p" shellenv)"; return 0; fi
  done
  return 1
}

if load_brew; then
  ok "found $(command -v brew)"
else
  [ -t 0 ] || die "Homebrew not found; install it from https://brew.sh and re-run"
  read -r -p "  Homebrew not found. Install it now? (asks for your password) [Y/n] " reply
  case "$reply" in
    [nN]*) die "Homebrew is required; install it from https://brew.sh and re-run" ;;
  esac
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew || die "Homebrew install didn't finish"
  ok "installed Homebrew"
fi

# ---------------------------------------------------------------------------
step "Python 3.10+"

# The pinned requirements (click 8.3) need 3.10+; macOS's built-in python3 is 3.9.
py_ok() { "$1" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; }

if command -v python3 >/dev/null 2>&1 && py_ok python3; then
  PYTHON="$(command -v python3)"
else
  brew install python
  PYTHON="$(brew --prefix)/bin/python3"
  py_ok "$PYTHON" || die "no usable Python 3.10+ after brew install python"
fi
ok "$("$PYTHON" --version) at $PYTHON"

# ---------------------------------------------------------------------------
step "ffmpeg"

if command -v ffmpeg >/dev/null 2>&1; then
  ok "found $(command -v ffmpeg)"
else
  brew install ffmpeg
  ok "installed ffmpeg"
fi

# ---------------------------------------------------------------------------
step "App environment"

VENV="$REPO_DIR/venv"
# Rebuild the venv if it's broken (its Python was removed, the repo moved) or
# was made from a Python older than 3.10.
if py_ok "$VENV/bin/python"; then
  ok "reusing venv"
else
  rm -rf "$VENV"
  "$PYTHON" -m venv "$VENV"
  ok "created venv"
fi
"$VENV/bin/python" -m pip install -q --disable-pip-version-check -r "$REPO_DIR/requirements.txt"
ok "installed Python packages"

if bash "$SCRIPTS/update_ytdlp.sh" 2>&1 | indent; then
  ok "yt-dlp ready"
elif [ -x "$REPO_DIR/bin/yt-dlp" ]; then
  note "couldn't check for a newer yt-dlp; keeping the current one"
else
  die "couldn't download yt-dlp; check your network and re-run"
fi

# ---------------------------------------------------------------------------
step "aytdlp command"

chmod +x "$SCRIPTS/aytdlp" "$SCRIPTS/menubar/aytdlp.10s.sh"
BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"
ln -sfn "$SCRIPTS/aytdlp" "$BIN_DIR/aytdlp"
ok "linked ~/bin/aytdlp -> $SCRIPTS/aytdlp"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    case "$(basename "${SHELL:-}")" in
      zsh)  RC="$HOME/.zshrc" ;;
      bash) RC="$HOME/.bash_profile" ;;
      *)    RC="" ;;
    esac
    PATH_LINE='export PATH="$HOME/bin:$PATH"'
    if [ -n "$RC" ]; then
      if grep -qsF "$PATH_LINE" "$RC"; then
        note "~/bin is already added to PATH in $RC; open a new terminal to use \`aytdlp\`"
      else
        printf '\n# added by auto-yt-dlp install.sh\n%s\n' "$PATH_LINE" >> "$RC"
        note "added ~/bin to PATH in $RC; open a new terminal to use \`aytdlp\`"
      fi
    else
      note "add ~/bin to your PATH to use \`aytdlp\` directly"
    fi
    ;;
esac

# ---------------------------------------------------------------------------
if [ "$MENUBAR" = 1 ]; then
  step "SwiftBar menubar"

  if [ -d /Applications/SwiftBar.app ] || [ -d "$HOME/Applications/SwiftBar.app" ]; then
    ok "found SwiftBar"
  else
    brew install --cask swiftbar
    ok "installed SwiftBar"
  fi

  # Respect a plugin folder the user already picked; otherwise preset one so
  # SwiftBar skips its "choose a folder" prompt on first launch.
  PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
  PLUGIN_DIR="${PLUGIN_DIR/#\~/$HOME}"
  if [ -z "$PLUGIN_DIR" ]; then
    PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/SwiftBarPlugins}"
    defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGIN_DIR"
    ok "set SwiftBar plugin folder to $PLUGIN_DIR"
  fi
  mkdir -p "$PLUGIN_DIR"
  cp "$SCRIPTS/menubar/aytdlp.10s.sh" "$PLUGIN_DIR/"
  ok "installed plugin -> $PLUGIN_DIR/aytdlp.10s.sh"

  if pgrep -xq SwiftBar; then
    open -g "swiftbar://refreshallplugins"
    ok "refreshed SwiftBar"
  else
    open -ga SwiftBar
    ok "launched SwiftBar"
  fi
fi

# ---------------------------------------------------------------------------
if [ "$START" = 1 ]; then
  step "Server"
  case "$("$SCRIPTS/aytdlp" status --json)" in
    *'"running":true'*)
      note "already running; run \`aytdlp restart\` to load updated code" ;;
    *)
      "$SCRIPTS/aytdlp" start 2>&1 | indent || note "server didn't start; see \`aytdlp logs\`" ;;
  esac
fi

# ---------------------------------------------------------------------------
step "Done"
cat <<EOF
  aytdlp open                     open the web UI (starts the server if needed)
  aytdlp start | stop | restart   control the background server
  aytdlp status | logs            check on it
EOF
if [ "$MENUBAR" = 1 ]; then
  echo "  Menubar: click the ⬇ icon for Start / Stop / Open in Browser."
  echo "  Tip: SwiftBar → Preferences → Launch at Login keeps the icon after a reboot."
fi

#!/usr/bin/env bash
set -euo pipefail

# Link the `aytdlp` control command into ~/bin and drop the SwiftBar plugin
# into the menubar plugin folder. Re-run after moving the repo.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

chmod +x "$SCRIPT_DIR/aytdlp" "$SCRIPT_DIR/menubar/aytdlp.10s.sh"

BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"
ln -sf "$SCRIPT_DIR/aytdlp" "$BIN_DIR/aytdlp"
echo "linked $BIN_DIR/aytdlp -> $SCRIPT_DIR/aytdlp"

if [ ! -x "$REPO_DIR/venv/bin/python" ]; then
  echo "note: venv missing — before first start run:"
  echo "  cd \"$REPO_DIR\" && python3 -m venv venv && venv/bin/pip install -r requirements.txt"
fi

PLUGIN_SRC="$SCRIPT_DIR/menubar/aytdlp.10s.sh"
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/SwiftBarPlugins}"
if [ -d "$PLUGIN_DIR" ]; then
  cp "$PLUGIN_SRC" "$PLUGIN_DIR/"
  echo "installed SwiftBar plugin -> $PLUGIN_DIR/aytdlp.10s.sh (SwiftBar → Refresh All)"
else
  echo "SwiftBar plugin dir not found ($PLUGIN_DIR); skipping plugin copy"
  echo "  brew install --cask swiftbar, then: cp \"$PLUGIN_SRC\" <plugin-dir>/"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on your PATH — add it to use \`aytdlp\` directly" ;;
esac

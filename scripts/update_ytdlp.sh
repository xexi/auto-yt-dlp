#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/../bin"
mkdir -p "$BIN_DIR"
BIN_DIR="$(cd "$BIN_DIR" && pwd)"
VERSION_FILE="$BIN_DIR/.ytdlp_version"
API_URL="https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Darwin) ASSET_NAME="yt-dlp_macos" ;;
    Linux)
        case "$ARCH" in
            x86_64)  ASSET_NAME="yt-dlp_linux" ;;
            aarch64) ASSET_NAME="yt-dlp_linux_aarch64" ;;
            *)       ASSET_NAME="yt-dlp_linux" ;;
        esac
        ;;
    MINGW*|MSYS*|CYGWIN*) ASSET_NAME="yt-dlp.exe" ;;
    *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

echo "Fetching latest yt-dlp release info..."
LATEST_TAG=$(curl -sL "$API_URL" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")

# Check if already up to date
if [ -f "$VERSION_FILE" ] && [ -f "$BIN_DIR/yt-dlp" ]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE")
    if [ "$CURRENT_VERSION" = "$LATEST_TAG" ]; then
        echo "yt-dlp is already up to date ($CURRENT_VERSION)"
        exit 0
    fi
fi

DOWNLOAD_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${LATEST_TAG}/${ASSET_NAME}"

echo "Downloading yt-dlp $LATEST_TAG ($ASSET_NAME)..."
curl -sL "$DOWNLOAD_URL" -o "$BIN_DIR/yt-dlp"
chmod +x "$BIN_DIR/yt-dlp"

echo "$LATEST_TAG" > "$VERSION_FILE"
echo "yt-dlp $LATEST_TAG installed to $BIN_DIR/yt-dlp"
"$BIN_DIR/yt-dlp" --version

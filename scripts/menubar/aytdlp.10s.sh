#!/usr/bin/env bash
# <bitbar.title>auto-yt-dlp</bitbar.title>
# <bitbar.version>v1.0</bitbar.version>
# <bitbar.author>synth</bitbar.author>
# <bitbar.desc>YouTube downloader web app status</bitbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.environment>[AYTDLP_BIN=aytdlp]</swiftbar.environment>

find_bin() {
  if [ -n "${AYTDLP_BIN:-}" ] && [ -x "$AYTDLP_BIN" ]; then echo "$AYTDLP_BIN"; return; fi
  for p in \
    "$HOME/bin/aytdlp" \
    "$HOME/.local/bin/aytdlp" \
    "/opt/homebrew/bin/aytdlp" \
    "/usr/local/bin/aytdlp"; do
    [ -x "$p" ] && { echo "$p"; return; }
  done
  command -v aytdlp 2>/dev/null
}

AYTDLP="$(find_bin)"

if [ -z "$AYTDLP" ] || [ ! -x "$AYTDLP" ]; then
  echo " | sfimage=exclamationmark.triangle"
  echo "---"
  echo "aytdlp not found | disabled=true"
  echo "Set AYTDLP_BIN in the plugin env to the absolute path of aytdlp. | disabled=true"
  echo "Tried: \$AYTDLP_BIN, ~/bin, ~/.local/bin, /opt/homebrew/bin, /usr/local/bin, \$PATH | disabled=true"
  exit 0
fi

json="$("$AYTDLP" status --json 2>/dev/null)"
running="$(printf '%s' "$json" | sed -nE 's/.*"running":[[:space:]]*(true|false).*/\1/p')"

if [ "$running" = "true" ]; then
  port="$(printf '%s' "$json" | sed -nE 's/.*"port":[[:space:]]*([0-9]+).*/\1/p')"
  echo " | sfimage=arrow.down.circle.fill"
  echo "---"
  echo "Running on :$port | disabled=true"
  echo "Open in Browser | shell=$AYTDLP param1=open terminal=false"
  echo "Restart | shell=$AYTDLP param1=restart terminal=false refresh=true"
  echo "Stop | shell=$AYTDLP param1=stop terminal=false refresh=true"
else
  echo " | sfimage=arrow.down.circle"
  echo "---"
  echo "Not running | disabled=true"
  echo "Start | shell=$AYTDLP param1=start terminal=false refresh=true"
fi

echo "---"
echo "Refresh | refresh=true"

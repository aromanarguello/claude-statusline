#!/bin/bash
# Install Claude Code status line
set -euo pipefail

INSTALL_DIR="$HOME/.claude"
SCRIPT_NAME="statusline-command.sh"
DEST="$INSTALL_DIR/$SCRIPT_NAME"
SETTINGS="$INSTALL_DIR/settings.json"

# Colors for output
green='\033[32m'
cyan='\033[36m'
dim='\033[2m'
reset='\033[0m'

info()  { printf "${cyan}%s${reset}\n" "$*"; }
ok()    { printf "${green}%s${reset}\n" "$*"; }
note()  { printf "${dim}%s${reset}\n" "$*"; }

# --- Preflight checks ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it with:"
  echo "  brew install jq        # macOS"
  echo "  apt install jq         # Debian/Ubuntu"
  exit 1
fi

if ! command -v curl &>/dev/null; then
  echo "Error: curl is required for rate limit data. Install it with:"
  echo "  brew install curl      # macOS"
  echo "  apt install curl       # Debian/Ubuntu"
  exit 1
fi

# --- Determine source file ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"

if [ -f "$SCRIPT_DIR/statusline.sh" ]; then
  SOURCE="$SCRIPT_DIR/statusline.sh"
else
  echo "Error: statusline.sh not found in $SCRIPT_DIR"
  echo "Run this script from the cloned repo directory."
  exit 1
fi

# --- Install script ---
info "Installing status line script..."
mkdir -p "$INSTALL_DIR"
cp "$SOURCE" "$DEST"
chmod +x "$DEST"
ok "  Copied to $DEST"

# --- Update settings.json ---
info "Updating Claude Code settings..."

STATUSLINE_JSON=$(cat <<ENDJSON
{"type":"command","command":"/bin/bash $DEST"}
ENDJSON
)

if [ -f "$SETTINGS" ]; then
  tmp=$(mktemp)
  jq --argjson sl "$STATUSLINE_JSON" '.statusLine = $sl' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  ok "  Updated statusLine in $SETTINGS"
else
  mkdir -p "$INSTALL_DIR"
  echo "{}" | jq --argjson sl "$STATUSLINE_JSON" '. + {statusLine: $sl}' > "$SETTINGS"
  ok "  Created $SETTINGS with statusLine"
fi

echo ""
ok "Done! Restart Claude Code to see your new status line."
note "Customize rate-limit placeholders by editing $DEST"

#!/bin/bash
# Uninstall Claude Code status line
set -euo pipefail

INSTALL_DIR="$HOME/.claude"
DEST="$INSTALL_DIR/statusline-command.sh"
SETTINGS="$INSTALL_DIR/settings.json"

green='\033[32m'
cyan='\033[36m'
reset='\033[0m'

info()  { printf "${cyan}%s${reset}\n" "$*"; }
ok()    { printf "${green}%s${reset}\n" "$*"; }

# --- Remove script ---
if [ -f "$DEST" ]; then
  rm "$DEST"
  ok "Removed $DEST"
else
  info "Script not found at $DEST (already removed?)"
fi

# --- Remove statusLine from settings ---
if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
  if jq -e '.statusLine' "$SETTINGS" &>/dev/null; then
    tmp=$(mktemp)
    jq 'del(.statusLine)' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    ok "Removed statusLine from $SETTINGS"
  else
    info "No statusLine entry in settings (already removed?)"
  fi
fi

echo ""
ok "Done! Restart Claude Code to apply changes."

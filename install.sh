#!/bin/bash
# Install claude-statusline — runs the interactive wizard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node &>/dev/null; then
  echo "Error: Node.js 18+ is required.  brew install node"
  exit 1
fi

if [ ! -d "$SCRIPT_DIR/node_modules/@clack" ]; then
  echo "Installing dependencies..."
  npm install --prefix "$SCRIPT_DIR" --silent
fi

node "$SCRIPT_DIR/setup.js"

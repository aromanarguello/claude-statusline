#!/bin/bash
# Claude Code Status Line
# https://github.com/YOUR_USERNAME/claude-statusline
#
# A rich multi-line status line for Claude Code showing model info,
# token usage, context window, and rate limit indicators.
#
# Input: JSON from Claude Code via stdin
# Output: ANSI-colored multi-line status text

set -euo pipefail

# Read JSON input from stdin
input=$(cat)

# --- Extract values from Claude Code JSON ---
model_name=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // 0')

# --- Computed values ---
total_tokens=$((total_input + total_output))
remaining_tokens=$((context_size - total_tokens))
total_k=$((total_tokens / 1000))
context_k=$((context_size / 1000))

# --- Helpers ---

# Format number with commas (e.g. 134938 -> 134,938)
fmt() {
  echo "$1" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta'
}

# Create a 10-dot progress bar from a percentage
bar() {
  local pct=${1%%.*}  # truncate decimals
  local filled=$((pct / 10))
  local empty=$((10 - filled))
  local out=""
  for ((i = 0; i < filled; i++)); do out+="●"; done
  for ((i = 0; i < empty; i++)); do out+="○"; done
  echo "$out"
}

# --- Colors ---
G='\033[32m'   # green
Y='\033[33m'   # yellow
C='\033[36m'   # cyan
D='\033[2m'    # dim
R='\033[0m'    # reset

# ┌─────────────────────────────────────────────────────────────────┐
# │ Line 1: Model · token counts · used/remaining · thinking       │
# └─────────────────────────────────────────────────────────────────┘
line1="${G}${model_name}${R}"
line1+=" | ${G}${total_k}k / ${context_k}k${R}"
line1+=" | ${Y}${used_pct}% used $(fmt $total_tokens)${R}"
line1+=" | ${G}${remaining_pct}% remain $(fmt $remaining_tokens)${R}"
line1+=" | ${C}thinking: On${R}"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Line 2: Rate limit bars (current = real, weekly/extra = mock)  │
# └─────────────────────────────────────────────────────────────────┘
# NOTE: Claude Code doesn't expose rate-limit data to status lines.
# "current" uses your real context-window %. Weekly & extra are
# placeholders — customize the values below or remove them.
WEEKLY_PCT=20
EXTRA_PCT=40
EXTRA_COST="\$24.19/\$50"

line2="${G}current: $(bar "$used_pct") ${used_pct}%${R}"
line2+=" | ${Y}weekly: $(bar $WEEKLY_PCT) ${WEEKLY_PCT}%${R}"
line2+=" | ${Y}extra: $(bar $EXTRA_PCT) ${EXTRA_COST}${R}"

# ┌─────────────────────────────────────────────────────────────────┐
# │ Line 3: Reset countdowns (placeholder — customize as needed)   │
# └─────────────────────────────────────────────────────────────────┘
now_reset=$(date +"%l:%M%p" | tr '[:upper:]' '[:lower:]' | sed 's/^ //')
weekly_reset=$(date -v+6d +"%b %d, %l:%M%p" 2>/dev/null \
  || date -d "+6 days" +"%b %d, %l:%M%p" 2>/dev/null \
  || echo "—")
weekly_reset=$(echo "$weekly_reset" | tr '[:upper:]' '[:lower:]' | sed 's/^ *//')
month_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null \
  || date -d "next month" +"%b %-d" 2>/dev/null \
  || echo "—")
month_reset=$(echo "$month_reset" | tr '[:upper:]' '[:lower:]')

line3="${D}resets ${now_reset}${R}"
line3+=" | ${D}resets ${weekly_reset}${R}"
line3+=" | ${D}resets ${month_reset}${R}"

# --- Output ---
printf "%b\n%b\n%b\n" "$line1" "$line2" "$line3"

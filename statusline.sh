#!/bin/bash
# Claude Code Status Line
# https://github.com/aromanarguello/claude-statusline
#
# A rich multi-line status line for Claude Code showing model info,
# token usage, context window, and real rate limit data.
#
# Input: JSON from Claude Code via stdin
# Output: ANSI-colored multi-line status text

set -euo pipefail

# --- Cache / credential paths (per-user, not /tmp) ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
USAGE_CACHE="$CACHE_DIR/usage.json"
USAGE_LOCK="$CACHE_DIR/usage.lock"
CACHE_MAX_AGE=60
CRED_FILE="$HOME/.claude/.credentials.json"

mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR" 2>/dev/null || true

# --- Colors ---
G='\033[32m'   # green
Y='\033[33m'   # yellow
C='\033[36m'   # cyan
D='\033[2m'    # dim
RED='\033[31m' # red
R='\033[0m'    # reset

# --- Read JSON input from stdin ---
input=$(cat)

# --- Extract ALL values in a single jq call ---
# Guard against jq failure so set -e doesn't kill us
parsed=""
parsed=$(echo "$input" | jq -r '[
  (.model.display_name // "Unknown"),
  (.context_window.total_input_tokens // 0),
  (.context_window.total_output_tokens // 0),
  (.context_window.context_window_size // 200000),
  (.context_window.used_percentage // 0),
  (.context_window.remaining_percentage // 0),
  (.cost.total_cost_usd // 0),
  (.cost.total_lines_added // 0),
  (.cost.total_lines_removed // 0),
  (.version // "unknown")
] | @tsv' 2>/dev/null) || parsed=""

if [[ -n "$parsed" ]]; then
  IFS=$'\t' read -r model_name total_input total_output context_size used_pct remaining_pct \
       session_cost lines_added lines_removed cc_version <<< "$parsed"
else
  model_name="Unknown"; total_input=0; total_output=0; context_size=200000
  used_pct=0; remaining_pct=0; session_cost=0; lines_added=0; lines_removed=0; cc_version="unknown"
fi

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
  local pct="${1%%.*}"  # truncate decimals
  # Handle non-numeric (e.g. "---")
  if ! [[ "$pct" =~ ^-?[0-9]+$ ]]; then
    echo "○○○○○○○○○○"
    return
  fi
  [[ "$pct" -gt 100 ]] && pct=100
  [[ "$pct" -lt 0 ]] && pct=0
  local filled=$((pct / 10))
  local empty=$((10 - filled))
  local out=""
  for ((i = 0; i < filled; i++)); do out+="●"; done
  for ((i = 0; i < empty; i++)); do out+="○"; done
  echo "$out"
}

# Return color code based on usage percentage
color_for_pct() {
  local pct="$1"
  if ! [[ "$pct" =~ ^[0-9]+$ ]]; then echo "$D"; return; fi
  if [[ "$pct" -ge 80 ]]; then echo "$RED"
  elif [[ "$pct" -ge 50 ]]; then echo "$Y"
  else echo "$G"; fi
}

# File age in seconds (cross-platform)
get_file_age() {
  local file="$1"
  local file_mtime now
  if [[ "$(uname -s)" == "Darwin" ]]; then
    file_mtime=$(stat -f '%m' "$file" 2>/dev/null) || { echo 999999; return; }
  else
    file_mtime=$(stat -c '%Y' "$file" 2>/dev/null) || { echo 999999; return; }
  fi
  now=$(date +%s)
  echo $(( now - file_mtime ))
}

# Convert ISO 8601 UTC to local time string
format_reset_time() {
  local iso="$1"
  if [[ -z "$iso" ]] || [[ "$iso" == "null" ]]; then echo "---"; return; fi

  # Strip fractional seconds
  local clean
  clean=$(echo "$iso" | sed 's/\.[0-9]*+/+/' | sed 's/\.[0-9]*Z/Z/')

  local result=""
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local no_tz
    no_tz=$(echo "$clean" | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//' | sed 's/Z$//')
    local epoch
    epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$no_tz" "+%s" 2>/dev/null) || { echo "---"; return; }
    result=$(date -j -r "$epoch" "+%l:%M%p %b %d" 2>/dev/null) || { echo "---"; return; }
  else
    result=$(date -d "$clean" "+%l:%M%p %b %d" 2>/dev/null) || { echo "---"; return; }
  fi
  echo "$result" | tr '[:upper:]' '[:lower:]' | sed 's/^ //'
}

# --- Credential retrieval ---
# Keychain first on macOS (more reliable), file fallback
get_access_token() {
  local token=""

  # Strategy 1: macOS Keychain (primary)
  if command -v security &>/dev/null; then
    local keychain_json
    keychain_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || true
    if [[ -n "$keychain_json" ]]; then
      token=$(echo "$keychain_json" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      if [[ -n "$token" ]]; then echo "$token"; return 0; fi
    fi
  fi

  # Strategy 2: credentials file fallback
  if [[ -f "$CRED_FILE" ]]; then
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED_FILE" 2>/dev/null)
    if [[ -n "$token" ]]; then echo "$token"; return 0; fi
  fi

  return 1
}

# --- API fetch with stale-while-revalidate caching ---

fetch_usage_bg() {
  # Atomic lock via mkdir (prevents races, works cross-platform)
  if ! mkdir "$USAGE_LOCK" 2>/dev/null; then
    # Lock exists - check if stale (>30s = crashed/timed out)
    local lock_age
    lock_age=$(get_file_age "$USAGE_LOCK")
    if [[ "$lock_age" -lt 30 ]]; then return 0; fi
    rm -rf "$USAGE_LOCK"
    mkdir "$USAGE_LOCK" 2>/dev/null || return 0
  fi

  # Background subshell: fetch API, write cache atomically
  (
    trap 'rm -rf "$USAGE_LOCK"' EXIT

    local token
    token=$(get_access_token) || exit 1

    # Write token to temp file for curl --header @file to avoid ps exposure
    local token_file
    token_file=$(mktemp "$CACHE_DIR/tok.XXXXXX")
    chmod 600 "$token_file"
    printf 'Authorization: Bearer %s' "$token" > "$token_file"

    local response
    response=$(curl -s --max-time 5 \
      -H @"$token_file" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "Accept: application/json" \
      -H "User-Agent: claude-code/${cc_version:-unknown}" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

    rm -f "$token_file"

    # Validate response has expected structure before writing cache
    if echo "$response" | jq -e '.five_hour' &>/dev/null; then
      # Atomic write: tmpfile + mv prevents readers from seeing partial JSON
      local tmp_cache
      tmp_cache=$(mktemp "$CACHE_DIR/cache.XXXXXX")
      echo "$response" > "$tmp_cache"
      mv "$tmp_cache" "$USAGE_CACHE"
    fi
  ) &
  disown 2>/dev/null
}

# Read cached usage data, trigger background refresh if stale
get_usage_data() {
  # Defaults (graceful degradation)
  five_hour_pct="---"
  weekly_pct="---"
  extra_enabled="false"
  extra_pct="---"
  extra_used="---"
  extra_limit="---"
  five_hour_reset="---"
  weekly_reset="---"
  monthly_reset="---"

  if [[ -f "$USAGE_CACHE" ]]; then
    local cache_age
    cache_age=$(get_file_age "$USAGE_CACHE")

    # Parse cache (even if stale - stale data > no data)
    local usage_parsed=""
    usage_parsed=$(jq -r '[
      (.five_hour.utilization // -1 | floor),
      (.five_hour.resets_at // ""),
      ((.seven_day.utilization // -1) | floor),
      (.seven_day.resets_at // ""),
      (.extra_usage.is_enabled // false),
      (.extra_usage.utilization // -1 | floor),
      (.extra_usage.used_credits // 0),
      (.extra_usage.monthly_limit // -1)
    ] | @tsv' "$USAGE_CACHE" 2>/dev/null) || usage_parsed=""

    if [[ -n "$usage_parsed" ]]; then
      local fh_pct_raw fh_reset_raw wk_pct_raw wk_reset_raw ex_en ex_pct_raw ex_used_raw ex_limit_raw
      IFS=$'\t' read -r fh_pct_raw fh_reset_raw wk_pct_raw wk_reset_raw \
           ex_en ex_pct_raw ex_used_raw ex_limit_raw <<< "$usage_parsed"

      # Convert -1 (missing) to "---"
      [[ "$fh_pct_raw" != "-1" ]] && five_hour_pct="$fh_pct_raw"
      [[ "$wk_pct_raw" != "-1" ]] && weekly_pct="$wk_pct_raw"

      extra_enabled="$ex_en"

      if [[ "$extra_enabled" == "true" ]]; then
        [[ "$ex_pct_raw" != "-1" ]] && extra_pct="$ex_pct_raw"
        # Convert cents to dollars
        if [[ "$ex_used_raw" != "0" ]]; then
          extra_used=$(awk "BEGIN {printf \"%.2f\", $ex_used_raw / 100}" 2>/dev/null) || extra_used="---"
        fi
        # monthly_limit can be -1 (null/unlimited) or a real value in cents
        if [[ "$ex_limit_raw" == "-1" ]]; then
          extra_limit="Unlimited"
        elif [[ "$ex_limit_raw" != "0" ]]; then
          extra_limit=$(awk "BEGIN {printf \"%.0f\", $ex_limit_raw / 100}" 2>/dev/null) || extra_limit="---"
        fi
      fi

      # Convert reset times
      [[ -n "$fh_reset_raw" ]] && five_hour_reset=$(format_reset_time "$fh_reset_raw")
      [[ -n "$wk_reset_raw" ]] && weekly_reset=$(format_reset_time "$wk_reset_raw")

      # Monthly reset: 1st of next month
      if [[ "$(uname -s)" == "Darwin" ]]; then
        monthly_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]') || monthly_reset="---"
      else
        monthly_reset=$(date -d "next month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]') || monthly_reset="---"
      fi
      [[ -z "$monthly_reset" ]] && monthly_reset="---"
    fi

    # Trigger background refresh if stale
    if [[ "$cache_age" -ge "$CACHE_MAX_AGE" ]]; then
      fetch_usage_bg
    fi
  else
    # No cache at all - trigger background fetch, show "---" this render
    fetch_usage_bg
  fi
}

# --- Fetch usage data ---
get_usage_data

# ┌─────────────────────────────────────────────────────────────────┐
# │ Line 1: Model · token counts · used/remaining · cost · lines   │
# └─────────────────────────────────────────────────────────────────┘
line1="${G}${model_name}${R}"
line1+=" | ${G}${total_k}k / ${context_k}k${R}"
line1+=" | ${Y}${used_pct}% used $(fmt $total_tokens)${R}"
line1+=" | ${G}${remaining_pct}% remain $(fmt $remaining_tokens)${R}"

# Session cost (only show if non-zero)
if [[ "$session_cost" != "0" ]] && [[ "$session_cost" != "0.0" ]] && [[ "$session_cost" != "0e"* ]]; then
  line1+=" | ${C}\$${session_cost}${R}"
fi

# Lines changed (only show if any)
if [[ "$lines_added" != "0" ]] || [[ "$lines_removed" != "0" ]]; then
  line1+=" | ${G}+${lines_added}${R}/${RED}-${lines_removed}${R}"
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Line 2: Usage bars — all real data from API + context window    │
# └─────────────────────────────────────────────────────────────────┘
ctx_color=$(color_for_pct "$used_pct")
fh_color=$(color_for_pct "$five_hour_pct")
wk_color=$(color_for_pct "$weekly_pct")

line2="${ctx_color}context: $(bar "$used_pct") ${used_pct}%${R}"

if [[ "$five_hour_pct" == "---" ]]; then
  line2+=" | ${D}5-hour: $(bar "---") ---${R}"
else
  line2+=" | ${fh_color}5-hour: $(bar "$five_hour_pct") ${five_hour_pct}%${R}"
fi

if [[ "$weekly_pct" == "---" ]]; then
  line2+=" | ${D}weekly: $(bar "---") ---${R}"
else
  line2+=" | ${wk_color}weekly: $(bar "$weekly_pct") ${weekly_pct}%${R}"
fi

# Extra credits: only show if enabled
if [[ "$extra_enabled" == "true" ]]; then
  ex_color=$(color_for_pct "$extra_pct")
  if [[ "$extra_pct" == "---" ]]; then
    line2+=" | ${D}extra: $(bar "---") ---${R}"
  else
    line2+=" | ${ex_color}extra: $(bar "$extra_pct") \$${extra_used}/\$${extra_limit}${R}"
  fi
fi

# ┌─────────────────────────────────────────────────────────────────┐
# │ Line 3: Reset times — real data from API                       │
# └─────────────────────────────────────────────────────────────────┘
line3="${D}5-hour resets ${five_hour_reset}${R}"
line3+=" | ${D}weekly resets ${weekly_reset}${R}"
if [[ "$extra_enabled" == "true" ]]; then
  line3+=" | ${D}monthly resets ${monthly_reset}${R}"
fi

# --- Output ---
printf "%b\n%b\n%b\n" "$line1" "$line2" "$line3"

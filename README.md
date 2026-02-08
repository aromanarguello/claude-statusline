# claude-statusline

A rich multi-line status line for [Claude Code](https://claude.ai/code) with **real rate limit data**.

![status line screenshot](screenshot.png)

## What it shows

| Line | Content | Source |
|------|---------|--------|
| 1 | Model name, token counts, used/remaining %, session cost, lines changed | Real data from Claude Code |
| 2 | Context bar, 5-hour usage bar, weekly usage bar, extra credits bar | All real — context from stdin, rate limits from API |
| 3 | Rate limit reset times | Real reset times from API |

## How it works

Claude Code pipes a JSON object to the status line command via stdin on each render tick. The script:

1. Extracts token counts and context data from stdin JSON (single `jq` call)
2. Fetches rate limit data from `https://api.anthropic.com/api/oauth/usage` using your OAuth credentials
3. Caches API responses for 60 seconds with non-blocking background refresh (~590ms API call never blocks the render path)
4. Formats everything with ANSI colors and dynamic color-coding (green/yellow/red based on usage level)

On first run, rate limit bars show `---` for ~1 second until the background API fetch completes.

## Requirements

- [jq](https://jqlang.github.io/jq/) — `brew install jq` (macOS) or `apt install jq` (Linux)
- [curl](https://curl.se/) — pre-installed on macOS and most Linux
- [Claude Code](https://claude.ai/code) CLI (Pro, Max, or Team subscription for rate limit data)

> **Note:** API users (pay-per-token) won't see rate limit bars since they have no usage caps. The context bar and session stats still work.

## Install

```bash
git clone https://github.com/aromanarguello/claude-statusline.git
cd claude-statusline
./install.sh
```

Then restart Claude Code.

## Uninstall

```bash
cd claude-statusline
./uninstall.sh
```

## Credential access

On **macOS**, credentials are read from the Keychain (set up automatically when you log in to Claude Code). No extra configuration needed.

On **Linux** or other systems, the script falls back to `~/.claude/.credentials.json` if it exists.

If no credentials are found, rate limit bars gracefully show `---` and the statusline still works for context/model data.

## Customize

Edit `~/.claude/statusline-command.sh` to tweak:

- **Cache duration** — change `CACHE_MAX_AGE` (default 60 seconds)
- **Colors** — modify the ANSI escape codes
- **Color thresholds** — adjust the `color_for_pct()` function (default: green <50%, yellow 50-79%, red 80%+)
- **Remove lines** — delete any `line2`/`line3` sections you don't need

## License

MIT

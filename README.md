# claude-statusline

A rich multi-line status line for [Claude Code](https://claude.ai/code).

![status line screenshot](screenshot.png)

## What it shows

| Line | Content | Source |
|------|---------|--------|
| 1 | Model name, token counts, used/remaining %, thinking mode | Real data from Claude Code |
| 2 | Context usage bar, weekly limit bar, extra credits bar | Context bar is real; weekly & extra are placeholders |
| 3 | Rate limit reset countdowns | Placeholder timestamps |

> **Note:** Claude Code doesn't currently expose rate-limit or billing data to status line scripts. The "weekly" and "extra" bars are placeholders you can customize.

## Requirements

- [jq](https://jqlang.github.io/jq/) — `brew install jq` (macOS) or `apt install jq` (Linux)
- [Claude Code](https://claude.ai/code) CLI

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

## Customize

Edit `~/.claude/statusline-command.sh` to tweak:

- **Weekly/extra bar values** — change `WEEKLY_PCT`, `EXTRA_PCT`, `EXTRA_COST`
- **Colors** — modify the ANSI escape codes (`G`, `Y`, `C`, `D`)
- **Remove lines** — delete any `line2`/`line3` sections you don't need
- **Add data** — the full JSON input schema is documented in the [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code)

## How it works

Claude Code pipes a JSON object to the status line command via stdin on each render tick. The script extracts token counts and context window data with `jq`, formats it with ANSI colors, and prints multi-line output.

## License

MIT

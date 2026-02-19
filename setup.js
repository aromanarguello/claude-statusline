#!/usr/bin/env node
// setup.js — interactive wizard for claude-statusline
import * as p from '@clack/prompts'
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync, mkdirSync, unlinkSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { generateScript } from './lib/generate.js'
import { applyStatusLine } from './lib/patch-settings.js'
import { detectCredentials } from './lib/detect-credentials.js'

const DEST     = join(homedir(), '.claude', 'statusline-command.sh')
const SETTINGS = join(homedir(), '.claude', 'settings.json')

p.intro('claude-statusline setup')

// Step 1: Detect account type
const hasRateLimits = detectCredentials()
if (!hasRateLimits) {
  p.log.info('No OAuth credentials found — rate limit fields hidden (Enterprise/API plan)')
}

// Step 2: Pick data fields
const alwaysOptions = [
  { value: 'model',        label: 'Model name' },
  { value: 'tokenCounts',  label: 'Token counts (used / total)' },
  { value: 'usedPct',      label: 'Used % with raw token count' },
  { value: 'remainingPct', label: 'Remaining % with raw token count' },
  { value: 'linesChanged', label: 'Lines changed (+added / -removed)' },
  { value: 'contextBar',   label: 'Context window progress bar' },
]
const rateLimitOptions = [
  { value: 'rateLimitBars', label: '5-hour & weekly rate limit bars' },
  { value: 'resetTimes',    label: 'Rate limit reset times' },
]

const fields = await p.multiselect({
  message: 'Which data fields do you want? (space to toggle, enter to confirm)',
  options: hasRateLimits ? [...alwaysOptions, ...rateLimitOptions] : alwaysOptions,
  initialValues: ['model', 'tokenCounts', 'usedPct', 'remainingPct', 'contextBar'],
  required: true,
})
if (p.isCancel(fields)) { p.cancel('Cancelled.'); process.exit(0) }

// Step 3: Layout
const layout = await p.select({
  message: 'Layout?',
  options: [
    { value: 'multi',  label: 'Multi-line  (model/tokens on line 1, bars on line 2)' },
    { value: 'single', label: 'Single line (everything on one line)' },
  ],
  initialValue: 'multi',
})
if (p.isCancel(layout)) { p.cancel('Cancelled.'); process.exit(0) }

// Step 4: Color style
const colorStyle = await p.select({
  message: 'Color style?',
  options: [
    { value: 'traffic-light', label: 'Traffic-light  (green <50%, yellow 50-79%, red >=80%)' },
    { value: 'monochrome',    label: 'Monochrome  (no colors)' },
    { value: 'custom',        label: 'Custom thresholds' },
  ],
  initialValue: 'traffic-light',
})
if (p.isCancel(colorStyle)) { p.cancel('Cancelled.'); process.exit(0) }

let thresholds = { yellow: 50, red: 80 }
if (colorStyle === 'custom') {
  const yellow = await p.text({
    message: 'Yellow threshold % (usage at/above this shows yellow)',
    placeholder: '50',
    validate: v => (isNaN(Number(v)) || Number(v) < 1 || Number(v) > 99) ? 'Enter 1-99' : undefined,
  })
  if (p.isCancel(yellow)) { p.cancel('Cancelled.'); process.exit(0) }

  const red = await p.text({
    message: 'Red threshold % (usage at/above this shows red)',
    placeholder: '80',
    validate: v => (isNaN(Number(v)) || Number(v) <= Number(yellow) || Number(v) > 100)
      ? `Enter ${Number(yellow) + 1}-100` : undefined,
  })
  if (p.isCancel(red)) { p.cancel('Cancelled.'); process.exit(0) }

  thresholds = { yellow: Number(yellow), red: Number(red) }
}

// Step 5: Preview
const config = { fields, layout, colorStyle, thresholds }
const script = generateScript(config)

const fakeInput = JSON.stringify({
  model: { display_name: 'Claude Sonnet 4.6 (1M context)' },
  context_window: {
    total_input_tokens: 45000,
    total_output_tokens: 3200,
    context_window_size: 1000000,
    used_percentage: 5,
    remaining_percentage: 95,
  },
  cost: { total_lines_added: 47, total_lines_removed: 12 },
  version: '1.0.0',
})

p.log.step('Preview (sample data):')
// Write script to temp file, pipe fake JSON to it via stdin.
// spawnSync args are an array — no shell, no injection risk.
const tmpScript = join(tmpdir(), `statusline-preview-${Date.now()}.sh`)
try {
  writeFileSync(tmpScript, script, { mode: 0o700 })
  const result = spawnSync('bash', [tmpScript], {
    input: fakeInput,
    encoding: 'utf8',
  })
  if (result.stdout) process.stdout.write(result.stdout)
  if (result.error) p.log.warn('Preview failed: ' + result.error.message)
} finally {
  try { unlinkSync(tmpScript) } catch { /* ignore */ }
}

// Step 6: Confirm and write
const ok = await p.confirm({
  message: `Write to ${DEST} and patch settings.json?`,
  initialValue: true,
})
if (p.isCancel(ok) || !ok) { p.cancel('Nothing written.'); process.exit(0) }

const spinner = p.spinner()
spinner.start('Writing files')

mkdirSync(join(homedir(), '.claude'), { recursive: true })
writeFileSync(DEST, script, { mode: 0o755 })

const rawSettings = existsSync(SETTINGS) ? readFileSync(SETTINGS, 'utf8') : '{}'
writeFileSync(SETTINGS, applyStatusLine(rawSettings, DEST))

spinner.stop('Done')
p.outro(`Restart Claude Code to see your new status line.\nRe-run \`npx claude-statusline\` any time to reconfigure.`)

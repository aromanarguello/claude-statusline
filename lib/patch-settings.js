// lib/patch-settings.js
// Pure function — caller handles reading/writing the file.

export function applyStatusLine(rawJson, scriptPath) {
  let settings
  try {
    settings = JSON.parse(rawJson)
  } catch {
    throw new Error('~/.claude/settings.json is malformed JSON — aborting to avoid corruption')
  }
  settings.statusLine = { type: 'command', command: `/bin/bash ${scriptPath}` }
  return JSON.stringify(settings, null, 2) + '\n'
}

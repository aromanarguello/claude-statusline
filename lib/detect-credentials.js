// lib/detect-credentials.js
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'

/**
 * Returns true if Claude Code OAuth credentials are accessible.
 * Checks macOS Keychain first, then ~/.claude/.credentials.json.
 * Uses execFileSync (not execSync) — no shell, no injection risk.
 */
export function detectCredentials() {
  // macOS Keychain
  try {
    const json = execFileSync(
      'security',
      ['find-generic-password', '-s', 'Claude Code-credentials', '-w'],
      { stdio: ['pipe', 'pipe', 'pipe'], encoding: 'utf8' }
    ).trim()
    if (json) {
      const parsed = JSON.parse(json)
      if (parsed?.claudeAiOauth?.accessToken) return true
    }
  } catch {
    // Not on macOS, no entry, or security binary not found — fall through
  }

  // Credentials file fallback
  const credFile = `${homedir()}/.claude/.credentials.json`
  if (existsSync(credFile)) {
    try {
      const parsed = JSON.parse(readFileSync(credFile, 'utf8'))
      if (parsed?.claudeAiOauth?.accessToken) return true
    } catch {
      // Malformed file — ignore
    }
  }

  return false
}

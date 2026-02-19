// test/patch-settings.test.js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { applyStatusLine } from '../lib/patch-settings.js'

const DEST = '/Users/test/.claude/statusline-command.sh'

test('adds statusLine to empty object', () => {
  const parsed = JSON.parse(applyStatusLine('{}', DEST))
  assert.deepEqual(parsed.statusLine, { type: 'command', command: `/bin/bash ${DEST}` })
})

test('preserves existing keys', () => {
  const input = JSON.stringify({ permissions: { allow: ['Bash(git:*)'] }, model: 'sonnet' })
  const parsed = JSON.parse(applyStatusLine(input, DEST))
  assert.deepEqual(parsed.permissions, { allow: ['Bash(git:*)'] })
  assert.equal(parsed.model, 'sonnet')
})

test('overwrites existing statusLine', () => {
  const input = JSON.stringify({ statusLine: { type: 'command', command: '/old/path.sh' } })
  const parsed = JSON.parse(applyStatusLine(input, DEST))
  assert.equal(parsed.statusLine.command, `/bin/bash ${DEST}`)
})

test('throws on malformed JSON', () => {
  assert.throws(
    () => applyStatusLine('not json', DEST),
    { message: /malformed/ }
  )
})

test('output ends with newline', () => {
  assert.ok(applyStatusLine('{}', DEST).endsWith('\n'))
})

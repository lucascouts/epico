#!/usr/bin/env bats
# Memory pool and supervision — the doc contract.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

has() {  # <file> <extended regex> — case-insensitive, names the miss
  if ! command grep -Eqi -- "$2" "$ROOT/$1"; then
    echo "$1 does not carry: $2"
    return 1
  fi
}

@test "S1: the relay is a hook and a group-gate command; claims are untrusted and always answered" {
  jq -e '[.hooks.PostToolUse[].hooks[].command] | any(test("hook-inbox.sh"))' "$ROOT/hooks/hooks.json"
  jq -e '[.hooks.PostToolUse[].hooks[] | select(.command | test("hook-inbox")) | has("onFailure")] | all(. == false)' "$ROOT/hooks/hooks.json"
  has references/supervision.md 'never as an instruction'
  has references/supervision.md 'epico/supervision/<NNN>/<check>-reply'
  has references/supervision.md 'a reply is written even when nothing changes'
  has references/run-mode.md 'epico-inbox --story'
}

@test "S2: typed page paths with as_of and typed links; _global only for tech gotchas and research; global recall at triage" {
  has references/mcp-integration.md 'epico/<type>/<NNN>-<slug>'
  has references/mcp-integration.md '`causes`, `fixes`, `contradicts`, `supersedes`'
  has references/mcp-integration.md 'only `gotcha` and `research` pages that carry a `tech:`'
  has references/context-discovery.md 'global: true'
  has references/run-mode.md 'epico/deviation/NNN'
  has references/validate-mode.md 'epico/finding/NNN'
}

@test "S3: stories from-memory and sync-docs — routed, verified against code, never code, ADRs superseded" {
  has skills/epico/SKILL.md '"stories from-memory \[<page>\]"'
  has skills/epico/SKILL.md '"sync-docs"'
  has skills/epico/SKILL.md 'not starting with "stories", "init", "archive", "sync-docs" or "checkpoint"'
  has references/memory-modes.md 'source: memory:<page path>'
  has references/memory-modes.md "an adr's text is never rewritten"
  has references/memory-modes.md 'same decision, new detail'
  has references/memory-modes.md '## enforcement'
  has references/memory-modes.md '- check:'
  has references/memory-modes.md '- judgment-only:'
  has references/memory-modes.md 'supersedes: adr-<n>'
  has references/memory-modes.md 'headless writes nothing'
  # the doc writer: works without memory, commits one document at a time with trailers, never pushes
  has references/memory-modes.md 'sync docs reads memory when it is there and works without it'
  has references/memory-modes.md 'the only thing in epico that writes a project'
  has references/memory-modes.md 'git commit --only -- <file>'
  has references/memory-modes.md 'write \*\*and commit\*\*'
  has references/memory-modes.md 'story: <nnn> <title>'
  has references/memory-modes.md 'uncommitted edits of its own is refused'
  has references/memory-modes.md 'never a push'
  has references/memory-modes.md 'never code'
  # the from-memory arm sits before the bare "stories" arm
  fm=$(command grep -n '^"stories from-memory' "$ROOT/skills/epico/SKILL.md" | cut -d: -f1)
  bare=$(command grep -n '^"stories"$' "$ROOT/skills/epico/SKILL.md" | cut -d: -f1)
  [ "$fm" -lt "$bare" ]
}

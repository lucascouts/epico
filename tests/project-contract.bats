#!/usr/bin/env bats
# Project-side rules — the doc contract of the managed CLAUDE.md block, the
# lookup order, the mandatory constitution, the archive and worktree defaults.
#
# The surface is agent-executed prose, so every case asserts keywords in the
# file that carries the rule, case-insensitively. No case requires a sentence
# verbatim: a correct rewrite must stay green.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

has() {  # <file> <extended regex> — case-insensitive, names the miss
  if ! command grep -Eqi -- "$2" "$ROOT/$1"; then
    echo "$1 does not carry: $2"
    return 1
  fi
}

@test "P1: init writes the managed CLAUDE.md block; repair refreshes it; the doctor flags it" {
  has references/init-mode.md 'epico-claude-md write'
  has references/init-mode.md '## the managed claude.md block'
  has references/init-mode.md '## repair \(`init --repair`\)'
  has scripts/doctor.sh 'claude-md.sh" check'
}

@test "P2: one lookup order, in the reference, the managed block and the Executor" {
  has references/lookup-order.md 'memory, as a pointer'
  has references/lookup-order.md 'issue tracker'
  has references/lookup-order.md 'the web\*\*, last'
  has scripts/claude-md.sh 'Where to look, in order'
  has agents/executor.md 'lookup-order.md'
  has references/mcp-integration.md 'part of the \[lookup order\]'
}

@test "P3: the constitution is mandatory, complete, host-derived; triage gates on it; provisioning from project up" {
  has references/constitution.md '## security floor'
  has references/constitution.md '## reversibility'
  has references/constitution.md '## runtime'
  has references/constitution.md '## invariants'
  has references/constitution.md 'the constitution is mandatory'
  has references/init-mode.md 'command -v'
  has references/init-mode.md 'default for a `layperson`'
  has references/triage.md '## constitution gate'
  has references/triage.md 'init --repair'
  has references/engineering-level.md 'only `project` and `product` provision a runtime'
}

@test "P4: init offers a deny rule on the archive; the weight guard keeps proof images up to 2 MB" {
  has references/init-mode.md 'Edit\(\.epico/archive/\*\*\)'
  has references/init-mode.md 'the archive hook is best-effort and stays'
  has scripts/archive-story.sh 'GUARD_PROOF_IMAGE_MAX=2097152'
  has references/list-mode.md 'under a `proof/` directory'
}

@test "P5: worktrees on Claude Code defaults; materialized tests committed before a parallel spawn; the trade is stated" {
  has references/run-parallel.md 'materialized tests are committed before the spawn'
  has references/run-parallel.md 'never lists `\.epico/`'
  has references/run-parallel.md 'the trade is wall clock for cost'
  has references/init-mode.md '\.claude/worktrees/'
  has references/init-mode.md '"baseRef": "head"'
}

@test "P6: the story list marks dormant drafts with both ways out and changes nothing" {
  has references/list-mode.md '`dormant` \| `epico-doctor` reports'
  has references/list-mode.md 'stories archive NNN --force'
  has references/list-mode.md 'stories supersede NNN --by MMM'
  has references/list-mode.md 'a dormant draft is shown, never touched'
}

@test "P7: A7 — plugin root named once in SKILL.md, options on userConfig, README drift fixed, validate --strict in CI" {
  has skills/epico/SKILL.md '\$\{CLAUDE_PLUGIN_ROOT\}/references/'
  has skills/epico/SKILL.md 'triage.md#constitution-gate'
  command jq -e '.userConfig.defaultScale.options == ["fast","standard","full","spike"] and .userConfig.aiMemory.options == ["auto","off"]' "$ROOT/.claude-plugin/plugin.json"
  # The count is derived, so a new agent fails here until the README names it.
  n=$(find "$ROOT/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
  has README.md "$n sub-agents"
  has README.md '4 hook events'
  has README.md 'no output style changes how they respond'
  has .github/workflows/shell.yml 'claude plugin validate --strict'
}

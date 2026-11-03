#!/usr/bin/env bats
# The P2 items of the 2026-10-30 SDD battery's verdict, each pinned to the
# reference that carries it.
#
#   Q1  a refusal points only to commands every Claude Code has — the bundled
#       ones or plain chat — never to another framework's (/gsd-*, /tab), which
#       the requester may not have installed
#   Q2  host hygiene: every process the run started is stopped before the
#       closing unless the requester asked to keep it, and nothing opens on the
#       requester's desktop unasked (servers left running in 3/4 battery runs; an
#       instant run opened a terminal and a browser)
#   Q3  for a layperson the lean route's converge pass is run by a fresh
#       final reviewer that never edits; only a finding the main agent
#       reproduces is fixed (Superpowers: a fresh review found a real defect in
#       7/7 runs, data loss included). It runs after the commit — run before
#       it, 13/14 reports opened with "not committed" — and reports only what
#       breaks the request or the floor through use the requester would make, at
#       most three findings (the 2026-11-03 check also reported ids above 2^53,
#       64 KB lines and non-UTF-8 terminals)
#   Q4  a layperson round of three or more questions whose recommended options
#       they would take becomes numbered assumptions confirmed at once (BMAD:
#       "yes to all 5" replaced five questions)

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "Q1: PURPOSE.md and SKILL.md point only to commands every Claude Code has" {
  for f in "$ROOT/PURPOSE.md" "$ROOT/skills/epico/SKILL.md"; do
    run grep -nE '/gsd-|`/tab`' "$f"
    [ "$status" -eq 1 ] || { echo "${f#"$ROOT"/}: $output" >&2; return 1; }
  done
}

@test "Q2: processes the run started are stopped, and nothing opens on the desktop unasked" {
  for f in "$ROOT/references/lean-route.md" "$ROOT/references/run-mode.md"; do
    grep -qiF 'every process the run started is stopped before the closing' "$f" \
      || { echo "${f#"$ROOT"/}: no stop rule" >&2; return 1; }
    grep -qiF 'nothing opens on the requester' "$f" \
      || { echo "${f#"$ROOT"/}: no desktop rule" >&2; return 1; }
  done
}

@test "Q3: a layperson's converge pass is a fresh, read-only final reviewer's; only reproduced findings are fixed" {
  f="$ROOT/references/lean-route.md"
  grep -qF 'epico:final-reviewer' "$f"
  grep -qiF 'only a finding the main agent reproduces is fixed' "$f"
  grep -qF 'agents/final-reviewer.md' "$ROOT/references/personas.md"
  a="$ROOT/agents/final-reviewer.md"
  grep -q '^tools: Read, Glob, Grep, Bash$' "$a"
  run grep -nE '^tools:.*(Write|Edit)' "$a"
  [ "$status" -eq 1 ]
  grep -qiF 'after the commit' "$f"
  grep -qiF 'through use the requester would make' "$a"
  grep -qiF 'at most three findings' "$a"
}

@test "Q4: a layperson's routine round becomes numbered assumptions confirmed at once" {
  f="$ROOT/references/clarify.md"
  grep -qiF 'numbered assumptions' "$f"
  grep -qiF 'confirmed at once' "$f"
  grep -qiF 'change number' "$f"
}

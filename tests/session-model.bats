#!/usr/bin/env bats
# The model is chosen where it is active — the session. Epico suggests, before
# any work, continuing on the recommended model or starting a session already on
# it; it never tries to switch the model itself.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "triage: Fast and Spike carry a Model line only when the session is not on Sonnet" {
  grep -qF '> - **Model:** (Fast and Spike, only when this session is not on Sonnet)' "$ROOT/references/triage.md"
  grep -qF 'switch this session with `/model sonnet`' "$ROOT/references/triage.md"
  grep -qF '`claude --model sonnet`' "$ROOT/references/triage.md"
}

@test "triage: Epico suggests and never switches; nothing under --auto; Standard/Full go through clarify" {
  f="$ROOT/references/triage.md"
  grep -qF 'So Epico never tries to switch it' "$f"
  grep -qF 'Under `--auto` or headless nothing is suggested' "$f"
  grep -qF 'clarify.md#the-run-model-standard-and-full' "$f"
}

@test "lean route: one line before the work, never a question" {
  f="$ROOT/references/lean-route.md"
  grep -qF '**The model is suggested once, never asked.**' "$f"
  grep -qF 'Then the work starts' "$f"
}

@test "no skill carries a model override" {
  run grep -rlE '^model:' "$ROOT/skills"
  [ "$status" -eq 1 ]
}

@test "every suggestion says /model also changes the default, and how to switch for this session only" {
  for f in triage.md lean-route.md phase-gates.md; do
    grep -qF 'default' "$ROOT/references/$f" || { echo "$f: no default note"; return 1; }
    grep -qF 'press `s`' "$ROOT/references/$f" || { echo "$f: no session-only path"; return 1; }
  done
}

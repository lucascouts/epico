#!/usr/bin/env bats
# The plugin's foundation pillars (owner's decision, 2026-11-08): Security,
# Stability and Performance govern every change to the plugin itself, in that
# order — on a conflict the earlier one wins, so a shortcut that saves time is
# taken only with a proof that the result stays the same, and nothing skips a
# security check. They are written where a contributor reads first (PURPOSE.md),
# mapped to the mechanisms that enforce them (ARCHITECTURE.md), and asked of
# every pull request (the template), so a change states what it costs each one.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "PURPOSE.md names the three pillars in order and the rule for a conflict" {
  local f="$ROOT/PURPOSE.md"
  grep -qF '## Foundation pillars' "$f" || { echo "PURPOSE.md: no Foundation pillars section" >&2; return 1; }
  run grep -nF '**Security, Stability, Performance.**' "$f"
  [ "$status" -eq 0 ] || { echo "PURPOSE.md: the pillars are not named in their order" >&2; return 1; }
  grep -qiF 'the earlier one wins' "$f" || { echo "PURPOSE.md: no conflict rule" >&2; return 1; }
  grep -qiF 'never skips a security check' "$f" || { echo "PURPOSE.md: a shortcut may skip a security check" >&2; return 1; }
}

@test "ARCHITECTURE.md maps each pillar to the mechanisms that enforce it" {
  local f="$ROOT/ARCHITECTURE.md" p
  grep -qF '](#foundation-pillars)' "$f" || { echo "ARCHITECTURE.md: the reading guide does not link the pillars" >&2; return 1; }
  grep -qF '## Foundation pillars' "$f" || { echo "ARCHITECTURE.md: no Foundation pillars section" >&2; return 1; }
  for p in Security Stability Performance; do
    run grep -cE "^\| \*\*$p\*\* \|" "$f"
    [ "$output" -eq 1 ] || { echo "ARCHITECTURE.md: expected one map row for $p, found $output" >&2; return 1; }
  done
}

@test "the pull request template asks for the effect on each pillar" {
  local f="$ROOT/.github/pull_request_template.md" p
  [ -f "$f" ] || { echo "no .github/pull_request_template.md" >&2; return 1; }
  for p in Security Stability Performance; do
    grep -qE "^- \*\*$p\*\*:" "$f" || { echo "template: no line for $p" >&2; return 1; }
  done
}

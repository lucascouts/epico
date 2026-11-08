#!/usr/bin/env bats
# Test economy in the loop (owner's point, 2026-11-08: the tests, optimized as
# far as they go; mattpocock/skills `implement`: "single test files regularly,
# the full test suite once at the end"). A box proves itself with the narrowest
# command that can; the whole suite runs once, at the end, as a gate; the
# runner's own cache and parallelism stay on, and nothing is installed to make
# tests faster; an expected value comes from an independent source, never from
# the code's own computation (mattpocock `tdd`: a tautological test passes by
# construction and can never disagree with the code).

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

section() {  # <file> <heading> — the lines of one `## <heading>` section
  awk -v h="## $2" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$1"
}

@test "tasks.md: Validation is the narrowest command that proves the box, and the suite is a gate run once" {
  local f="$ROOT/references/tasks.md"
  grep -qF '**Validation is testable and narrow.**' "$f" || { echo "tasks.md: rule 5 does not ask for the narrowest command" >&2; return 1; }
  grep -qF 'the whole suite is a Quality Gate, which validate runs once' "$f" || { echo "tasks.md: the suite is not a gate run once" >&2; return 1; }
}

@test "the loop runs each box's own test and Validation, never the whole suite per box" {
  local f
  for f in "$ROOT/references/run-mode.md" "$ROOT/agents/executor.md"; do
    grep -qF 'never the whole suite per box' "$f" || { echo "${f#"$ROOT"/}: no rule against a suite per box" >&2; return 1; }
  done
}

@test "language-rules: each language with a test runner says how a box runs its own tests" {
  local lang s
  for lang in Go Rust Python JavaScript/TypeScript PHP Shell; do
    s=$(section "$ROOT/references/language-rules.md" "$lang")
    grep -qF -- '- A box runs ' <<< "$s" || { echo "language-rules.md, $lang: no line on how a box runs its tests" >&2; return 1; }
  done
  s=$(section "$ROOT/references/language-rules.md" Go)
  grep -qF -- '-count=1' <<< "$s" || { echo "language-rules.md, Go: the test cache is not kept" >&2; return 1; }
  s=$(section "$ROOT/references/language-rules.md" Python)
  grep -qiF 'no new dependency for speed' <<< "$s" || { echo "language-rules.md, Python: a speed plugin may be added" >&2; return 1; }
}

@test "an expected value comes from an independent source: no tautological test" {
  local f
  for f in "$ROOT/agents/test-advisor.md" "$ROOT/agents/executor.md"; do
    grep -qF 'An expected value comes from an independent source' "$f" || { echo "${f#"$ROOT"/}: no rule against tautological tests" >&2; return 1; }
  done
}

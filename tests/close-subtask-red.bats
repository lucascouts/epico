#!/usr/bin/env bats
# close-subtask.sh refuses a plain close of a test-first sub-task whose Red is
# not on record. At engineering level project or product, a Standard or Full
# story records every sub-task's Red in .draft/red-evidence.yaml — the Test
# Advisor's at plan time, an Executor-authored Unit test's at run time
# (run-mode.md, "Recording an Executor-authored Red"). Without this guard a box
# closes with that entry missing and the gap surfaces only at validation, as a
# missing_red that costs a fix round.
#
# Exempt: Tests: None, Fast and spike, experiment and tool, a story with no
# declared engineering level (fail-open on absence), and a --tilde close.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/close-subtask.sh"
  WORK=$(mktemp -d)
  STORY="$WORK/proj/.epico/stories/031-fixture"
  mkdir -p "$STORY/.draft"
  write_tasks standard product
}

teardown() { rm -rf "$WORK"; }

write_tasks() { # <scale> <engineering or "-" for none>
  local eng_line=""
  [ "$2" = - ] || eng_line="engineering: $2"
  cat > "$STORY/tasks.md" <<EOF
---
story: fixture
type: feature
scale: $1
$eng_line
status: in-progress
---

## Task List
- [ ] 1 - The group
  - _Complexity: Simple | Tests: Unit | Risks: None | Dependencies: None_
  - [ ] 1.1 - Test-first
    - Tests: Unit · \`tests/a.bats\` — one case
    - Validation: \`true\`
  - [ ] 1.2 - Structural
    - Tests: None
    - Validation: \`true\`
  - [ ] 1.3 - Also test-first
    - Tests: Unit · \`tests/b.bats\` — one case
    - Validation: \`true\`

## Quality Gates
- [ ] All task validations pass
EOF
}

red_entry() { # <task> — a Red entry on record for that task
  cat >> "$STORY/.draft/red-evidence.yaml" <<EOF
  - task: "$1"
    command: "bats tests/a.bats"
    failed: true
    red_at: assertion
EOF
}

close() { run --separate-stderr bash "$SCRIPT" "$STORY" "$@"; }

box_of() { grep -E "^  - \[.\] $1 " "$STORY/tasks.md" | cut -c6; }

@test "a test-first sub-task with no Red entry is refused, and nothing is written" {
  printf 'red-evidence:\n' > "$STORY/.draft/red-evidence.yaml"
  before=$(cat "$STORY/tasks.md")
  close 1.1
  [ "$status" -eq 1 ]
  printf '%s' "$output" | jq -e '.reason | test("red-evidence") and test("1.1")' > /dev/null
  [ "$(cat "$STORY/tasks.md")" = "$before" ]
}

@test "a missing red-evidence.yaml refuses the same way" {
  close 1.1
  [ "$status" -eq 1 ]
  printf '%s' "$output" | jq -e '.reason | test("red-evidence")' > /dev/null
}

@test "a Red entry on record lets the box close" {
  printf 'red-evidence:\n' > "$STORY/.draft/red-evidence.yaml"
  red_entry 1.1
  close 1.1
  [ "$status" -eq 0 ]
  [ "$(box_of 1.1)" = x ]
}

@test "an entry for another task does not count: 1.3 is refused while only 1.1 is on record" {
  printf 'red-evidence:\n' > "$STORY/.draft/red-evidence.yaml"
  red_entry 1.1
  close 1.3
  [ "$status" -eq 1 ]
}

@test "Tests: None closes with no entry" {
  close 1.2
  [ "$status" -eq 0 ]
  [ "$(box_of 1.2)" = x ]
}

@test "project closes are guarded too; experiment, tool, Fast and an undeclared level are not" {
  write_tasks full project
  close 1.1
  [ "$status" -eq 1 ]
  for spec in "standard experiment" "standard tool" "fast product" "standard -"; do
    # shellcheck disable=SC2086 # two words on purpose
    write_tasks $spec
    close 1.1
    [ "$status" -eq 0 ] || { echo "refused under: $spec"; return 1; }
  done
}

@test "a --tilde close is not a claim the work was done, so it needs no Red" {
  close 1.1 --tilde "waived: no harness for this test here — user decision"
  [ "$status" -eq 0 ]
  [ "$(box_of 1.1)" = "~" ]
}

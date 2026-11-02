#!/usr/bin/env bats
# The project's 500-line limit (CLAUDE.md, Code rules) on what the model reads.
#
# A reference, a skill or an agent is read whole or in slices by the model;
# past 500 lines it is read in slices, and a rule in an unread slice does not
# fire. The 2026-10-30 SDD battery found run-mode.md at 667 lines, and the
# "see it running" defect lived in its tail. Scripts are out of scope here:
# several predate the rule and splitting them is a decision of its own.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "every reference, skill and agent stays under 500 lines" {
  over=0
  for f in "$ROOT"/references/*.md "$ROOT"/skills/*/SKILL.md "$ROOT"/agents/*.md; do
    n=$(wc -l < "$f")
    if [ "$n" -ge 500 ]; then
      echo "${f#"$ROOT"/}: $n lines" >&2
      over=$((over + 1))
    fi
  done
  [ "$over" -eq 0 ]
}

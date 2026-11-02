#!/usr/bin/env bats
# references/run-end.md, "End of Run" — the next-step question.
#
# A finished run asks ONE AskUserQuestion offering ONE next step, decided by
# the story's state, and gates it on the measured context fill:
#
#   N1  the question is AskUserQuestion: one step (refine or validate) plus
#       Stop here — never a menu of modes, never archive
#   N2  the fill is measured by epico-telemetry's `band`, never estimated and
#       never from a guessed --window: a 200k guess on a 1M model read 107%
#   N3  the bands: high recommended here, efficient allowed, degraded a new
#       session — a mode that runs out of room mid-way loses what it checked
#   N4  refine when the plan is owed a change (follow_up entry, fix round 2),
#       run the rest when boxes are open, validate otherwise; archive only
#       after validate, or --force. A partial run on 2026-09-27 reached the old
#       `open box → refine` rule in 3/3 runs and the model overrode it 3/3
#   N5  prose only when AskUserQuestion is not callable; --auto is not headless
#       at the run's end. A 2026-09-27 run wrote "the session is non-interactive,
#       so I logged the recommendation" with the tool available
#   N6  the old y/n Validator prompt is gone, so two offers never coexist
#   N7  a layperson is asked too: the three-line closing form rule names the
#       question as its exception. A run on 2026-09-26 followed the form rule
#       and skipped the question

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  END=$(awk '/^## End of Run/ {f=1; print; next} f && /^## / {exit} f {print}' "$ROOT/references/run-end.md")
  [ -n "$END" ]
}

@test "N1: the next step is one AskUserQuestion with one step and Stop here, never archive" {
  [[ "$END" == *'one `AskUserQuestion`'* ]]
  [[ "$END" == *'offers **one** next step, never a menu of modes'* ]]
  [[ "$END" == *'**Validate**'* ]]
  [[ "$END" == *'**Refine**'* ]]
  [[ "$END" == *'**Stop here**'* ]]
  [[ "$END" == *"**Archive is never this question's step.**"* ]]
}

@test "N2: the context fill is read from epico-telemetry's band, never a guessed window" {
  [[ "$END" == *"epico-telemetry | jq '.context'"* ]]
  [[ "$END" == *'Read `band`'* ]]
  run grep -q 'epico-telemetry --window' "$ROOT/references/run-mode.md" "$ROOT/references/run-end.md"
  [ "$status" -eq 1 ]
}

@test "N3: high recommended here, efficient allowed, degraded a new session" {
  printf '%s\n' "$END" | grep -q '^| `high` | ≤ 100k | ≤ 200k | offered in this session — \*\*strongly recommended here\*\*'
  printf '%s\n' "$END" | grep -q '^| `efficient` | ≤ 150k | ≤ 400k | offered in this session'
  printf '%s\n' "$END" | grep -q '^| `degraded` | above | above | \*\*not run in this session\*\*'
}

@test "N4: refine when the plan is owed a change, run the rest when boxes are open, validate otherwise" {
  printf '%s\n' "$END" | grep -q '^1\. \*\*Refine\*\* — the plan no longer describes the work: an entry in `.draft/deviations.yaml` carries `follow_up: true`'
  printf '%s\n' "$END" | grep -q '^2\. \*\*Run the rest\*\* — the plan still holds and part of it is unrun: the last close.s `census.open > 0`'
  printf '%s\n' "$END" | grep -q '^3\. \*\*Validate\*\* — otherwise'
  grep -q 'optional boolean field `follow_up: true`' "$ROOT/references/run-mode.md"
  # The producer of the signal: without it the flag is the orchestrator's guess.
  grep -q '`follow_up: true` when it leaves work this sub-task did not do' "$ROOT/agents/executor.md"
  # Run mode no longer makes an archive offer of its own.
  run grep -n 'sends the run to the archive offer' "$ROOT/references/run-mode.md"
  [ "$status" -eq 1 ]
}

@test "N5: prose only when AskUserQuestion is not callable; under --auto the recommended step is taken and logged" {
  printf '%s\n' "$END" | grep -q '^\*\*Ask whenever `AskUserQuestion` is callable\*\*'
  [[ "$END" == *'a Fast default and a missing Task tool do not make the run'* ]]
  [[ "$END" == *'`--auto` is the one exception, and it is explicit'* ]]
  [[ "$END" == *'logged as an assumption'* ]]
  printf '%s\n' "$END" | grep -q '^\*\*Only when `AskUserQuestion` is not callable:\*\* do not start the step'
  # The archive offer reads the same signal — the stale TaskCreate one is gone.
  run grep -n '`TaskCreate` present = interactive' "$ROOT/references/validate-mode.md"
  [ "$status" -eq 1 ]
  grep -q '^\*\*Only when `AskUserQuestion` is not callable\*\*' "$ROOT/references/validate-mode.md"
}

@test "N6: the y/n Validator prompt is gone from run-mode.md" {
  run grep -n 'Run Validator to verify' "$ROOT/references/run-mode.md"
  [ "$status" -eq 1 ]
}

@test "N7: the layperson closing-form rules keep the next-step question" {
  [[ "$END" == *'**A `layperson` requester is asked too**'* ]]
  n=$(grep -c "closing three lines.*next-step question" "$ROOT/references/run-mode.md")
  [ "$n" -eq 2 ]
}

@test "N8: SKILL.md carries the next-step rule, since run-mode.md is read in slices" {
  # A 2026-09-26 run grepped run-mode.md for "End of Run" and never read the
  # section: a rule that lives only in a reference does not reach the Fast path.
  grep -q 'A run that finishes a story ends with an `AskUserQuestion`' "$ROOT/skills/epico/SKILL.md"
}

@test "N9: a layperson is offered to see the program running, then asked again" {
  # On 2026-09-26 the Bia persona ignored validate/refine/archive and answered
  # in free text: "run it so I can see it working".
  [[ "$END" == *'**See it running** — `layperson` requester only'* ]]
  [[ "$END" == *'three for a `layperson` requester'* ]]
}

@test "N10: the recommended marker is written in the user's language" {
  # 2026-09-27 battery: a Portuguese run labelled its option "(Recommended)".
  [[ "$END" == *"recommended marker **in the user's language**"* ]]
  grep -q 'never the English marker in another language' "$ROOT/references/clarify.md"
}

@test "N11: the validate-fix loop is bounded — one round, asked, and its revalidation re-checks only the failures" {
  # 2026-09-27 battery: a validate-fix-revalidate loop ran with no ceiling.
  # 2026-10-24 timing: the Auditor was a fifth of an epico run's wall clock, and
  # a second round re-ran the whole suite; the bound came down to one round.
  VM="$ROOT/references/validate-mode.md"
  grep -q '^### Fix loop bound' "$VM"
  grep -q 'Validation fixes — round N' "$VM"
  grep -q '\*\*Round 1 is the only one offered.\*\*' "$VM"
  grep -q '\*\*Every offer states what a round costs\*\*' "$VM"
  [[ "$END" == *'**A fix round is asked, never chained.**'* ]]
}

@test "N12: archive follows validation — validate offers it, supersede passes --force" {
  VM="$ROOT/references/validate-mode.md"
  grep -q '2\. `status:` reads \*\*`validated`\*\* after step 2\.' "$VM"
  grep -q 'Run mode never makes it' "$VM"
  grep -q 'epico-archive NNN --force "superseded by MMM"' "$ROOT/references/supersede-mode.md"
  grep -q '**validated and complete**' "$ROOT/references/list-mode.md"
}

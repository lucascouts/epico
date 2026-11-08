#!/usr/bin/env bats
# Atomic stories, by BMAD's definition (owner's decision, 2026-11-08; read in
# bmad-method 6.12.4: bmad-build/workflow.md SCOPE STANDARD and
# bmad-create-epics-and-stories steps 2-4). One goal per story — two or more
# deliverables that could each be reviewed, tested and merged as their own PR
# are two or more stories; never counted by verbs or "and"; never a split of one
# goal's layers. A story fits one agent, depends only on earlier stories, and
# creates only what it needs. Size is a proposal, never a gate. A split becomes
# a batch whose source is the request; --auto keeps the goals together and logs
# the warning, as BMAD's auto flow does. references/atomic-stories.md is the
# single home of the rule; triage, batch-create and SKILL.md cite it.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
REF="$ROOT/references/atomic-stories.md"

@test "the reference defines one goal the way BMAD does" {
  [ -f "$REF" ] || { echo "no references/atomic-stories.md" >&2; return 1; }
  grep -qF 'reviewed, tested and merged as its own pull request without breaking the others' "$REF" || { echo "no independently-shippable test" >&2; return 1; }
  grep -qF 'Never count verbs' "$REF" || { echo "goals may be counted by verbs or 'and'" >&2; return 1; }
  grep -qF "never split one goal's layers" "$REF" || { echo "a goal may be split by layer" >&2; return 1; }
  grep -qF 'bmad-method 6.12.4' "$REF" || { echo "the source version is not named" >&2; return 1; }
}

@test "the reference carries the other atomicity rules: one agent, no forward dependency, only what it needs" {
  grep -qF 'Fits one agent' "$REF" || { echo "no size rule" >&2; return 1; }
  grep -qF 'No forward dependency' "$REF" || { echo "no forward-dependency rule" >&2; return 1; }
  grep -qF 'Only what it needs' "$REF" || { echo "no create-only-what-it-needs rule" >&2; return 1; }
  grep -qF 'never a gate' "$REF" || { echo "size may block" >&2; return 1; }
  grep -qF 'File churn' "$REF" || { echo "no file-churn check" >&2; return 1; }
}

@test "the split is offered in the proposal, becomes a batch from the request, and --auto keeps the goals together" {
  grep -qF '**Split**' "$REF" && grep -qF '**Keep together**' "$REF" || { echo "the two answers are not named" >&2; return 1; }
  grep -qF 'a batch whose source is the request' "$REF" || { echo "a split is not a batch from the request" >&2; return 1; }
  grep -qF 'Under `--auto`, keep the goals together' "$REF" || { echo "--auto behaviour missing" >&2; return 1; }
  grep -qF 'The lean route and instant create no story' "$REF" || { echo "the check may run where no story exists" >&2; return 1; }
}

@test "triage runs the one-goal check and SKILL.md points to it" {
  grep -qF '[atomic-stories.md](atomic-stories.md)' "$ROOT/references/triage.md" || { echo "triage.md does not run the check" >&2; return 1; }
  grep -qF 'atomic-stories.md' "$ROOT/skills/epico/SKILL.md" || { echo "SKILL.md does not point to the check" >&2; return 1; }
}

@test "batch-create accepts a split's request as its source and derives atomic, ordered stories" {
  local f="$ROOT/references/batch-create.md"
  grep -qF "a split's request" "$f" || { echo "batch-create refuses a split with no document" >&2; return 1; }
  grep -qF '| Blocked by |' "$f" || { echo "the consolidated table has no Blocked by column" >&2; return 1; }
  grep -qF '[atomic-stories.md](atomic-stories.md)' "$f" || { echo "derivation does not apply the atomicity rules" >&2; return 1; }
}

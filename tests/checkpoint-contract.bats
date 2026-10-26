#!/usr/bin/env bats
# The checkpoint mode's contract: the user's verdict before Epico's on judgment
# items, no recommended marker there, --auto stops before judgment, documents
# only through the doc writer, the record of every answer.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REF="$ROOT/references/checkpoint-mode.md"
}

has() {  # <extended regex> — case-insensitive, names the miss
  if ! command grep -Eqi -- "$1" "$REF"; then echo "checkpoint-mode.md does not carry: $1"; return 1; fi
}

@test "routed: the cascade arm, the dispatch row and the description" {
  command grep -qF '"checkpoint <N>"' "$ROOT/skills/epico/SKILL.md"
  command grep -qF '| **Checkpoint** | `/epico:epico checkpoint <N>` | Load [checkpoint-mode.md]' "$ROOT/skills/epico/SKILL.md"
}

@test "the user leads: verdict first on judgment items, no recommended marker, --auto stops before judgment" {
  has 'ask for the user.s verdict, and only then give Epico.s own reading'
  has 'carry \*\*no `\(Recommended\)` marker\*\*'
  has 'under `--auto` the checkpoint runs step 1, prints it, and stops before step 2'
  has 'headless: print every step.s evidence and proposed answers, write nothing'
}

@test "step 1 runs epico-checkpoint and handles every state it returns" {
  has 'run `epico-checkpoint --stage <N>`'
  for st in closed in-work unmapped mismatch open; do has "\`$st\` —"; done
  has 'unknown_ids'
}

@test "documents only through the doc writer; findings become stories only here; batch is printed, not run" {
  has 'only through the doc writer'
  has 'a finding becomes a story only here'
  has 'print the `stories create --batch` command for the stage; do not run it'
  has 'never code, never a story'
}

@test "the record keeps the user's verdict, Epico's reading and the final answer" {
  has '\.epico/checkpoints/<N>\.yaml'
  has '^    user: '
  has '^    epico: '
  has '^    final: '
  has 'follows the project.s `\.epico/\.gitpolicy`'
}

step3() { # the text of Procedure step 3, from its number to step 4's
  awk '/^3\. \*\*Decisions and rules\.\*\*/ { on = 1 } /^4\. / { on = 0 } on' "$REF"
}

in_step3() { # <extended regex> — case-insensitive, inside step 3 only
  if ! step3 | command grep -Eqi -- "$1"; then echo "step 3 does not carry: $1"; return 1; fi
}

@test "step 3 runs epico-depdiff from the previous checkpoint and asks about each uncovered dependency" {
  [ -n "$(step3)" ]
  in_step3 'run `epico-depdiff --base <rev>`'
  in_step3 'last commit that touched `\.epico/checkpoints/<N-1>\.yaml`'
  in_step3 'git log -1 --format=%H -- \.epico/checkpoints/<N-1>\.yaml'
  in_step3 "repository.s first commit"
  in_step3 'git rev-list --max-parents=0 HEAD'
  in_step3 'each `uncovered` (entry|dependency)'
  in_step3 'record an ADR'
  in_step3 'accept it without one'
  in_step3 'not a runtime dependency'
  in_step3 'every `unparsed` manifest'
  in_step3 '`step: 3` items? in `\.epico/checkpoints/<N>\.yaml`'
  # still a judgment item, so the dependency question carries no recommendation
  run bash -c "awk '/^3\\. \\*\\*Decisions/{on=1} /^4\\. /{on=0} on' '$REF' | grep -c 'Recommended'"
  [ "$output" -eq 0 ]
  has 'Judgment items\*\* \(steps 2, 3, 4 and 6\)'
}

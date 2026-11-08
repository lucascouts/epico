#!/usr/bin/env bats
# epico-doctor --deep adds the checks that read across the project's documents,
# which the session-start doctor must stay too fast to run. Warnings only;
# nothing on disk changes.
#
#   K1  without --deep none of these checks run
#   K2  refs: — an open story's ref that does not resolve, named with its status
#   K3  roadmap: — an open story naming a task no ROADMAP or stage file holds
#   K4  ADRs — a repeated number, a Supersedes with no target, an untyped Enforcement line
#   K5  root docs — PRD, ARCHITECTURE or ROADMAP without version or as_of
#   K6  task IDs — one ID written in two places
#   K7  the .gitpolicy verdict when it is not consistent
#   K8  a project fresh from epico-docs-layout has no deep finding
#   K9  the usage names --deep

bats_require_minimum_version 1.5.0

DEEP_CHECKS='["refs","roadmap","adr","docs-frontmatter","task-ids","gitpolicy-verdict"]'

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/.epico/stories"
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email t@example.invalid
  git -C "$PROJ" config user.name t
  bash "$ROOT/scripts/docs-layout.sh" --root "$PROJ" --date 2026-11-08 >/dev/null
  printf 'local-only\n' > "$PROJ/.epico/.gitpolicy"
  printf '.epico/\n' > "$PROJ/.gitignore"
}

teardown() { rm -rf "$WORK"; }

doctor() { run bash -c "cd '$PROJ' && bash '$ROOT/scripts/doctor.sh' $*"; }
deep() { jq -c --argjson d "$DEEP_CHECKS" '[.findings[] | select(.check as $c | $d | index($c))]' <<< "$output"; }
has() { jq -e --arg c "$1" --arg t "$2" 'any(.findings[]; .check == $c and (.detail | contains($t)))' <<< "$output" >/dev/null \
  || { echo "no $1 finding mentioning: $2" >&2; echo "$output" >&2; return 1; }; }

story() {  # $1 = extra frontmatter line
  S="$PROJ/.epico/stories/001-x"; mkdir -p "$S"
  printf -- '---\nversion: 1\ncreated: 2026-11-08\nscale: fast\n%s\n---\n\n## Task List\n- [ ] 1 - Do\n  - Commit: "feat(001): do"\n  - [ ] 1.1 - It\n    - Validation: `true`\n\n## Quality Gates\n- [ ] All tests pass\n' "$1" > "$S/tasks.md"
}

@test "K1 without --deep none of the deep checks run" {
  story 'refs: [PRD#nowhere]'
  doctor
  [ "$status" -eq 0 ]
  [ "$(deep)" = '[]' ]
}

@test "K2 an open story's ref that does not resolve is named, with its status" {
  story 'refs: [PRD#nowhere, ARCHITECTURE#3]'
  doctor --deep
  [ "$status" -eq 0 ]
  has refs 'PRD#nowhere'
  has refs 'no-anchor'
  [ "$(jq '[.findings[] | select(.check == "refs")] | length' <<< "$output")" -eq 1 ]
}

@test "K3 an open story naming a task no ROADMAP or stage file holds" {
  story 'roadmap: [1.1.1, 9.9.9]'
  doctor --deep
  has roadmap '9.9.9'
  [ "$(jq '[.findings[] | select(.check == "roadmap")] | length' <<< "$output")" -eq 1 ]
}

@test "K4 ADRs: a repeated number, a Supersedes with no target, an untyped Enforcement line" {
  A="$PROJ/docs/adr"
  cp "$A/0001-record-architecture-decisions.md" "$A/0002-use-sqlite.md"
  cp "$A/0001-record-architecture-decisions.md" "$A/0002-use-postgres.md"
  printf '# ADR-0003 — X\n\n- Status: Accepted\n- Supersedes: ADR-0009\n\n## Enforcement\n\n- run the tests\n\n## Amendments\n' > "$A/0003-x.md"
  doctor --deep
  has adr '0002'
  has adr 'ADR-0009'
  has adr 'run the tests'
}

@test "K5 a root doc without version or as_of" {
  sed -i '/^as_of:/d' "$PROJ/docs/PRD.md"
  sed -i '/^version:/d' "$PROJ/docs/ROADMAP.md"
  doctor --deep
  has docs-frontmatter 'docs/PRD.md'
  has docs-frontmatter 'docs/ROADMAP.md'
}

@test "K6 one task ID written in two places" {
  printf '# Stage 2\n\n- [ ] **1.1.1 Again**\n' > "$PROJ/docs/stages/02-next.md"
  doctor --deep
  has task-ids '1.1.1'
}

@test "K7 the .gitpolicy verdict, when it is not consistent" {
  story ''
  git -C "$PROJ" add -f .epico/stories/001-x/tasks.md
  doctor --deep
  has gitpolicy-verdict 'contradiction'
}

@test "K8 a project fresh from epico-docs-layout has no deep finding" {
  story 'refs: [ARCHITECTURE#3, stages/01#1.1.2]'
  doctor --deep
  [ "$(deep)" = '[]' ] || { echo "$output" >&2; return 1; }
}

@test "K9 the usage names --deep" {
  run bash "$ROOT/scripts/doctor.sh" --help
  grep -qF -- '--deep' <<< "$output"
}

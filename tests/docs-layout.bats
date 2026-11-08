#!/usr/bin/env bats
# epico-docs-layout writes the optional docs/ template init offers to a
# Standard or Full project: PRD, ARCHITECTURE, ROADMAP as an index, one file
# per stage, and ADRs with Enforcement and Amendments. It writes only what is
# missing and never touches a project that already keeps a ROADMAP — an
# existing project migrates only if it wants to.
#
#   D1  an empty project gets the whole layout, each path listed as written
#   D2  a file already there is kept byte for byte and listed as kept
#   D3  a project with a ROADMAP anywhere is refused, with the path that holds it
#   D4  --dry-run lists what it would write and writes nothing
#   D5  no placeholder survives; the date and the project name are filled in
#   D6  the stage file's tasks are the ones epico-checkpoint reads
#   D7  the ADR carries the sections the doc writer and the checkpoint expect
#   D8  the root docs carry version and as_of, the ROADMAP links its stage
#   D9  the managed CLAUDE.md block finds the docs the layout wrote
#   D10 init offers the layout as a question, default no, and names the command
#   D11 the templates hold no development history

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  PROJ="$WORK/acme-shop"
  mkdir -p "$PROJ"
}

teardown() { rm -rf "$WORK"; }

layout() { run bash "$ROOT/scripts/docs-layout.sh" --root "$PROJ" "$@"; }

EXPECTED='docs/ARCHITECTURE.md
docs/PRD.md
docs/ROADMAP.md
docs/adr/0001-record-architecture-decisions.md
docs/stages/01-foundation.md'

@test "D1 an empty project gets the whole layout, each path listed as written" {
  layout
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = written ]
  [ "$(jq -r '.written[]' <<< "$output" | LC_ALL=C sort)" = "$EXPECTED" ]
  [ "$(cd "$PROJ" && find docs -type f | LC_ALL=C sort)" = "$EXPECTED" ]
}

@test "D2 a file already there is kept byte for byte and listed as kept" {
  mkdir -p "$PROJ/docs"
  printf 'my own PRD\n' > "$PROJ/docs/PRD.md"
  layout
  [ "$status" -eq 0 ]
  [ "$(cat "$PROJ/docs/PRD.md")" = 'my own PRD' ]
  [ "$(jq -r '.kept[]' <<< "$output")" = docs/PRD.md ]
  if jq -e '.written | index("docs/PRD.md")' <<< "$output"; then return 1; fi
}

@test "D3 a project that already keeps a ROADMAP is refused, naming where" {
  for where in ROADMAP.md docs/ROADMAP.md docs/stages/03-api.md; do
    rm -rf "$PROJ" && mkdir -p "$(dirname "$PROJ/$where")"
    printf '# Roadmap\n' > "$PROJ/$where"
    layout
    [ "$status" -eq 1 ] || { echo "not refused: $where" >&2; return 1; }
    [ "$(jq -r .status <<< "$output")" = refused ]
    jq -r .reason <<< "$output" | grep -qF "$where"
    [ ! -e "$PROJ/docs/PRD.md" ]
  done
}

@test "D4 --dry-run lists what it would write and writes nothing" {
  layout --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -r .status <<< "$output")" = dry-run ]
  [ "$(jq -r '.written[]' <<< "$output" | LC_ALL=C sort)" = "$EXPECTED" ]
  [ ! -e "$PROJ/docs" ]
}

@test "D5 no placeholder survives; the date and the project name are filled in" {
  layout --date 2026-11-08
  [ "$status" -eq 0 ]
  if grep -rn '{{' "$PROJ/docs"; then return 1; fi
  grep -q '^as_of: 2026-11-08$' "$PROJ/docs/PRD.md"
  grep -q 'acme-shop' "$PROJ/docs/PRD.md"
  layout --date 08/11/2026
  [ "$status" -eq 2 ]
}

@test "D6 the stage file's tasks are the ones epico-checkpoint reads" {
  layout
  run bash "$ROOT/scripts/checkpoint-reconcile.sh" --stage 1 --root "$PROJ"
  [ "$status" -eq 0 ]
  n=$(jq '.tasks | length' <<< "$output")
  [ "$n" -ge 2 ]
  [ "$(jq -r '[.tasks[].state] | unique | join(",")' <<< "$output")" = open ]
}

@test "D7 the ADR carries the sections the doc writer and the checkpoint expect" {
  layout
  for f in "$PROJ/docs/adr/0001-record-architecture-decisions.md"; do
    for h in '^- Status: ' '^## Context$' '^## Decision$' '^## Consequences$' '^## Enforcement$' '^## Amendments$'; do
      grep -qE "$h" "$f" || { echo "$f lacks $h" >&2; return 1; }
    done
    sed -n '/^## Enforcement$/,/^## /p' "$f" | grep -qE '^- (check: `|judgment-only: )'
  done
}

@test "D8 the root docs carry version and as_of; the ROADMAP links its stage and holds no task" {
  layout
  for d in PRD ARCHITECTURE ROADMAP; do
    head -5 "$PROJ/docs/$d.md" | grep -q '^version: 1$'
    head -5 "$PROJ/docs/$d.md" | grep -q '^as_of: '
  done
  grep -qF '(stages/01-foundation.md)' "$PROJ/docs/ROADMAP.md"
  if grep -qE '^\s*- \[.\] \*\*[0-9]' "$PROJ/docs/ROADMAP.md"; then return 1; fi
}

@test "D9 the managed CLAUDE.md block finds the docs the layout wrote" {
  layout
  git -C "$PROJ" init -q
  mkdir -p "$PROJ/.epico"
  printf '# Constitution\n\n## Quality\n- Unit tests — `true`\n' > "$PROJ/.epico/constitution.md"
  run bash -c "cd '$PROJ' && bash '$ROOT/scripts/claude-md.sh' show"
  [ "$status" -eq 0 ]
  for d in docs/ARCHITECTURE.md docs/ROADMAP.md docs/PRD.md; do
    grep -qF "$d" <<< "$output" || { echo "block misses $d" >&2; echo "$output" >&2; return 1; }
  done
}

@test "D10 init offers the layout as a question, default no, and names the command" {
  f="$ROOT/references/init-mode.md"
  sect=$(sed -n '/^   \*\*Project docs/,/^   \*\*/p' "$f")
  [ -n "$sect" ]
  grep -qF 'epico-docs-layout' <<< "$sect"
  grep -qiE '\[1\] skip \(default\)' <<< "$sect"
  [ -x "$ROOT/bin/epico-docs-layout" ]
}

@test "D11 the templates hold no development history" {
  run bash "$ROOT/tests/lib/provenance-lint.sh" --strict "$ROOT"/assets/templates/docs/*.md "$ROOT"/assets/templates/docs/*/*.md
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

#!/usr/bin/env bats
# `refs:` names the sections of the project's documents a story starts from, as
# `<doc>#<anchor>`. epico-refs turns each into a file and a line range; the
# references are hints, never limits, so an unresolved one is a warning.
#
#   R1  a number matches the heading that starts with it — the whole section
#   R2  4.1 never matches 4.10, and 4 never matches 4.1
#   R3  a task ID in a stage file matches the task line and its sub-bullets
#   R4  anything else is a GitHub heading slug; ADR-<n> finds adr/<nnnn>-*.md
#   R5  a doc that matches two files is ambiguous, with both named
#   R6  an unknown doc, an unknown anchor and a ref with no `#` say which
#   R7  a heading inside a fenced block is not an anchor
#   R8  --story reads tasks.md's refs:; validate-story warns per unresolved ref
#   R9  the references document the field, the grammar and "hints, never limits"

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  mkdir -p "$PROJ"
  bash "$ROOT/scripts/docs-layout.sh" --root "$PROJ" --date 2026-11-08 >/dev/null
}

teardown() { rm -rf "$WORK"; }

refs() { run bash "$ROOT/scripts/resolve-refs.sh" --root "$PROJ" "$@"; }
field() { jq -r --arg r "$1" ".refs[] | select(.ref == \$r) | .$2" <<< "$output"; }
line_of() { grep -nxF -- "$2" "$PROJ/$1" | head -1 | cut -d: -f1; }

@test "R1 a number matches the heading that starts with it, through the end of its section" {
  refs 'ARCHITECTURE#3'
  [ "$status" -eq 0 ]
  [ "$(field 'ARCHITECTURE#3' status)" = found ]
  [ "$(field 'ARCHITECTURE#3' file)" = docs/ARCHITECTURE.md ]
  [ "$(field 'ARCHITECTURE#3' start)" = "$(line_of docs/ARCHITECTURE.md '## 3. Rules')" ]
  [ "$(field 'ARCHITECTURE#3' end)" = "$(( $(line_of docs/ARCHITECTURE.md '## 4. Decisions') - 1 ))" ]
}

@test "R2 4.1 never matches 4.10, and 4 never matches 4.1" {
  printf '# Doc\n\n## 4.10 Ten\n\nten\n\n## 4.1 One\n\none\n\n### 4.1.2 Deeper\n\n## 4 Four\n\nfour\n' > "$PROJ/docs/NOTES.md"
  refs 'NOTES#4.1' 'NOTES#4'
  [ "$(field 'NOTES#4.1' start)" = "$(line_of docs/NOTES.md '## 4.1 One')" ]
  [ "$(field 'NOTES#4.1' end)" = "$(( $(line_of docs/NOTES.md '## 4 Four') - 1 ))" ]
  [ "$(field 'NOTES#4' start)" = "$(line_of docs/NOTES.md '## 4 Four')" ]
}

@test "R3 a task ID in a stage file matches the task line and its sub-bullets" {
  refs 'stages/01#1.1.1'
  [ "$(field 'stages/01#1.1.1' status)" = found ]
  [ "$(field 'stages/01#1.1.1' file)" = docs/stages/01-foundation.md ]
  s=$(field 'stages/01#1.1.1' start) e=$(field 'stages/01#1.1.1' end)
  sed -n "${s}p" "$PROJ/docs/stages/01-foundation.md" | grep -qF '**1.1.1 '
  sed -n "${e}p" "$PROJ/docs/stages/01-foundation.md" | grep -qF 'Complexity:'
  [ "$(sed -n "$((e + 1))p" "$PROJ/docs/stages/01-foundation.md" | grep -cF '**1.1.2 ')" -eq 1 ]
}

@test "R4 anything else is a GitHub heading slug; ADR-<n> finds the numbered ADR" {
  refs 'ADR-0001#enforcement' 'ADR-1#decision' 'ROADMAP#open-blockers'
  for r in 'ADR-0001#enforcement' 'ADR-1#decision' 'ROADMAP#open-blockers'; do
    [ "$(field "$r" status)" = found ] || { echo "$r: $output" >&2; return 1; }
  done
  [ "$(field 'ADR-1#decision' file)" = docs/adr/0001-record-architecture-decisions.md ]
  printf '# T\n\n## Amendment 2026-10-14 — The pin, again!\n\nx\n' > "$PROJ/docs/T.md"
  refs 'T#amendment-2026-10-14--the-pin-again'
  [ "$(field 'T#amendment-2026-10-14--the-pin-again' status)" = found ]
}

@test "R5 a doc that matches two files is ambiguous, and both are named" {
  printf '# A\n\n## 1. X\n' > "$PROJ/ARCHITECTURE.md"
  printf '# S\n' > "$PROJ/docs/stages/01-other.md"
  refs 'ARCHITECTURE#1' 'stages/01#1.1.1'
  [ "$(field 'ARCHITECTURE#1' status)" = ambiguous ]
  [ "$(field 'ARCHITECTURE#1' 'candidates | join(",")')" = 'ARCHITECTURE.md,docs/ARCHITECTURE.md' ]
  [ "$(field 'stages/01#1.1.1' status)" = ambiguous ]
}

@test "R6 an unknown doc, an unknown anchor and a ref with no # each say which" {
  refs 'GLOSSARY#terms' 'PRD#nothing-here' 'PRD'
  [ "$status" -eq 0 ]
  [ "$(field 'GLOSSARY#terms' status)" = no-doc ]
  [ "$(field 'PRD#nothing-here' status)" = no-anchor ]
  [ "$(field 'PRD' status)" = malformed ]
  [ "$(jq .unresolved <<< "$output")" -eq 3 ]
  printf '# Secret\n\n## 1. X\n' > "$WORK/outside.md"
  refs '../outside#1' '/etc/passwd#1' 'docs/../../outside#1'
  [ "$(jq -r '[.refs[].status] | unique | join(",")' <<< "$output")" = malformed ]
}

@test "R7 a heading inside a fenced block is not an anchor" {
  printf '# D\n\n```markdown\n## 9. Fake\n```\n\n## 2. Real\n' > "$PROJ/docs/D.md"
  refs 'D#9' 'D#2'
  [ "$(field 'D#9' status)" = no-anchor ]
  [ "$(field 'D#2' status)" = found ]
}

write_story() {  # $1 = the refs: line
  S="$PROJ/.epico/stories/001-x"
  mkdir -p "$S"
  printf -- '---\nversion: 1\ncreated: 2026-11-08\nscale: fast\n%s\n---\n\n## Task List\n- [ ] 1 - Do\n  - Commit: "feat(001): do"\n  - [ ] 1.1 - It\n    - Validation: `true`\n\n## Quality Gates\n- [ ] All tests pass\n' "$1" > "$S/tasks.md"
}

@test "R8 --story reads refs:, and validate-story warns once per unresolved ref" {
  write_story 'refs: [ARCHITECTURE#3, stages/01#1.1.2, PRD#nowhere]'
  run bash "$ROOT/scripts/resolve-refs.sh" --story "$PROJ/.epico/stories/001-x"
  [ "$(jq '.refs | length' <<< "$output")" -eq 3 ]
  [ "$(jq .unresolved <<< "$output")" -eq 1 ]
  run bash "$ROOT/scripts/validate-story.sh" "$PROJ/.epico/stories/001-x"
  w=$(jq -r '.warnings[] | select(test("refs"))' <<< "$output")
  [ "$(grep -c . <<< "$w")" -eq 1 ]
  grep -qF 'PRD#nowhere' <<< "$w"
  grep -qF 'no-anchor' <<< "$w"
  write_story 'refs: ARCHITECTURE#3'
  run bash "$ROOT/scripts/validate-story.sh" "$PROJ/.epico/stories/001-x"
  jq -r '.warnings[]' <<< "$output" | grep -qF "'refs' is not a list"
}

@test "R9 the references document the field, the grammar, and that refs are hints" {
  grep -qF '`refs:`' "$ROOT/references/tasks.md"
  grep -qF 'epico-refs' "$ROOT/references/context-discovery.md"
  grep -qiF 'hints, never limits' "$ROOT/references/context-discovery.md"
  grep -qF 'REF' "$ROOT/references/batch-create.md"
  grep -qF 'refs:' "$ROOT/references/batch-create.md"
  [ -x "$ROOT/bin/epico-refs" ]
}

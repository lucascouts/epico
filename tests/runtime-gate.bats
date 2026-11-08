#!/usr/bin/env bats
# The runtime gate runs a command, never a version.
#
# Defect found in the 0.28 battery (2026-11-08): a plan carried
# `- [ ] Q11 — Supported and declared runtime: `go 1.27` declared in `go.mod``.
# validate-run.sh runs a gate's first backtick span, `go` is on the PATH, so it
# ran `go 1.27` — a usage error — and recorded a false FAIL. The cause was the
# catalog: only npm had a command (`jq -e .engines package.json`); every other
# stack was described in prose, so the plan author wrote the version instead.
#
#   C1  the catalog gives each declaring stack a command, in both tables
#   C2  each command passes on a project that declares and fails on one that does not
#   L1  a gate whose first span is only a version is a warning that names the fix
#   L2  a gate that leads with a command raises no such warning
#   E1  validate-run settles the catalog's Go command as PASS

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CATALOG="$PLUGIN_ROOT/references/quality-catalog.md"
  WORK=$(mktemp -d)
}

teardown() { rm -rf "$WORK"; }

# stack \t file \t declared content \t undeclared content \t command
STACKS=$(cat <<'EOF'
node	package.json	{"engines":{"node":">=22"}}	{"name":"x"}	jq -e .engines.node package.json
go	go.mod	module x\n\ngo 1.27\n	module x\n	grep -Eq '^go [0-9]' go.mod
python	pyproject.toml	[project]\nrequires-python = ">=3.12"\n	[project]\nname = "x"\n	grep -Eq '^requires-python *=' pyproject.toml
rust	Cargo.toml	[package]\nrust-version = "1.80"\n	[package]\nedition = "2021"\n	grep -Eq '^rust-version *=' Cargo.toml
ruby	Gemfile	ruby "3.4.1"\n	source "https://rubygems.org"\n	grep -Eq '^ruby ' Gemfile
php	composer.json	{"require":{"php":">=8.3"}}	{"require":{}}	jq -e .require.php composer.json
any	.tool-versions	nodejs 22.11.0\n	\n	grep -Eq '^[a-z]+ [0-9]' .tool-versions
EOF
)

floor_row() { grep -F '| Supported and declared runtime |' "$CATALOG" | sed -n "${1}p"; }

@test "C1 the catalog gives each declaring stack a runnable command, in both tables" {
  [ "$(grep -cF '| Supported and declared runtime |' "$CATALOG")" -eq 2 ]
  while IFS=$'\t' read -r stack _ _ _ cmd; do
    for n in 1 2; do
      floor_row "$n" | grep -qF -- "\`$cmd\`" || { echo "row $n lacks the $stack command: $cmd" >&2; return 1; }
    done
  done <<< "$STACKS"
}

@test "C2 each catalog command passes on a declaring project and fails on one that does not" {
  while IFS=$'\t' read -r stack file yes no cmd; do
    mkdir -p "$WORK/$stack/yes" "$WORK/$stack/no"
    printf '%b' "$yes" > "$WORK/$stack/yes/$file"
    printf '%b' "$no" > "$WORK/$stack/no/$file"
    (cd "$WORK/$stack/yes" && bash -c "$cmd" >/dev/null) || { echo "$stack: did not pass on a declaring project" >&2; return 1; }
    if (cd "$WORK/$stack/no" && bash -c "$cmd" >/dev/null 2>&1); then echo "$stack: passed with no declaration" >&2; return 1; fi
  done <<< "$STACKS"
}

write_story() {  # $1 = the runtime gate line
  mkdir -p "$WORK/story"
  cat > "$WORK/story/tasks.md" <<EOF
---
version: 1
created: 2026-11-08
scale: fast
---

## Task List
- [ ] 1 - Implement
  - Commit: "feat(001): implement"
  - [ ] 1.1 - Write it
    - Validation: \`echo ok\`

## Quality Gates
$1
EOF
}

version_warnings() { jq -r '.warnings[]? | select(test("only a version"))' <<< "$1"; }

@test "L1 a gate whose first span is only a version warns, names the line and the catalog fix" {
  for span in 'go 1.27' 'node 22' 'python 3.12' '1.27' 'go1.27' 'node >=22'; do
    write_story "- [ ] Q1 — Supported and declared runtime: \`$span\` declared in \`go.mod\`"
    run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$WORK/story"
    w=$(version_warnings "$output")
    [ -n "$w" ] || { echo "no warning for: $span" >&2; echo "$output" >&2; return 1; }
    grep -qF 'line 14' <<< "$w"
    grep -qF 'quality-catalog.md' <<< "$w"
  done
}

@test "L2 a gate that leads with a command raises no version warning" {
  for gate in "- [ ] Q1 — Supported and declared runtime: \`grep -Eq '^go [0-9]' go.mod\`" \
              '- [ ] Q1 — Unit tests: `go test ./...`' \
              '- [ ] Q1 — README: the two commands it names run' \
              '- [ ] Q1 — Lint: `shellcheck scripts/*.sh` and `go 1.27` in go.mod'; do
    write_story "$gate"
    run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$WORK/story"
    [ -z "$(version_warnings "$output")" ] || { echo "false warning for: $gate" >&2; return 1; }
  done
}

@test "L3 a version span outside the gates section is not a gate and does not warn" {
  write_story '- [ ] All tests pass'
  sed -i 's/^    - Validation: `echo ok`$/    - Validation: `echo ok`; the target is `go 1.27`/' "$WORK/story/tasks.md"
  run bash "$PLUGIN_ROOT/scripts/validate-story.sh" "$WORK/story"
  [ -z "$(version_warnings "$output")" ]
}

@test "E1 validate-run settles the catalog's Go command as PASS" {
  PROJ="$WORK/proj" STORY="$WORK/proj/.epico/stories/001-rt"
  mkdir -p "$STORY"
  git -C "$PROJ" init -q
  printf 'module x\n\ngo 1.27\n' > "$PROJ/go.mod"
  cat > "$STORY/tasks.md" <<'EOF'
---
story: rt
type: feature
scale: fast
status: in-progress
---

## Task List

- [x] 1 - Core

  - [x] 1.1 - Declare
    - Validation: `test -f go.mod` exits 0

## Quality Gates

- [ ] Q1 — Supported and declared runtime: `grep -Eq '^go [0-9]' go.mod`
EOF
  run bash "$PLUGIN_ROOT/scripts/validate-run.sh" --story "$STORY"
  r=$(jq -r '.entries[] | select(.id | startswith("Q1")) | .result' "$STORY/.draft/validation-run.json")
  [ "$r" = "PASS" ] || { echo "$output" >&2; return 1; }
}

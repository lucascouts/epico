#!/usr/bin/env bats
# A revalidation proves the scope of the change before it re-runs anything
# (owner's point, 2026-11-08: "if the fix only touched the lockfile and
# tasks.md, re-test the line that failed and what the diff touches"). Every
# run of validate-run.sh records its fixed point — the commit and a fingerprint
# of the work tree outside .epico/ — and `--since-last` re-runs the failures,
# the entries whose line changed, and what the changed paths can reach:
#
#   nothing outside .epico/ changed          → nothing more        (unchanged)
#   only lockfiles, same resolved versions   → every gate          (same-versions)
#   anything else                            → everything          (code)
#   no fixed point it can trust              → everything, and why (full)
#
# Inside one run, entries sharing a command share one execution. Counters
# outside the project tree prove what ran without changing the tree.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  STORY="$PROJ/.epico/stories/001-scope"
  C="$WORK/count"
  mkdir -p "$STORY" "$PROJ/src" "$C"
  git -C "$PROJ" init -q
  printf 'build/\n' > "$PROJ/.gitignore"
  printf 'v1\n' > "$PROJ/src/app.txt"
  git -C "$PROJ" add -A
  git -C "$PROJ" -c user.email=t@example.invalid -c user.name=t commit -q -m "feat(001): scope core"
  cat > "$STORY/tasks.md" <<EOF
---
story: scope
type: feature
scale: fast
status: in-progress
---

# Implementation Plan - Scope

## Task List

- [x] 1 - Core

  - [x] 1.1 - First check
    - Validation: \`echo a >> $C/a\` exits 0

  - [x] 1.2 - Same command again
    - Validation: \`echo a >> $C/a\` exits 0

  - [x] 1.3 - Needs a marker outside the tree
    - Validation: \`test -f $WORK/marker\` exits 0

## Quality Gates

- [ ] All task validations pass
- [ ] Suite: \`echo g >> $C/g\` passes
EOF
}

teardown() { rm -rf "$WORK"; }

vr() { run bash "$ROOT/scripts/validate-run.sh" --story "$STORY" "$@"; }
result() { jq -r --arg i "$1" '.entries[] | select(.id == $i or (.id | startswith($i))) | .result' "$STORY/.draft/validation-run.json" | head -1; }
count() { [ -f "$C/$1" ] && wc -l < "$C/$1" | tr -d ' ' || echo 0; }
rule() { jq -r '.scope.rule' "$STORY/.draft/validation-run.json"; }
# The project's code only: the story stays untracked, as in a project whose
# .epico/ is not versioned (the tracked case has its own test).
commit_all() { git -C "$PROJ" add -A -- . ':(exclude).epico' && git -C "$PROJ" -c user.email=t@example.invalid -c user.name=t commit -q -m "$1"; }

@test "a run records its fixed point: the commit, the tree outside .epico/ and each entry's line" {
  vr
  j="$STORY/.draft/validation-run.json"
  [ "$(jq -r .head "$j")" = "$(git -C "$PROJ" rev-parse HEAD)" ]
  jq -e '.tree | test("^[0-9a-f]{40}$")' "$j"
  [ "$(jq -r '.entries[] | select(.id == "1.3") | .source.command' "$j")" = "test -f $WORK/marker" ]
}

@test "the tree fingerprint ignores .epico/ and ignored files, and sees everything else" {
  vr; t1=$(jq -r .tree "$STORY/.draft/validation-run.json")
  printf 'note\n' >> "$STORY/tasks.md"; mkdir -p "$PROJ/build"; printf 'x\n' > "$PROJ/build/out"
  vr; [ "$(jq -r .tree "$STORY/.draft/validation-run.json")" = "$t1" ]
  printf 'new\n' > "$PROJ/src/new.txt"
  vr; [ "$(jq -r .tree "$STORY/.draft/validation-run.json")" != "$t1" ]
}

@test "a versioned .epico/ is left out of the fingerprint too, and the user's index is untouched" {
  git -C "$PROJ" add -A
  git -C "$PROJ" -c user.email=t@example.invalid -c user.name=t commit -q -m "chore(001): track the story"
  vr; t1=$(jq -r .tree "$STORY/.draft/validation-run.json")
  [[ "$t1" =~ ^[0-9a-f]{40}$ ]]
  printf 'note\n' >> "$STORY/tasks.md"; git -C "$PROJ" add "$STORY/tasks.md"
  staged=$(git -C "$PROJ" diff --cached --name-only)
  vr; [ "$(jq -r .tree "$STORY/.draft/validation-run.json")" = "$t1" ]
  [ "$(git -C "$PROJ" diff --cached --name-only)" = "$staged" ]
  [ -z "$(git -C "$PROJ" ls-files --others --exclude-standard -- src)" ]
}

@test "entries sharing a command run it once and share its result" {
  vr
  [ "$(count a)" -eq 1 ]
  [ "$(result 1.1)" = PASS ]
  [ "$(result 1.2)" = PASS ]
  jq -e '.entries[] | select(.id == "1.2") | .detail | test("run once, for 1.1")' "$STORY/.draft/validation-run.json"
}

@test "since-last, nothing outside .epico/ changed: only the failure re-runs" {
  vr; [ "$(result 1.3)" = FAIL ]
  touch "$WORK/marker"
  vr --since-last
  [ "$status" -eq 0 ]
  [ "$(rule)" = unchanged ]
  [ "$(result 1.3)" = PASS ]
  [ "$(count a)" -eq 1 ]
  [ "$(count g)" -eq 1 ]
  jq -e '.scope.kept | index("1.1")' "$STORY/.draft/validation-run.json"
  jq -e '.entries[] | select(.id == "1.1") | .kept | test("unchanged since")' "$STORY/.draft/validation-run.json"
  [ "$(jq -r .scope <<< "$output")" = unchanged ]
}

@test "since-last, a tracked file changed: everything re-runs" {
  vr
  printf 'v2\n' > "$PROJ/src/app.txt"
  vr --since-last
  [ "$(rule)" = code ]
  [ "$(count a)" -eq 2 ]
  [ "$(count g)" -eq 2 ]
  jq -e '.scope.changed[] | select(.path == "src/app.txt" and .class == "code")' "$STORY/.draft/validation-run.json"
}

@test "since-last, a committed fix is seen like an uncommitted one" {
  vr
  printf 'v2\n' > "$PROJ/src/app.txt"; commit_all "fix(001): app"
  vr --since-last
  [ "$(rule)" = code ]
  [ "$(count a)" -eq 2 ]
}

@test "since-last, an ignored file is no change; a new untracked one is" {
  vr
  mkdir -p "$PROJ/build"; printf 'x\n' > "$PROJ/build/out"
  vr --since-last; [ "$(rule)" = unchanged ]; [ "$(count a)" -eq 1 ]
  printf 'n\n' > "$PROJ/notes.txt"
  vr --since-last; [ "$(rule)" = code ]; [ "$(count a)" -eq 2 ]
}

@test "since-last, a lockfile with the same resolved versions re-runs the gates only" {
  printf '{"lockfileVersion":3,"packages":{"":{"name":"p"},"node_modules/left-pad":{"version":"1.3.0","integrity":"sha512-AAA"}}}\n' > "$PROJ/package-lock.json"
  commit_all "chore(001): lock"
  vr
  printf '{\n  "lockfileVersion": 3,\n  "packages": {\n    "": {"name": "p"},\n    "node_modules/left-pad": {"version": "1.3.0", "integrity": "sha512-BBB"}\n  }\n}\n' > "$PROJ/package-lock.json"
  vr --since-last
  [ "$(rule)" = same-versions ]
  [ "$(count a)" -eq 1 ]
  [ "$(count g)" -eq 2 ]
  jq -e '.scope.changed[] | select(.path == "package-lock.json" and .class == "lock")' "$STORY/.draft/validation-run.json"
}

@test "since-last, a lockfile whose resolved version moved re-runs everything" {
  printf '{"lockfileVersion":3,"packages":{"node_modules/left-pad":{"version":"1.3.0"}}}\n' > "$PROJ/package-lock.json"
  commit_all "chore(001): lock"
  vr
  printf '{"lockfileVersion":3,"packages":{"node_modules/left-pad":{"version":"1.3.1"}}}\n' > "$PROJ/package-lock.json"
  vr --since-last
  [ "$(rule)" = code ]
  [ "$(count a)" -eq 2 ]
  jq -e '.scope.reason | test("package-lock.json")' "$STORY/.draft/validation-run.json"
}

@test "since-last, a lockfile it cannot read counts as code" {
  printf '{"lockfileVersion":3,"packages":{}}\n' > "$PROJ/package-lock.json"
  commit_all "chore(001): lock"
  vr
  printf '{ not json\n' > "$PROJ/package-lock.json"
  vr --since-last
  [ "$(rule)" = code ]
  [ "$(count a)" -eq 2 ]
}

@test "since-last, an entry whose line in tasks.md changed re-runs although nothing else did" {
  vr
  sed -i "s|test -f $WORK/marker|true|" "$STORY/tasks.md"
  vr --since-last
  [ "$(rule)" = unchanged ]
  [ "$(result 1.3)" = PASS ]
  [ "$(count a)" -eq 1 ]
}

@test "since-last with no previous run, or one without a fixed point, runs everything and says why" {
  vr --since-last
  [ "$(rule)" = full ]
  jq -e '.scope.reason | test("no previous run")' "$STORY/.draft/validation-run.json"
  [ "$(count a)" -eq 1 ]
  jq 'del(.tree)' "$STORY/.draft/validation-run.json" > "$WORK/j" && mv "$WORK/j" "$STORY/.draft/validation-run.json"
  vr --since-last
  [ "$(rule)" = full ]
  [ "$(count a)" -eq 2 ]
}

@test "since-last after a history rewrite runs everything" {
  printf 'v2\n' > "$PROJ/src/app.txt"; commit_all "feat(001): second"
  vr
  git -C "$PROJ" reset -q --hard HEAD~1
  printf 'v2\n' > "$PROJ/src/app.txt"; commit_all "feat(001): second, rewritten"
  vr --since-last
  [ "$(rule)" = full ]
  jq -e '.scope.reason | test("rewritten")' "$STORY/.draft/validation-run.json"
}

@test "--since-last and --only together are bad usage" {
  vr --since-last --only 1.1
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "lockfile parsers: the resolved name@version set of each format" {
  source "$ROOT/scripts/lib-lock-versions.sh"
  [ "$(printf 'golang.org/x/text v0.3.0 h1:a=\ngolang.org/x/text v0.3.0/go.mod h1:b=\n' | lock_versions go.sum)" = "golang.org/x/text@v0.3.0" ]
  [ "$(printf '[[package]]\nname = "serde"\nversion = "1.0.1"\nsource = "x"\n\n[[package]]\nname = "app"\nversion = "0.1.0"\n' | lock_versions Cargo.lock | paste -sd,)" = "app@0.1.0,serde@1.0.1" ]
  [ "$(printf 'version = 1\n[[package]]\nname = "rich"\nversion = "13.0"\n' | lock_versions uv.lock)" = "rich@13.0" ]
  [ "$(printf '{"packages":[{"name":"a/b","version":"1.0"}],"packages-dev":[{"name":"c/d","version":"2.0"}]}' | lock_versions composer.lock | paste -sd,)" = "a/b@1.0,c/d@2.0" ]
  [ "$(printf 'GEM\n  remote: https://rubygems.org/\n  specs:\n    rake (13.0.6)\n    rspec (3.12.0)\n      rspec-core (~> 3.12.0)\n' | lock_versions Gemfile.lock | paste -sd,)" = "rake@13.0.6,rspec@3.12.0" ]
  run lock_versions package-lock.json <<< '{"lockfileVersion":1,"dependencies":{}}'
  [ "$status" -eq 3 ]
  run lock_versions go.sum <<< 'not a go.sum line'
  [ "$status" -eq 3 ]
  run lock_versions yarn.lock <<< 'anything'
  [ "$status" -eq 3 ]
}

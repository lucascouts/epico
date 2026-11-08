#!/usr/bin/env bats
# epico-gitpolicy reports `effective`: the policy the workspace actually runs
# under. A declared policy is its own effective one; an undeclared workspace is
# inferred from what git does — `tracked-md` when git tracks any .epico/
# markdown, `local-only` otherwise. The checkpoint and the supervisors read it
# to decide whether their records are versioned, so they never guess.
#
#   G1  a declared policy is the effective one, whatever git tracks
#   G2  undeclared, with .epico/ markdown tracked → tracked-md
#   G3  undeclared, nothing tracked → local-only
#   G4  undeclared, only .draft/ tracked → local-only (.draft/ is never an artifact)
#   G5  not a git repository → the declared policy, else local-only
#   G6  the doctor's warning for a missing .gitpolicy names the inferred policy
#   G7  the checkpoint follows `effective`, never the file alone

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/.epico/stories/001-a/.draft"
  printf -- '---\nstory: a\n---\n' > "$WORK/.epico/stories/001-a/story.md"
  printf 'log\n' > "$WORK/.epico/stories/001-a/.draft/run.md"
}

teardown() { rm -rf "$WORK"; }

repo() { git -C "$WORK" init -q; git -C "$WORK" config user.email t@example.invalid; git -C "$WORK" config user.name t; }
commit() { git -C "$WORK" add -f -- "$@" && git -C "$WORK" commit -q -m c; }
eff() { (cd "$WORK" && bash "$ROOT/scripts/epico-gitpolicy.sh") | jq -r .effective; }

@test "G1 a declared policy is the effective one, whatever git tracks" {
  repo
  printf 'local-only\n' > "$WORK/.epico/.gitpolicy"
  commit .epico/stories/001-a/story.md
  [ "$(eff)" = local-only ]
  printf 'tracked-md\n' > "$WORK/.epico/.gitpolicy"
  git -C "$WORK" rm -q --cached .epico/stories/001-a/story.md
  [ "$(eff)" = tracked-md ]
}

@test "G2 undeclared, with .epico/ markdown tracked, is tracked-md" {
  repo
  commit .epico/stories/001-a/story.md
  out=$(cd "$WORK" && bash "$ROOT/scripts/epico-gitpolicy.sh")
  [ "$(jq -r .policy <<< "$out")" = undeclared ]
  [ "$(jq -r .effective <<< "$out")" = tracked-md ]
}

@test "G3 undeclared, with nothing tracked, is local-only" {
  repo
  [ "$(eff)" = local-only ]
}

@test "G4 undeclared, with only .draft/ tracked, is local-only" {
  repo
  commit .epico/stories/001-a/.draft/run.md
  [ "$(eff)" = local-only ]
}

@test "G5 outside a git repository: the declared policy, else local-only" {
  [ "$(eff)" = local-only ]
  printf 'tracked-md\n' > "$WORK/.epico/.gitpolicy"
  [ "$(eff)" = tracked-md ]
}

@test "G6 the doctor's warning for a missing .gitpolicy names the inferred policy" {
  repo
  commit .epico/stories/001-a/story.md
  run bash -c "cd '$WORK' && bash '$ROOT/scripts/doctor.sh'"
  w=$(jq -r '.. | objects | select(.check? == "gitpolicy") | .detail' <<< "$output")
  grep -qF 'tracked-md' <<< "$w" || { echo "$output" >&2; return 1; }
}

@test "G7 the checkpoint follows the effective policy" {
  grep -qF '`effective`' "$ROOT/references/checkpoint-mode.md"
}

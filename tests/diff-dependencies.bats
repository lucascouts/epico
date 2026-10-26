#!/usr/bin/env bats
# epico-depdiff: the new runtime dependencies between two revisions of a
# repository. This file pins the envelope — the flags, how a revision resolves,
# the refusal paths and the one JSON object on stdout — on real temporary git
# repositories; git state is never mocked. The manifest parsers and the ADR
# coverage get their own cases further down.
#
# Assertions stay behaviour-level on purpose: a reason is looked for among the
# JSON's strings, not under a pinned key, and `base`/`head` are checked by the
# commit they resolve to, not by their spelling.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$PLUGIN_ROOT/scripts/diff-dependencies.sh"
  # Hermetic git: no /etc/gitconfig, no init template, a fixed identity.
  export GIT_CONFIG_NOSYSTEM=1 GIT_TEMPLATE_DIR=
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  R=$(mktemp -d)
  git init -q -b main "$R"
  printf '{"name": "app", "dependencies": {}}\n' > "$R/package.json"
  commit "$R" base package.json
  BASE=$(git -C "$R" rev-parse HEAD)
  printf 'readme\n' > "$R/README.md"
  commit "$R" head README.md
  HEAD_SHA=$(git -C "$R" rev-parse HEAD)
}

teardown() { rm -rf "$R" ${O:+"$O"} ${N:+"$N"}; }

commit() { # <repo> <message> <path>... — signing off, whatever the user's global config says
  local repo=$1 msg=$2; shift 2
  git -C "$repo" add -- "$@"
  git -C "$repo" -c commit.gpgsign=false commit -q -m "$msg"
}

depdiff_run() { run --separate-stderr bash "$SCRIPT" --root "$R" "$@"; }

one_object() { # $output is exactly one JSON object
  printf '%s' "$output" | jq -s -e 'length == 1 and (.[0] | type == "object")' > /dev/null \
    || { echo "stdout is not one JSON object: $output"; return 1; }
}

reason_names() { # <text> — some string in the JSON on stdout carries it
  printf '%s' "$output" | jq -e --arg s "$1" '[.. | strings] | any(.[]; contains($s))' > /dev/null \
    || { echo "no string in the JSON names '$1': $output"; return 1; }
}

resolves_to() { # <field> <sha> [<repo>] — the field names that commit
  local got
  got=$(printf '%s' "$output" | jq -r --arg f "$1" '.[$f]')
  [ "$(git -C "${3:-$R}" rev-parse --verify --quiet "$got^{commit}")" = "$2" ] \
    || { echo ".$1 = '$got' does not resolve to $2"; return 1; }
}

@test "1.1: missing --base exits 2 with the reason in one JSON object on stdout" {
  depdiff_run
  [ "$status" -eq 2 ]
  one_object
  reason_names "--base"
}

@test "1.1: --base given with no value counts as missing" {
  depdiff_run --base
  [ "$status" -eq 2 ]
  one_object
  reason_names "--base"
}

@test "1.1: a revision that names no object is refused, for --base and for --head" {
  depdiff_run --base no-such-rev
  [ "$status" -eq 2 ]
  one_object
  reason_names "no-such-rev"

  # The head is checked too, not only the base.
  depdiff_run --base "$BASE" --head other-missing-rev
  [ "$status" -eq 2 ]
  one_object
  reason_names "other-missing-rev"
}

@test "1.1: an object that is not a commit is refused — a tree as base, a blob as head" {
  tree=$(git -C "$R" rev-parse "HEAD^{tree}")
  blob=$(git -C "$R" rev-parse "HEAD:package.json")

  depdiff_run --base "$tree"
  [ "$status" -eq 2 ]
  one_object

  depdiff_run --base "$BASE" --head "$blob"
  [ "$status" -eq 2 ]
  one_object
}

@test "1.1: an annotated tag peels to its commit and is accepted" {
  # The converse of the refusal above: a non-commit object that points at a
  # commit is a commit for this purpose.
  git -C "$R" -c tag.gpgsign=false tag -a -m "first" v1 "$BASE"
  depdiff_run --base v1
  [ "$status" -eq 0 ]
  one_object
  resolves_to base "$BASE"
}

@test "1.1: valid revisions exit 0 with every key of the contract" {
  depdiff_run --base "$BASE" --head "$HEAD_SHA"
  [ "$status" -eq 0 ]
  one_object
  printf '%s' "$output" | jq -e '
    has("base") and has("head") and has("adr_dir")
    and has("new") and has("uncovered") and has("unparsed")
    and (.new | type) == "array"
    and (.uncovered | type) == "array"
    and (.unparsed | type) == "array"' > /dev/null
  # Only a README changed: no manifest gained a dependency.
  printf '%s' "$output" | jq -e '.new == [] and .uncovered == [] and .unparsed == []' > /dev/null
  resolves_to base "$BASE"
  resolves_to head "$HEAD_SHA"
}

@test "1.1: --head defaults to HEAD, and a symbolic base resolves to its commit" {
  depdiff_run --base HEAD~1
  [ "$status" -eq 0 ]
  one_object
  resolves_to base "$BASE"
  resolves_to head "$HEAD_SHA"
}

@test "1.1: --root defaults to the current directory" {
  cd "$R"
  run --separate-stderr bash "$SCRIPT" --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  resolves_to head "$HEAD_SHA"
}

@test "1.1: revisions resolve in --root, never in the current directory" {
  O=$(mktemp -d)
  git init -q -b main "$O"
  printf 'other\n' > "$O/other.txt"
  commit "$O" other other.txt
  O_SHA=$(git -C "$O" rev-parse HEAD)

  # Standing in O, --root R: R's base resolves and the head is R's HEAD, not O's.
  cd "$O"
  run --separate-stderr bash "$SCRIPT" --root "$R" --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  resolves_to head "$HEAD_SHA"

  # Standing in R, --root O: R's base does not exist there.
  cd "$R"
  run --separate-stderr bash "$SCRIPT" --root "$O" --base "$BASE"
  [ "$status" -eq 2 ]
  one_object

  # And O's own commit is found when O is the root.
  run --separate-stderr bash "$SCRIPT" --root "$O" --base "$O_SHA"
  [ "$status" -eq 0 ]
  resolves_to head "$O_SHA" "$O"
}

@test "1.1: a root that is not a git repository is refused" {
  N=$(mktemp -d)
  run --separate-stderr bash "$SCRIPT" --root "$N" --base HEAD
  [ "$status" -eq 2 ]
  one_object
}

@test "1.1: the working tree and the index are never read" {
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  before=$output

  # A dependency added only on disk, and a manifest only staged: neither is a
  # revision, so the answer for the same revisions must not move.
  printf '{"name": "app", "dependencies": {"left-pad": "1.3.0"}}\n' > "$R/package.json"
  printf 'module example.com/app\n\ngo 1.22\n\nrequire github.com/pkg/errors v0.9.1\n' > "$R/go.mod"
  git -C "$R" add go.mod

  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  [ "$output" = "$before" ] || { echo "output moved with the working tree: $output"; return 1; }
}

@test "1.1: bin/epico-depdiff runs the script by bare name" {
  [ -x "$PLUGIN_ROOT/bin/epico-depdiff" ]
  PATH="$PLUGIN_ROOT/bin:$PATH" run --separate-stderr epico-depdiff --root "$R" --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  resolves_to head "$HEAD_SHA"

  PATH="$PLUGIN_ROOT/bin:$PATH" run --separate-stderr epico-depdiff --root "$R"
  [ "$status" -eq 2 ]
  one_object
}

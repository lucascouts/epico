#!/usr/bin/env bash
# tests/lib/depdiff-fixture.sh — the shared fixture of the diff-dependencies
# suites: a real temporary git repository with a base and a head commit, and
# the readers of the script's JSON. Sourced by each suite's setup, so every
# slice of the script gets the same hermetic git without copying it.
#
# The envelope suite (tests/diff-dependencies.bats) keeps its own copy of the
# first half: it is a pre-authored test, and its text is frozen.

depdiff_fixture_setup() {
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

put() { # <path> — stdin becomes the file at <path> in R
  mkdir -p "$(dirname "$R/$1")"
  cat > "$R/$1"
}

snapshot() { # <message> — record everything in R, print the new commit
  commit "$R" "$1" .
  git -C "$R" rev-parse HEAD
}

new_pairs() { printf '%s' "$output" | jq -r '.new[] | "\(.manifest) \(.name)"' | LC_ALL=C sort; }

new_is() { # <"manifest name">... — `new` holds exactly these, in sorted order
  local want got
  want=$(printf '%s\n' "$@")
  got=$(new_pairs)
  [ "$got" = "$want" ] || { printf 'new is:\n%s\nwanted:\n%s\n' "$got" "$want"; return 1; }
}

unparsed_manifests() { printf '%s' "$output" | jq -r '[.unparsed[].manifest] | unique | .[]'; }

covered_by_of() { # <name> — the ADRs covering it, comma-joined
  printf '%s' "$output" | jq -r --arg n "$1" '[.new[] | select(.name == $n) | .covered_by[]] | join(",")'
}

uncovered_names() { printf '%s' "$output" | jq -r '[.uncovered[].name] | sort | join(",")'; }

adr_dir_is() { # <json> — adr_dir equals it
  printf '%s' "$output" | jq -e --argjson want "$1" '.adr_dir == $want' > /dev/null \
    || { echo "adr_dir is $(printf '%s' "$output" | jq -c .adr_dir), wanted $1"; return 1; }
}

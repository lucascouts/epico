#!/usr/bin/env bats
# epico-depdiff, slice 1.4: a new dependency is covered by each ADR under adr/
# or docs/adr/ at the head revision whose text names it whole, case-insensitive.

bats_require_minimum_version 1.5.0

setup() { . "$BATS_TEST_DIRNAME/lib/depdiff-fixture.sh"; depdiff_fixture_setup; }

teardown() { rm -rf "$R" ${O:+"$O"} ${N:+"$N"}; }

@test "1.4: a longer name never covers a shorter one it starts with or ends with" {
  put package.json <<'EOF'
{"dependencies": {"react": "18", "@scope/pkg": "1"}}
EOF
  put Cargo.toml <<'EOF'
[dependencies]
serde = "1"
EOF
  put go.mod <<'EOF'
module example.com/app

require github.com/pkg/errors v0.9.1
EOF
  put adr/0001-libraries.md <<'EOF'
# Libraries

We render with react-dom, call the API through @scope/pkg-extra and the bare pkg
helper, encode with serde_json, and wrap errors with github.com/pkg/errors/v2.
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  adr_dir_is '["adr"]'
  printf '%s' "$output" | jq -e '.new | length == 4 and all(.covered_by == [])' > /dev/null
  [ "$(uncovered_names)" = "@scope/pkg,github.com/pkg/errors,react,serde" ] \
    || { echo "uncovered: $(uncovered_names)"; return 1; }
}

@test "1.4: case, backticks, punctuation and a sentence-ending period still cover; name.js does not" {
  put package.json <<'EOF'
{"dependencies": {"react": "18", "@scope/pkg": "1", "vue": "3"}}
EOF
  put go.mod <<'EOF'
module example.com/app

require github.com/pkg/errors v0.9.1
EOF
  put docs/adr/0002-stack.md <<'EOF'
# Stack

We chose React for the UI and `@Scope/Pkg`, for the API client.
The admin page stays on vue.js for now.
Errors are wrapped with github.com/pkg/errors.
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  adr_dir_is '["docs/adr"]'
  [ "$(covered_by_of react)" = "docs/adr/0002-stack.md" ]
  [ "$(covered_by_of @scope/pkg)" = "docs/adr/0002-stack.md" ]
  [ "$(covered_by_of github.com/pkg/errors)" = "docs/adr/0002-stack.md" ]
  [ "$(covered_by_of vue)" = "" ]
  [ "$(uncovered_names)" = "vue" ] || { echo "uncovered: $(uncovered_names)"; return 1; }
}

@test "1.4: an ADR only in the working tree or the index covers nothing" {
  put package.json <<'EOF'
{"dependencies": {"left-pad": "1"}}
EOF
  snapshot head > /dev/null
  put adr/0001-left-pad.md <<'EOF'
We use left-pad.
EOF
  put docs/adr/0002-left-pad.md <<'EOF'
We use left-pad.
EOF
  git -C "$R" add docs/adr/0002-left-pad.md
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  adr_dir_is null
  [ "$(covered_by_of left-pad)" = "" ]
  [ "$(uncovered_names)" = "left-pad" ]
}

@test "1.4: adr/ and docs/adr/ are both read and named; two ADRs naming one dependency both cover it" {
  put package.json <<'EOF'
{"dependencies": {"left-pad": "1"}}
EOF
  put adr/0001-padding.md <<'EOF'
Padding is done by left-pad.
EOF
  put docs/adr/0003-padding-again.md <<'EOF'
LEFT-PAD stays.
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  adr_dir_is '["adr","docs/adr"]'
  [ "$(covered_by_of left-pad)" = "adr/0001-padding.md,docs/adr/0003-padding-again.md" ] \
    || { echo "covered_by: $(covered_by_of left-pad)"; return 1; }
  [ "$(uncovered_names)" = "" ]
}

@test "1.4: a README or a non-markdown file under adr/ naming the dependency does not cover it" {
  put package.json <<'EOF'
{"dependencies": {"left-pad": "1"}}
EOF
  put README.md <<'EOF'
This project uses left-pad.
EOF
  put adr/0001-unrelated.md <<'EOF'
We deploy on Fridays.
EOF
  put adr/notes.txt <<'EOF'
left-pad
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  adr_dir_is '["adr"]'
  [ "$(covered_by_of left-pad)" = "" ]
  [ "$(uncovered_names)" = "left-pad" ]
}

@test "1.4: with no ADR directory adr_dir is null and every new dependency is uncovered" {
  put package.json <<'EOF'
{"dependencies": {"left-pad": "1"}}
EOF
  put requirements.txt <<'EOF'
requests
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  adr_dir_is null
  [ "$(uncovered_names)" = "left-pad,requests" ]
  printf '%s' "$output" | jq -e '.uncovered == .new' > /dev/null
}

@test "1.4: one runtime and one dev dependency: only the runtime one, uncovered, then covered once an ADR lands" {
  put package.json <<'EOF'
{"dependencies": {"express": "4"}, "devDependencies": {"jest": "29"}}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "package.json express"
  [ "$(uncovered_names)" = "express" ]

  put adr/0001-http-server.md <<'EOF'
# Use Express for the HTTP server
EOF
  snapshot adr > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "package.json express"
  [ "$(covered_by_of express)" = "adr/0001-http-server.md" ]
  [ "$(uncovered_names)" = "" ]
}

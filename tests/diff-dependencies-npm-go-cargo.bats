#!/usr/bin/env bats
# epico-depdiff, slice 1.2: the runtime names of package.json, go.mod and
# Cargo.toml, diffed per manifest path, on real temporary git repositories.

bats_require_minimum_version 1.5.0

setup() { . "$BATS_TEST_DIRNAME/lib/depdiff-fixture.sh"; depdiff_fixture_setup; }

teardown() { rm -rf "$R" ${O:+"$O"} ${N:+"$N"}; }

@test "1.2: package.json dependencies and optionalDependencies are new, dev and peer are not" {
  put package.json <<'EOF'
{"name": "app",
 "dependencies": {"express": "^4.18.0"},
 "optionalDependencies": {"fsevents": "^2.3.0"},
 "devDependencies": {"jest": "^29.0.0"},
 "peerDependencies": {"react": "^18.0.0"}}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  new_is "package.json express" "package.json fsevents"
  printf '%s' "$output" | jq -e '.new | all(.ecosystem == "npm" and .covered_by == [])' > /dev/null
}

@test "1.2: go.mod single-line and block require are new, // indirect is not" {
  put go.mod <<'EOF'
module example.com/app

go 1.22
EOF
  B=$(snapshot base)
  put go.mod <<'EOF'
module example.com/app

go 1.22

require github.com/a/one v1.0.0
require github.com/d/four v1.0.0 // indirect

require (
	github.com/b/two v1.2.0
	github.com/c/three v0.3.0 // indirect
	"example.com/quoted" v0.1.0 // a comment that is not indirect
)

replace github.com/b/two => ../two
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is "go.mod example.com/quoted" "go.mod github.com/a/one" "go.mod github.com/b/two"
  printf '%s' "$output" | jq -e '.new | all(.ecosystem == "go")' > /dev/null
}

@test "1.2: Cargo [dependencies] in both forms and [target.*.dependencies] are new, dev and build are not" {
  put Cargo.toml <<'EOF'
[package]
name = "app"
version = "0.1.0"
EOF
  B=$(snapshot base)
  put Cargo.toml <<'EOF'
[package]
name = "app"
version = "0.1.0"

[dependencies]
serde = "1"
tokio = { version = "1", features = ["full"] } # trailing comment

[target.'cfg(unix)'.dependencies]
nix = "0.27"

[dev-dependencies]
proptest = "1"

[build-dependencies]
cc = "1"

[target.'cfg(unix)'.dev-dependencies]
mockall = "0.12"
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is "Cargo.toml nix" "Cargo.toml serde" "Cargo.toml tokio"
  printf '%s' "$output" | jq -e '.new | all(.ecosystem == "cargo")' > /dev/null
}

@test "1.2: a Cargo [dependencies.<name>] table is new, a [dev-dependencies.<name>] table is not" {
  put Cargo.toml <<'EOF'
[package]
name = "app"

[dependencies.rand]
version = "0.8"
features = ["small_rng"]

[dev-dependencies.criterion]
version = "0.5"
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "Cargo.toml rand"
}

@test "1.2: a version bump and a removal are not new" {
  put package.json <<'EOF'
{"dependencies": {"left-pad": "1.0.0", "is-odd": "1.0.0"}}
EOF
  put go.mod <<'EOF'
module example.com/app

require github.com/pkg/errors v0.8.0
EOF
  B=$(snapshot base)
  put package.json <<'EOF'
{"dependencies": {"left-pad": "1.3.0"}}
EOF
  put go.mod <<'EOF'
module example.com/app

require github.com/pkg/errors v0.9.1
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is
}

@test "1.2: a manifest missing at the base reports every runtime name it has" {
  put Cargo.toml <<'EOF'
[dependencies]
anyhow = "1"
clap = { version = "4" }
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "Cargo.toml anyhow" "Cargo.toml clap"
}

@test "1.2: a name already in one package.json is new in another, under that manifest" {
  put packages/a/package.json <<'EOF'
{"dependencies": {"lodash": "4"}}
EOF
  B=$(snapshot base)
  put packages/b/package.json <<'EOF'
{"dependencies": {"lodash": "4"}}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is "packages/b/package.json lodash"
}

@test "1.2: a move from dependencies to optionalDependencies is not new; a dev dependency promoted is" {
  put package.json <<'EOF'
{"dependencies": {"chokidar": "3"}, "devDependencies": {"zod": "3"}}
EOF
  B=$(snapshot base)
  put package.json <<'EOF'
{"optionalDependencies": {"chokidar": "3"}, "dependencies": {"zod": "3"}}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  new_is "package.json zod"
}

@test "1.2: a manifest at depth is read" {
  put services/api/internal/go.mod <<'EOF'
module example.com/api

require (
	github.com/go-chi/chi/v5 v5.0.0
)
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "services/api/internal/go.mod github.com/go-chi/chi/v5"
}

@test "1.2: manifests under node_modules/ and vendor/ are ignored, at any depth" {
  put node_modules/left-pad/package.json <<'EOF'
{"dependencies": {"from-node-modules": "1"}}
EOF
  put web/node_modules/x/package.json <<'EOF'
{"dependencies": {"from-nested-node-modules": "1"}}
EOF
  put vendor/github.com/x/y/go.mod <<'EOF'
module github.com/x/y

require github.com/from/vendor v1.0.0
EOF
  put app/vendor/z/Cargo.toml <<'EOF'
[dependencies]
from-nested-vendor = "1"
EOF
  # A directory merely named like one is not skipped: only the whole component.
  put vendored/package.json <<'EOF'
{"dependencies": {"kept": "1"}}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "vendored/package.json kept"
}

@test "1.2: invalid JSON at the base or at the head goes to unparsed, none of its names new" {
  put package.json <<'EOF'
{"dependencies": {"a": "1",}}
EOF
  put web/package.json <<'EOF'
{"dependencies": {"b": "1"}}
EOF
  B=$(snapshot base)
  put package.json <<'EOF'
{"dependencies": {"a": "1", "c": "1"}}
EOF
  put web/package.json <<'EOF'
{"dependencies": {"b": "1", "d": "1"
EOF
  put other/package.json <<'EOF'
{"dependencies": {"e": "1"}}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$B"
  [ "$status" -eq 0 ]
  one_object
  new_is "other/package.json e"
  [ "$(unparsed_manifests)" = "$(printf 'package.json\nweb/package.json')" ] \
    || { echo "unparsed: $(unparsed_manifests)"; return 1; }
  # Each entry says why.
  printf '%s' "$output" | jq -e '.unparsed | all((.reason | type) == "string" and (.reason | length) > 0)' > /dev/null
}

@test "1.2: a dependencies field that is not an object goes to unparsed" {
  put package.json <<'EOF'
{"dependencies": ["left-pad"]}
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is
  [ "$(unparsed_manifests)" = "package.json" ]
}

@test "1.2: an unclosed go.mod require block and a Cargo line that is not key = value go to unparsed" {
  put go.mod <<'EOF'
module example.com/app

require (
	github.com/a/one v1.0.0
EOF
  put Cargo.toml <<'EOF'
[dependencies]
serde = "1"
this is not toml
EOF
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is
  [ "$(unparsed_manifests)" = "$(printf 'Cargo.toml\ngo.mod')" ] \
    || { echo "unparsed: $(unparsed_manifests)"; return 1; }
  printf '%s' "$output" | jq -e '[.unparsed[].reason] | any(contains("this is not toml"))' > /dev/null
}


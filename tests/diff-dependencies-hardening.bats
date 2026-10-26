#!/usr/bin/env bats
# epico-depdiff, the Tech Review's findings on slices 1.2–1.4: a name that
# could forge an output field, a diff too large for one command line, and the
# Cargo and Gemfile shapes the first parsers misread. Real temporary git
# repositories, as in the other diff-dependencies suites.

bats_require_minimum_version 1.5.0

setup() { . "$BATS_TEST_DIRNAME/lib/depdiff-fixture.sh"; depdiff_fixture_setup; }

teardown() { rm -rf "$R"; }

@test "review M1: a key with a tab or a newline sends the manifest to unparsed, forging no entry" {
  printf '{"dependencies": {"evil\\tcargo\\tfake/path": "1", "ok": "1"}}\n' | put package.json
  printf '{"require": {"a/b\\nc/d": "1"}}\n' | put composer.json
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  new_is
  [ "$(unparsed_manifests | tr '\n' ' ')" = "composer.json package.json " ]
}

@test "review M1: a quoted TOML key with a tab sends Cargo.toml to unparsed" {
  printf '[dependencies]\n"evil\tcargo" = "1"\nserde = "1"\n' | put Cargo.toml
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is
  [ "$(unparsed_manifests)" = "Cargo.toml" ]
}

@test "review M2: 3000 new dependencies still print one JSON object and exit 0" {
  jq -n '{dependencies: ([range(3000) | {key: "package-with-a-long-name-\(.)", value: "1"}] | from_entries)}' | put package.json
  mkdir -p "$R/adr"
  printf '# Use package-with-a-long-name-42\n' | put adr/0001-dep.md
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  [ "$(printf '%s' "$output" | jq '.new | length')" -eq 3000 ]
  [ "$(printf '%s' "$output" | jq '.uncovered | length')" -eq 2999 ]
  [ "$(covered_by_of package-with-a-long-name-42)" = "adr/0001-dep.md" ]
}

@test "review L1: a Cargo inline table whose array spans lines is read, not unparsed" {
  put Cargo.toml <<'TOML'
[dependencies]
tokio = { version = "1", features = [
  "full",
  "macros",
] }
serde = "1"
TOML
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "Cargo.toml serde" "Cargo.toml tokio"
  [ "$(printf '%s' "$output" | jq '.unparsed | length')" -eq 0 ]
}

@test "review L2: a renamed Cargo dependency is reported by its crate, inline and table form" {
  put Cargo.toml <<'TOML'
[dependencies]
web = { package = "actix-web", version = "4" }
rt = { version = "1", features = [
  "full",
], package = "tokio" }

[dependencies.json]
version = "1"
package = "serde_json"
TOML
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "Cargo.toml actix-web" "Cargo.toml serde_json" "Cargo.toml tokio"
}

@test "review L3: a Gemfile group header continued on the next line is still a dev group" {
  put Gemfile <<'RUBY'
source "https://rubygems.org"
group :development,
      :test do
  gem "pry"
end
gem "rack",
    "~> 3.0"
gem "rspec",
    group: :test
RUBY
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "Gemfile rack"
}

@test "review N1: a comment naming a package never renames a Cargo dependency" {
  put Cargo.toml <<'TOML'
[dependencies]
leftpad-rs = "0.2" # replaces package = "serde" helpers
rt = { version = "1", features = [ # package = "nope"
  "full",
], package = "tokio" }
TOML
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "Cargo.toml leftpad-rs" "Cargo.toml tokio"
}

@test "review M1-a: a tab in one name among a large list still sends the manifest to unparsed" {
  # Every 50th name holds a tab, so one lands inside the first pipe buffer
  # whatever order awk prints its array in — mawk and gawk differ there.
  { for i in $(seq 1 12000); do
      if [ $((i % 50)) -eq 0 ]; then printf 'gem "evil-%s\tcargo\tforged/path"\n' "$i"
      else printf 'gem "gem-number-%s"\n' "$i"; fi
    done; } | put Gemfile
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is
  [ "$(unparsed_manifests)" = "Gemfile" ]
}

@test "review M1-b: a tab or a newline in a manifest or ADR path forges no field" {
  printf '{"dependencies": {"right-pad": "1"}}\n' | put $'we\tird/package.json'
  printf '{"dependencies": {"left-pad": "1"}}\n' | put $'new\nline/package.json'
  printf 'We chose right-pad.\n' | put $'adr/0001\tpick.md'
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  one_object
  [ "$(printf '%s' "$output" | jq -r --arg m $'we\tird/package.json' '.new[] | select(.manifest == $m) | .name')" = right-pad ]
  [ "$(printf '%s' "$output" | jq -r --arg m $'new\nline/package.json' '.new[] | select(.manifest == $m) | .name')" = left-pad ]
  [ "$(printf '%s' "$output" | jq -r '.new[] | select(.name == "right-pad") | .covered_by[0]')" = $'adr/0001\tpick.md' ]
  [ "$(printf '%s' "$output" | jq '.unparsed | length')" -eq 0 ]
}

@test "review N2: no usable temporary directory is a refusal with its reason in the JSON" {
  TMPDIR="$R/no-such-dir" depdiff_run --base "$BASE"
  [ "$status" -eq 1 ]
  one_object
  reason_names "temporary"
}

@test "review N3: an ADR whose object is missing is a refusal with its reason in the JSON" {
  printf '{"dependencies": {"left-pad": "1"}}\n' | put package.json
  printf 'We chose left-pad.\n' | put adr/0001-pick.md
  snapshot head > /dev/null
  obj=$(git -C "$R" rev-parse HEAD:adr/0001-pick.md)
  rm -f "$R/.git/objects/${obj:0:2}/${obj:2}"
  depdiff_run --base "$BASE"
  [ "$status" -eq 1 ]
  one_object
  reason_names "adr/0001-pick.md"
}

@test "review note 1: package = inside a string value never renames a Cargo dependency" {
  put Cargo.toml <<'TOML'
[dependencies]
evil-a = { version = "1", features = [" package = 'serde'"] }
evil-b = { version = "1", features = [
  "package = \"tokio\"",
] }
TOML
  snapshot head > /dev/null
  depdiff_run --base "$BASE"
  [ "$status" -eq 0 ]
  new_is "Cargo.toml evil-a" "Cargo.toml evil-b"
}

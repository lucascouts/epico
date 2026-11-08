#!/usr/bin/env bats
# tests/run-suite.sh is the one command that runs every test: one bats process
# per file, several at once, with nothing beyond bats and xargs (GNU parallel,
# which `bats --jobs` needs, is not assumed). Measured 2026-11-08 on 32 cores:
# 96 s in one process, about 20 s per file in parallel once archive-story.bats
# was split by subject. It must run every file, add the results up, and fail —
# naming the file — when any case fails. It is exercised on scratch suites here,
# never on tests/ itself, which would run this file inside itself.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  WORK=$(mktemp -d)
  printf '@test "a" { true; }\n@test "b" { true; }\n' > "$WORK/one.bats"
  printf '@test "c" { true; }\n' > "$WORK/two.bats"
}

teardown() { rm -rf "$WORK"; }

@test "runs every file and adds the results up" {
  run bash "$ROOT/tests/run-suite.sh" "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 ok, 0 not ok, 2 files"* ]]
}

@test "a failing case fails the run and names its file" {
  printf '@test "d" { false; }\n' > "$WORK/three.bats"
  run bash "$ROOT/tests/run-suite.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"3 ok, 1 not ok, 3 files"* ]]
  [[ "$output" == *"three.bats"* ]]
  [[ "$output" == *'not ok 1 d'* ]]
}

@test "a file bats cannot even load fails the run too" {
  printf '@test "broken {\n' > "$WORK/broken.bats"
  run bash "$ROOT/tests/run-suite.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken.bats"* ]]
}

@test "JOBS sets how many files run at once, and a bad value is refused" {
  run env JOBS=1 bash "$ROOT/tests/run-suite.sh" "$WORK"
  [ "$status" -eq 0 ]
  run env JOBS=many bash "$ROOT/tests/run-suite.sh" "$WORK"
  [ "$status" -eq 2 ]
}

#!/usr/bin/env bats
# Contract tests for scripts/archive-story.sh: the weight and binary guard.
# The contract and the fixtures are in tests/lib/archive-story-common.sh.

bats_require_minimum_version 1.5.0
. "$BATS_TEST_DIRNAME/lib/archive-story-common.sh"

# --- Weight/binary guard ---

@test "text file over 10 MB blocks with the offender listed" {
  make_story 005-heavy complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485761 > "$PROJ/.epico/stories/005-heavy/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-heavy
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '(.guard.violations | length) >= 1' > /dev/null
  echo "$output" | grep -q 'big.txt'
  [ -d "$PROJ/.epico/stories/005-heavy" ]
  [ ! -d "$PROJ/.epico/archive/005-heavy" ]
}

@test "text file at exactly 10485760 bytes passes the weight guard" {
  make_story 005-boundary complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485760 > "$PROJ/.epico/stories/005-boundary/edge.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-boundary
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-boundary" ]
}

@test "an image of at most 2 MB under proof/ passes; a larger one, or one outside proof/, blocks" {
  make_story 005-proof complete
  mkdir -p "$PROJ/.epico/stories/005-proof/proof"
  { printf '\x89PNG\r\n\x1a\n\0'; head -c 2097143 /dev/zero; } > "$PROJ/.epico/stories/005-proof/proof/login.png"
  [ "$(wc -c < "$PROJ/.epico/stories/005-proof/proof/login.png")" -eq 2097152 ]
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-proof
  [ "$status" -eq 0 ]
  [ -f "$PROJ/.epico/archive/005-proof/proof/login.png" ]

  make_story 006-proof-big complete
  mkdir -p "$PROJ/.epico/stories/006-proof-big/proof"
  head -c 2097153 /dev/zero > "$PROJ/.epico/stories/006-proof-big/proof/big.jpg"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/006-proof-big
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'big.jpg'
  echo "$output" | grep -q '2 MB'

  make_story 007-loose complete
  printf '\x89PNG\0' > "$PROJ/.epico/stories/007-loose/shot.png"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/007-loose
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'shot.png'
}

@test "NUL-containing file blocks as non-text" {
  make_story 005-binary complete
  printf 'ab\0cd' > "$PROJ/.epico/stories/005-binary/blob.dat"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-binary
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | grep -q 'blob.dat'
  [ ! -d "$PROJ/.epico/archive/005-binary" ]
}

@test "--allow-heavy archives and records the override" {
  make_story 005-allowed complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485761 > "$PROJ/.epico/stories/005-allowed/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-allowed --allow-heavy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-allowed" ]
  # The override is recorded in the manifest entry.
  grep -q 'allow-heavy' "$MANIFEST"
}

@test "a node_modules/ tree blocks once, naming the directory, whatever its files weigh" {
  make_story 005-deps complete
  local story="$PROJ/.epico/stories/005-deps"
  mkdir -p "$story/node_modules/left-pad" "$story/node_modules/.bin"
  echo 'module.exports = () => 1' > "$story/node_modules/left-pad/index.js"
  echo '{"name":"left-pad"}' > "$story/node_modules/left-pad/package.json"
  echo '#!/bin/sh' > "$story/node_modules/.bin/pad"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-deps
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  # The tree is the offender: one violation, not one per file (three files here).
  echo "$output" | jq -e '(.guard.violations | length) == 1' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].file | endswith("node_modules/")' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].reason | contains("node_modules")' > /dev/null
  # Refused, never deleted: the tree is still there for the user to remove.
  [ -f "$story/node_modules/left-pad/index.js" ]
  [ ! -d "$PROJ/.epico/archive/005-deps" ]
}

@test "--allow-heavy archives a node_modules/ tree as it is and records the override" {
  make_story 005-deps-allowed complete
  local story="$PROJ/.epico/stories/005-deps-allowed"
  mkdir -p "$story/node_modules/left-pad"
  echo 'module.exports = () => 1' > "$story/node_modules/left-pad/index.js"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-deps-allowed --allow-heavy
  [ "$status" -eq 0 ]
  [ -f "$PROJ/.epico/archive/005-deps-allowed/node_modules/left-pad/index.js" ]
  grep -q 'allow-heavy' "$MANIFEST"
}

@test "every offending file is listed, not just the first" {
  # The guard lists EVERY offending file. A guard that stops at the first one
  # turns a clean-up into a game of whack-a-mole: block, delete, block again.
  make_story 005-many complete
  local story="$PROJ/.epico/stories/005-many"
  yes 'padding line for the weight guard fixture' | head -c 10485761 > "$story/first.txt"
  yes 'padding line for the weight guard fixture' | head -c 10485762 > "$story/second.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-many
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '(.guard.violations | length) == 2' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file | endswith("first.txt")] | any' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file | endswith("second.txt")] | any' > /dev/null
  # The human reason carries both too - it is what the orchestrator surfaces.
  echo "$output" | jq -e '.reason | contains("first.txt") and contains("second.txt")' > /dev/null
  [ ! -d "$PROJ/.epico/archive/005-many" ]
}

@test "each violation carries the offending file's size and its reason" {
  # Each offender carries its size AND its reason. The size as a NUMBER in a field,
  # not a figure a consumer has to fish back out of a prose sentence.
  make_story 005-sized complete
  yes 'padding line for the weight guard fixture' \
    | head -c 10485761 > "$PROJ/.epico/stories/005-sized/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-sized
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.guard.violations[0]
    | has("file") and has("size") and has("reason")' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].size == 10485761' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].size | type == "number"' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].reason | test("larger than")' > /dev/null
  # The prose list states the size as well, so a human reading only `reason`
  # learns by how much the file missed.
  echo "$output" | jq -e '.reason | contains("10485761")' > /dev/null
}

@test "a file inside .draft/ is scanned like any other" {
  # The guard walks the whole story tree: a blob is no lighter for sitting one
  # directory down, and .draft/ is where a story's evidence accumulates.
  make_story 005-draftblob complete
  mkdir -p "$PROJ/.epico/stories/005-draftblob/.draft/logs"
  printf 'core\0dump' > "$PROJ/.epico/stories/005-draftblob/.draft/logs/crash.dump"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-draftblob
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file
    | endswith(".draft/logs/crash.dump")] | any' > /dev/null
  [ -d "$PROJ/.epico/stories/005-draftblob" ]
  [ ! -d "$PROJ/.epico/archive/005-draftblob" ]
}

@test "a UTF-16 text artifact is blocked as non-text, with --allow-heavy as the escape" {
  # Pinned as a decision rather than left to be rediscovered: a UTF-16 file is real text, and it IS reported as binary,
  # because every ASCII-range character it holds carries a NUL byte.
  # Kept deliberately. A BOM exemption would miss BOM-less UTF-16 anyway AND
  # hand any 2.3 GB blob a two-byte prefix that buys it a free pass - the exact
  # hole this guard exists to close. So the verdict has to EXPLAIN itself, and
  # --allow-heavy is the recorded escape.
  make_story 005-utf16 complete
  python3 -c '
import sys
open(sys.argv[1], "wb").write("# Notes\nplain readable text\n".encode("utf-16-le"))
' "$PROJ/.epico/stories/005-utf16/notes-utf16.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-utf16
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file
    | endswith("notes-utf16.md")] | any' > /dev/null
  # The reason names the edge, so nobody has to guess why a text file is binary.
  echo "$output" | jq -e '.guard.violations[0].reason | test("UTF-16")' > /dev/null
  # ...and the documented way out works, recorded as an override.
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-utf16 --allow-heavy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-utf16" ]
  grep -q 'allow-heavy' "$MANIFEST"
}

@test "an empty file and a newline-only file are text, not binary" {
  # `grep -qI .` finds no character on either of them, so reading its exit code
  # as "binary" would block a clean story over an empty placeholder - the guard
  # failing in the direction that costs trust rather than safety.
  make_story 005-emptyish complete
  : > "$PROJ/.epico/stories/005-emptyish/.gitkeep"
  printf '\n\n\n' > "$PROJ/.epico/stories/005-emptyish/blank-lines.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-emptyish
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.guard.violations | length) == 0' > /dev/null
  [ -d "$PROJ/.epico/archive/005-emptyish" ]
}

@test "a blocked story leaves no manifest entry and no archive directory" {
  # The step order, asserted from the outside: the guard runs BEFORE the append
  # (step 5) and the move (step 6). A blocked story that had already been
  # written into the permanent record would be a record of an archive that
  # never happened - and .epico/archive/ is deliberately hard to repair.
  make_story 005-nowrite complete
  printf 'ab\0cd' > "$PROJ/.epico/stories/005-nowrite/blob.dat"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-nowrite
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.manifest_entry == {}' > /dev/null
  [ ! -e "$MANIFEST" ]
  [ ! -d "$PROJ/.epico/archive" ]
  [ -f "$PROJ/.epico/stories/005-nowrite/story.md" ]
  [ -f "$PROJ/.epico/stories/005-nowrite/blob.dat" ]
}

@test "a file the guard cannot read is a reported verdict, not a silent abort" {
  # `[[ -f ]]` says a file EXISTS, not that it opens. A `grep` that fails on an
  # unreadable file exits 2, and taking that for "no match, therefore text"
  # would clear a file nobody inspected; letting it abort under `set -e` would
  # end the run with zero bytes on stdout, which the output contract promises
  # never happens. Fail closed, with JSON, naming the file.
  make_story 005-opaque complete
  printf 'plain readable text\n' > "$PROJ/.epico/stories/005-opaque/opaque.txt"
  chmod 000 "$PROJ/.epico/stories/005-opaque/opaque.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-opaque
  # `|| true`: if the guard ever stops blocking, the story is MOVED and this
  # path is gone - and the case must then fail on its assertion, not die here
  # on the fixture cleanup. (teardown chmods the whole work tree anyway.)
  chmod 644 "$PROJ/.epico/stories/005-opaque/opaque.txt" 2> /dev/null || true
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].file | endswith("opaque.txt")] | any' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].reason | test("cannot be read")' > /dev/null
  [ -d "$PROJ/.epico/stories/005-opaque" ]
  [ ! -d "$PROJ/.epico/archive/005-opaque" ]
}

@test "a tree the guard cannot fully enumerate blocks instead of passing" {
  # The quiet way for a guard to fail is to pass on a tree it never saw: a
  # directory it cannot descend into makes `find` exit non-zero AFTER printing
  # the files it did reach, and a scan that reads only the output would clear a
  # story on the strength of a partial list. Same rule as everywhere else here -
  # what the guard cannot see, it cannot clear.
  make_story 005-locked complete
  mkdir -p "$PROJ/.epico/stories/005-locked/.draft/locked"
  printf 'ab\0cd' > "$PROJ/.epico/stories/005-locked/.draft/locked/hidden.dat"
  chmod 000 "$PROJ/.epico/stories/005-locked/.draft/locked"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-locked
  chmod 755 "$PROJ/.epico/stories/005-locked/.draft/locked" 2> /dev/null || true
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '[.guard.violations[].reason
    | test("cannot enumerate")] | any' > /dev/null
  [ -d "$PROJ/.epico/stories/005-locked" ]
  [ ! -d "$PROJ/.epico/archive/005-locked" ]
}

@test "a 2 GB-class binary is blocked with the offender and its size listed" {
  # A multi-GB binary must be refused. The fixture is sparse, so it costs no disk - and
  # the guard must not have to READ it to refuse it (size first, then text).
  make_story 005-huge-binary complete
  truncate -s 2469606195 "$PROJ/.epico/stories/005-huge-binary/vendor-blob.bin"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-huge-binary
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '.guard.violations[0].size == 2469606195' > /dev/null
  echo "$output" | grep -q 'vendor-blob.bin'
  # It is refused for its WEIGHT, and that assertion is what makes this case a
  # discriminator: a sparse file is all NUL bytes, so a guard that read it first
  # would block it as "non-text" and look just as correct while the 10 MB rule
  # sat broken. The size test runs first precisely so 2.3 GB is never read.
  echo "$output" | jq -e '.guard.violations[0].reason | test("larger than")' > /dev/null
  [ -d "$PROJ/.epico/stories/005-huge-binary" ]
  [ ! -d "$PROJ/.epico/archive/005-huge-binary" ]
}


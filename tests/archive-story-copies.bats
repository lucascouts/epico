#!/usr/bin/env bats
# Contract tests for scripts/archive-story.sh: byte-identical draft copies.
# The contract and the fixtures are in tests/lib/archive-story-common.sh.

bats_require_minimum_version 1.5.0
. "$BATS_TEST_DIRNAME/lib/archive-story-common.sh"

# --- Byte-identical draft copies ---

@test "byte-identical draft copy is removed and differing copy kept" {
  make_story 005-copies complete
  local story="$PROJ/.epico/stories/005-copies"
  mkdir -p "$story/.draft"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"          # identical
  echo 'promoted notes v2' > "$story/notes.md"
  echo 'draft notes v1' > "$story/.draft/notes.md"          # differs
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-copies
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-copies"
  [ ! -e "$arch/.draft/design.md" ]
  [ -f "$arch/.draft/notes.md" ]
  grep -q 'draft notes v1' "$arch/.draft/notes.md"
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
}

@test "--keep-copies preserves the duplicate and records the override" {
  make_story 005-keepcopies complete
  local story="$PROJ/.epico/stories/005-keepcopies"
  mkdir -p "$story/.draft"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-keepcopies --keep-copies
  [ "$status" -eq 0 ]
  [ -f "$PROJ/.epico/archive/005-keepcopies/.draft/design.md" ]
  # The override is recorded.
  grep -q 'keep-copies' "$MANIFEST"
}

# `--keep-copies preserves the duplicate` alone cannot tell "the flag was
# honoured" from "nothing prunes"; the prune cases below are what make it a
# discriminator.

# make_copy_story <dir-name> - a COMPLETE story with an empty .draft/ ready for
# the fixture's own files. Echoes nothing; the caller writes the pairs it needs.
make_copy_story() {
  make_story "$1" complete
  mkdir -p "$PROJ/.epico/stories/$1/.draft"
}

@test "a story blocked by the weight guard keeps every .draft copy" {
  # THE STEP ORDER, asserted from outside the script, for the COPIES half. The
  # log-pruning cases pin it for the logs half, and step 4 is destructive on
  # both: a copies
  # prune that ran before the guards would delete files for a story that is then
  # refused - and unlike the logs half it writes no summary, so the only record
  # that the file ever existed would be gone with it.
  make_copy_story 005-blockedcopies
  local story="$PROJ/.epico/stories/005-blockedcopies"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  yes 'padding line for the weight guard fixture' | head -c 10485761 > "$story/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-blockedcopies
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # The exact copy is still exactly where it was...
  [ -f "$story/.draft/design.md" ]
  grep -q 'promoted design body' "$story/.draft/design.md"
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # ...and the copies prune never announced itself at all. (`[[ != ]]`, not
  # `! grep`: an inverted command is exempt from set -e - see the note in the
  # secrets guard's no-secret-material case.)
  [[ "$stderr" != *"prune=copies"* ]]
}

@test "the copies prune reports itself after both guards and after the logs prune" {
  # The other half of the pair: the case above proves the copies prune does not
  # run when a guard blocks; this proves that when it DOES run, it runs last -
  # after both guards AND after the logs half, which is the order the summary it
  # must not delete depends on. All four verdicts are key=value lines on stderr,
  # so the ORDER is readable without parsing prose, and `guards_passed=true` is
  # the script's own sequence assertion stated where a test can see it.
  make_copy_story 005-order-copies
  local story="$PROJ/.epico/stories/005-order-copies"
  mkdir -p "$story/.draft/logs"
  seq 1 500 > "$story/.draft/logs/build.log"
  echo 'promoted design body' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-order-copies
  [ "$status" -eq 0 ]
  local weight secrets logs copies
  weight=$(echo "$stderr" | grep -n 'guard=weight-binary' | head -1 | cut -d: -f1)
  secrets=$(echo "$stderr" | grep -n 'guard=secrets' | head -1 | cut -d: -f1)
  logs=$(echo "$stderr" | grep -n 'prune=logs' | head -1 | cut -d: -f1)
  copies=$(echo "$stderr" | grep -n 'prune=copies' | head -1 | cut -d: -f1)
  [ -n "$weight" ]
  [ -n "$secrets" ]
  [ -n "$logs" ]
  [ -n "$copies" ]
  [ "$copies" -gt "$weight" ]
  [ "$copies" -gt "$secrets" ]
  [ "$copies" -gt "$logs" ]
  echo "$stderr" | grep -q 'prune=copies verdict=pruned.*guards_passed=true'
}

@test "a near-duplicate survives - one byte, one newline, or the same length" {
  # THE load-bearing word is "byte-identical". A near-duplicate is a
  # DIFFERENT DOCUMENT - usually the working draft the promoted artifact grew out
  # of, which is exactly what a reader opens .draft/ for. Three shapes, because
  # the plausible wrong implementations each miss a different one: comparing
  # sizes passes the two same-length pairs, and comparing "the first line" or a
  # trimmed form passes the trailing-newline pair.
  make_copy_story 005-near
  local story="$PROJ/.epico/stories/005-near" d="$PROJ/.epico/stories/005-near/.draft"
  printf 'duplicate detection\n' > "$story/onebyte.md"
  printf 'duplicate detectiom\n' > "$d/onebyte.md"        # one byte changed
  printf 'trailing newline matters\n' > "$story/newline.md"
  printf 'trailing newline matters' > "$d/newline.md"     # one byte shorter
  printf 'AAAA\n' > "$story/samesize.md"
  printf 'BBBB\n' > "$d/samesize.md"                      # same length, other bytes
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-near
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-near"
  [ -f "$arch/.draft/onebyte.md" ]
  [ -f "$arch/.draft/newline.md" ]
  [ -f "$arch/.draft/samesize.md" ]
  grep -q 'detectiom' "$arch/.draft/onebyte.md"
  [ "$(cat "$arch/.draft/samesize.md")" = 'BBBB' ]
  # The trailing newline is the difference, so it must still be absent.
  [ "$(wc -c < "$arch/.draft/newline.md")" -eq 24 ]
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # `clean` and not `none`: every draft file WAS compared and none matched.
  echo "$stderr" | grep -q 'prune=copies verdict=clean files_seen=3 compared=3 removed=0'
}

@test "identical bytes are a duplicate whatever the permissions and the mtime say" {
  # Duplicate detection is about CONTENT. A copy someone chmod'ed or touched is still a copy,
  # and metadata equality is neither necessary nor sufficient for it - which is
  # why the comparison is cmp on the bytes and not a stat-based shortcut.
  make_copy_story 005-meta
  local story="$PROJ/.epico/stories/005-meta"
  printf 'promoted body, byte for byte\n' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  chmod 600 "$story/.draft/design.md"
  chmod 644 "$story/design.md"
  touch -d '2020-01-01 00:00' "$story/.draft/design.md"
  touch -d '2026-08-01 12:00' "$story/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-meta
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.epico/archive/005-meta/.draft/design.md" ]
  [ -f "$PROJ/.epico/archive/005-meta/design.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
}

@test "copies_removed is a real count, not a boolean" {
  # The first copies case removes exactly one copy, so a boolean, a constant 1 or a
  # "did anything happen" flag satisfies it identically. Three copies is what
  # tells a count from a flag - and the number has to reach the PERMANENT record,
  # not just stdout.
  make_copy_story 005-three
  local story="$PROJ/.epico/stories/005-three" f
  for f in design research plan; do
    printf 'promoted %s body\n' "$f" > "$story/$f.md"
    cp "$story/$f.md" "$story/.draft/$f.md"
  done
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-three
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-three"
  for f in design research plan; do
    [ ! -e "$arch/.draft/$f.md" ]
    [ -f "$arch/$f.md" ]
  done
  echo "$output" | jq -e '.pruned.copies_removed == 3' > /dev/null
  grep -Eq 'copies_removed:[[:space:]]*3' "$MANIFEST"
}

@test "a .draft file with no promoted sibling is never touched" {
  # This is MOST of .draft/, and it is the failure mode that would hurt worst:
  # "prune the drafts" read as "empty .draft/" destroys the working notes the
  # archive exists to keep. A file that is a copy of nothing can never be a
  # duplicate of anything.
  make_copy_story 005-orphan
  local story="$PROJ/.epico/stories/005-orphan"
  printf 'scratch thinking nobody promoted\n' > "$story/.draft/scratch.md"
  printf 'raw interview notes\n' > "$story/.draft/interview.txt"
  printf 'promoted design body\n' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-orphan
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-orphan"
  [ -f "$arch/.draft/scratch.md" ]
  grep -q 'scratch thinking' "$arch/.draft/scratch.md"
  [ -f "$arch/.draft/interview.txt" ]
  # ...while the one that IS an exact copy went, so this is not "nothing ran".
  [ ! -e "$arch/.draft/design.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
  # 3 files seen, only 1 of them had a promoted artifact to compare against.
  echo "$stderr" | grep -q 'prune=copies verdict=pruned files_seen=3 compared=1 removed=1'
}

@test "a nested draft copy pairs by relative path, never by basename" {
  # THE RULE, pinned in both directions, because getting it wrong deletes a file
  # that was never a duplicate. `.draft/<rel>` pairs with `<story>/<rel>`:
  #   .draft/adr/002.md vs a top-level 002.md  -> NOT a pair (different document
  #                                               that happens to share a name)
  #   .draft/adr/003.md vs adr/003.md          -> a pair, and an exact copy
  # Both fixtures are byte-identical to their would-be partner, so only the
  # PAIRING decides the outcome.
  make_copy_story 005-nested
  local story="$PROJ/.epico/stories/005-nested"
  mkdir -p "$story/.draft/adr" "$story/adr"
  printf 'same bytes, unrelated documents\n' > "$story/002.md"
  printf 'same bytes, unrelated documents\n' > "$story/.draft/adr/002.md"
  printf 'promoted adr three\n' > "$story/adr/003.md"
  cp "$story/adr/003.md" "$story/.draft/adr/003.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-nested
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-nested"
  [ -f "$arch/.draft/adr/002.md" ]
  grep -q 'unrelated documents' "$arch/.draft/adr/002.md"
  [ ! -e "$arch/.draft/adr/003.md" ]
  [ -f "$arch/adr/003.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 1' > /dev/null
}

@test "a draft copy that cannot be read is kept, never assumed identical" {
  # The logs half's rule, and it matters more here: `[[ -f ]]` says a
  # file EXISTS, not that it opens, and reading an unreadable file as a duplicate
  # deletes the one copy nobody was able to check. cmp answers 0/1/>1 and only 0
  # deletes. --allow-heavy is needed to reach step 4 at all - the weight/binary
  # guard blocks an unreadable file first, which is the step order working.
  make_copy_story 005-unreadcopy
  local story="$PROJ/.epico/stories/005-unreadcopy"
  printf 'promoted design body\n' > "$story/design.md"
  cp "$story/design.md" "$story/.draft/design.md"
  chmod 000 "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-unreadcopy --allow-heavy
  # `|| true` on both: whichever side of the move the file ended on, the fixture
  # cleanup must not kill the case before its assertions run.
  chmod 644 "$story/.draft/design.md" 2> /dev/null || true
  chmod 644 "$PROJ/.epico/archive/005-unreadcopy/.draft/design.md" 2> /dev/null || true
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  local arch="$PROJ/.epico/archive/005-unreadcopy"
  [ -f "$arch/.draft/design.md" ]
  grep -q 'promoted design body' "$arch/.draft/design.md"
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # Reported, not silent: the file is named with the reason it was left.
  echo "$stderr" | grep -q 'prune=copies verdict=partial'
  echo "$stderr" | grep -q 'design.md'
}

@test "a draft file whose promoted counterpart is a directory is not a duplicate" {
  # A type mismatch is not a comparison. Both directions: a draft FILE whose
  # promoted path is a DIRECTORY (cmp against a directory is an error, and an
  # error is never "equal"), and a draft DIRECTORY whose promoted path is a FILE
  # (nothing under it maps to anything, so nothing is a candidate).
  make_copy_story 005-typemix
  local story="$PROJ/.epico/stories/005-typemix"
  mkdir -p "$story/adr.md" "$story/.draft/notes.md"
  printf 'promoted adr collection\n' > "$story/adr.md/index.md"
  printf 'draft file where a directory was promoted\n' > "$story/.draft/adr.md"
  printf 'promoted notes body\n' > "$story/notes.md"
  printf 'draft directory where a file was promoted\n' > "$story/.draft/notes.md/inner.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-typemix
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-typemix"
  [ -f "$arch/.draft/adr.md" ]
  [ -f "$arch/.draft/notes.md/inner.md" ]
  [ -f "$arch/adr.md/index.md" ]
  [ -f "$arch/notes.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
  # `clean`, not `partial`: a type mismatch is not even a comparison, so nothing
  # was compared and nothing failed to compare.
  echo "$stderr" | grep -q 'prune=copies verdict=clean files_seen=2 compared=0 removed=0'
}

@test "a symlinked draft copy is left as a link, never deleted" {
  # cmp FOLLOWS symlinks, so a link to the promoted artifact reads as
  # "identical". It is left alone anyway: it holds no bytes of its own, so
  # there is no copy to remove, and a symlink is how someone
  # deliberately wrote down "same file". Two layers keep it safe - `find -type f`
  # never enumerates it, and the loop tests -L again - and only removing BOTH
  # changes the outcome.
  make_copy_story 005-linkcopy
  local story="$PROJ/.epico/stories/005-linkcopy"
  printf 'promoted design body\n' > "$story/design.md"
  ln -s ../design.md "$story/.draft/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-linkcopy
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-linkcopy"
  [ -L "$arch/.draft/design.md" ]
  # ...and it still resolves: -f follows the link.
  [ -f "$arch/.draft/design.md" ]
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
}

@test "a promoted artifact that is a symlink into .draft is never made to dangle" {
  # THE dangerous direction. cmp follows the promoted link, so the pair reads as
  # byte-identical - and deleting the .draft file would leave the promoted
  # artifact pointing at nothing. A removal of a redundant duplicate would have
  # become the destruction of the story's only copy.
  make_copy_story 005-linkpromoted
  local story="$PROJ/.epico/stories/005-linkpromoted"
  printf 'the only copy of this text\n' > "$story/.draft/design.md"
  ln -s .draft/design.md "$story/design.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-linkpromoted
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-linkpromoted"
  [ -f "$arch/.draft/design.md" ]
  # -f on the link is FALSE when it dangles, so this is the no-dangle assertion.
  [ -L "$arch/design.md" ]
  [ -f "$arch/design.md" ]
  grep -q 'the only copy of this text' "$arch/design.md"
  echo "$output" | jq -e '.pruned.copies_removed == 0' > /dev/null
}

@test "the generated logs summary is not deleted by the copies half" {
  # Step 4 runs the logs half FIRST, so .draft/logs-summary.md exists by the time
  # the copies half enumerates the subtree. It has no promoted sibling, so it is
  # inert - and it must stay that way, because it is now the ONLY record of logs
  # this same step deleted moments earlier.
  make_copy_story 005-summarysafe
  local story="$PROJ/.epico/stories/005-summarysafe"
  mkdir -p "$story/.draft/logs"
  { seq 1 300; echo 'SUMMARY SAFE MARKER'; } > "$story/.draft/logs/build.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-summarysafe
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-summarysafe"
  [ -f "$arch/.draft/logs-summary.md" ]
  grep -q 'SUMMARY SAFE MARKER' "$arch/.draft/logs-summary.md"
  [ ! -e "$arch/.draft/logs/build.log" ]
  echo "$output" | jq -e '.pruned.logs_kb > 0 and .pruned.copies_removed == 0' > /dev/null
  # The copies half DID look at it and decided it was not a copy of anything.
  echo "$stderr" | grep -q 'prune=copies verdict=clean files_seen=1 compared=0 removed=0'
}


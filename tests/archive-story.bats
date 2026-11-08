#!/usr/bin/env bats
# Contract tests for scripts/archive-story.sh: the secrets guard, log pruning and
# the log summary. The contract and the fixtures are in
# tests/lib/archive-story-common.sh; the other subjects are in
# tests/archive-story-*.bats. These three stay in this file because their
# AKIA-shaped fixtures are classified in .gitleaksignore under this path.

bats_require_minimum_version 1.5.0
. "$BATS_TEST_DIRNAME/lib/archive-story-common.sh"

# --- Secrets guard ---
# Gated on gitleaks presence; the fixture key is a FAKE pattern (not a real
# credential) that the gitleaks aws rule detects.

@test "gitleaks finding blocks the archive with a findings count" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  make_story 005-leaky complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epico/stories/005-leaky/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-leaky
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked"' > /dev/null
  echo "$output" | jq -e '.secrets.findings >= 1' > /dev/null
  [ -d "$PROJ/.epico/stories/005-leaky" ]
  [ ! -d "$PROJ/.epico/archive/005-leaky" ]
}

@test "--skip-secrets bypasses the scan and records the override" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  make_story 005-skipped complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epico/stories/005-skipped/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-skipped --skip-secrets
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-skipped" ]
  # The override is recorded in the manifest entry.
  grep -q 'skip-secrets' "$MANIFEST"
}

@test "absent gitleaks proceeds and notes the skipped scan" {
  # Simulate a machine without gitleaks via a PATH that mirrors
  # /usr/bin minus the gitleaks binary.
  mkdir "$WORK/nobin"
  local t
  for t in /usr/bin/*; do
    ln -s "$t" "$WORK/nobin/${t##*/}" 2> /dev/null || true
  done
  rm -f "$WORK/nobin/gitleaks"
  make_story 005-noscan complete
  run --separate-stderr env PATH="$WORK/nobin" bash "$ARCHIVE_SH" .epico/stories/005-noscan
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  [ -d "$PROJ/.epico/archive/005-noscan" ]
  # The skipped scan is noted in the structured output.
  printf '%s\n%s\n' "$output" "$stderr" | grep -qi 'gitleaks'
}

# gl_shim_path <exit-code> - a PATH directory mirroring /usr/bin with a FAKE
# `gitleaks` that exits with the given code and writes NO report. Same mirroring
# trick the failing-clock case uses; a shim is the only honest way to produce a scan
# failure, since the real binary cannot be made to fail on demand.
#
# The shim's diagnostic is deliberately NASTY - ANSI escapes (which gitleaks
# really does emit, even into a pipe), a double quote, DEL and a C1 byte. That
# text is external data spliced into the JSON `secrets.error`, so it exercises
# the union escaper on the one path where arbitrary bytes from another program
# reach this script's output.
gl_shim_path() {
  local code="$1" dir="$WORK/glshim-$1" t
  mkdir -p "$dir"
  for t in /usr/bin/*; do ln -s "$t" "$dir/${t##*/}" 2> /dev/null || true; done
  # rm first: writing THROUGH the symlink would try to overwrite /usr/bin/gitleaks.
  rm -f "$dir/gitleaks"
  {
    echo '#!/bin/sh'
    printf 'printf %s >&2\n' "'FTL \\033[1mboom\\033[0m \"quoted\" del=\\177 c1=\\302\\206\\n'"
    printf 'exit %s\n' "$code"
  } > "$dir/gitleaks"
  chmod +x "$dir/gitleaks"
  printf '%s' "$dir"
}

@test "a scan that exits neither 0 nor 1 blocks instead of passing" {
  # THE difference between "scanned and clean" and "never actually scanned".
  # A scanner that RAN and could not answer is a guard hit like any other -
  # only an ABSENT scanner is the documented degradation. Collapsing the
  # two turns every broken gitleaks on every machine into a silent free pass.
  make_story 005-scanfail complete
  local p
  p=$(gl_shim_path 7)
  run --separate-stderr env PATH="$p" bash "$ARCHIVE_SH" .epico/stories/005-scanfail
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # Not a clean scan, and not findings either - the report says which.
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("exited 7")' > /dev/null
  echo "$output" | jq -e '.reason | test("FAILED")' > /dev/null
  # The size census runs BEFORE the scan, so this one is a real measurement
  # (no oversized file in the fixture) rather than the untaken-count null below.
  echo "$output" | jq -e '.secrets.unscanned_files == 0' > /dev/null
  # The scanner's own diagnostic is arbitrary bytes from another program spliced
  # into a JSON string. stdout must still parse, and round-trip what went in.
  echo "$output" | jq -e . > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("[1mboom")' > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("\"quoted\"")' > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("del=")' > /dev/null
  echo "$output" | jq -e '.secrets.error | contains("c1=")' > /dev/null
  # Fail-closed: nothing moved, nothing recorded.
  [ -d "$PROJ/.epico/stories/005-scanfail" ]
  [ ! -d "$PROJ/.epico/archive/005-scanfail" ]
  [ ! -e "$MANIFEST" ]
}

@test "gitleaks' own fatal exit 1 is a scan failure, not a findings count" {
  # gitleaks exits 1 for FINDINGS *and* for its own fatal errors - an
  # unparseable config, an unwritable report path, a target that does not exist.
  # So the exit code alone cannot tell "found something" from "never looked",
  # and the naive reading of `--exit-code 1` reports a scan that never ran as
  # `findings: 0`. The REPORT is the discriminator: gitleaks writes it only
  # after a scan that actually ran.
  make_story 005-fatal complete
  local p
  p=$(gl_shim_path 1)
  run --separate-stderr env PATH="$p" bash "$ARCHIVE_SH" .epico/stories/005-fatal
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  # The one assertion that matters: it is NOT reported as a clean scan.
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("without writing a readable JSON report")' > /dev/null
  [ -d "$PROJ/.epico/stories/005-fatal" ]
  [ ! -e "$MANIFEST" ]
  # No report survives this path, so none is named: pointing an operator at a
  # file the run has just deleted is the same mistake as a false "nothing moved".
  echo "$output" | jq -e '.secrets.report == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("/tmp/") | not' > /dev/null
}

@test "exit 0 without a report is a scanner that answered without looking" {
  # The mirror of the exit-1 fatal above: a CLEAN exit is trusted only when a report proves a scan happened.
  # gitleaks writes the report after the scan, so exit 0 with nothing on disk
  # is an answer with no scan behind it — which must not become `findings: 0`.
  make_story 005-noreport complete
  local p
  p=$(gl_shim_path 0)
  run --separate-stderr env PATH="$p" bash "$ARCHIVE_SH" .epico/stories/005-noreport
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  # The assertion that carries the whole case: a scan that did not happen is
  # never reported as a scan that found nothing.
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.error | test("exited 0 but wrote no readable JSON report")' > /dev/null
  # No surviving report, so none is named (same rule as the exit-1 fatal case).
  echo "$output" | jq -e '.secrets.report == null' > /dev/null
  # Fail-closed: the guard precedes the append and the move.
  [ -d "$PROJ/.epico/stories/005-noreport" ]
  [ ! -d "$PROJ/.epico/archive/005-noreport" ]
  [ ! -e "$MANIFEST" ]
}

@test "the absent-scanner note says WHAT was skipped, not just the scanner's name" {
  # The absent-scanner case above greps stdout+stderr for 'gitleaks' - which
  # the constant `"scanner": "gitleaks"` key satisfies ON ITS OWN, so it cannot
  # tell a real note from no note at all. The SKIPPED SCAN must be noted, so
  # that is what this pins, in both registers.
  mkdir "$WORK/nobin2"
  local t
  for t in /usr/bin/*; do ln -s "$t" "$WORK/nobin2/${t##*/}" 2> /dev/null || true; done
  rm -f "$WORK/nobin2/gitleaks"
  make_story 005-nonote complete
  run --separate-stderr env PATH="$WORK/nobin2" bash "$ARCHIVE_SH" .epico/stories/005-nonote
  [ "$status" -eq 0 ]
  # Structurally on stdout, where the orchestrator's jq can see it...
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  echo "$output" | jq -e '.secrets.skipped == "gitleaks not installed"' > /dev/null
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  # ...and in prose on stderr, in the guard's key=value shape, for the human.
  echo "$stderr" | grep -q 'guard=secrets verdict=skipped'
  echo "$stderr" | grep -q 'reason=gitleaks-not-installed'
  echo "$stderr" | grep -q 'UNSCANNED'
}

@test "a clean story reports a scan that RAN, and silence still means not-run" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # Silence must never read as safety: a clean archive says so POSITIVELY...
  make_story 005-clean complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-clean
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.secrets.scanned == true' > /dev/null
  echo "$output" | jq -e '.secrets.findings == 0' > /dev/null
  echo "$output" | jq -e '.secrets.skipped == null and .secrets.error == null' > /dev/null
  # ...and `{}` keeps its own meaning, which is the other half of the pair: a
  # story blocked at step 2 never reaches the scanner, so it must not read as
  # clean either.
  make_story 005-cleanbin complete
  printf 'ab\0cd' > "$PROJ/.epico/stories/005-cleanbin/blob.dat"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-cleanbin
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets == {}' > /dev/null
}

@test "--skip-secrets on a story that really holds a secret archives, and the skip shows" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The override on the path that actually exercises it: the --skip-secrets
  # case above asserts the exit code and the manifest, but a skip that LOOKS like a clean
  # scan in the report is worse than no scan at all.
  make_story 005-leakskip complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epico/stories/005-leakskip/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-leakskip --skip-secrets
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-leakskip" ]
  echo "$output" | jq -e '.secrets.scanned == false' > /dev/null
  echo "$output" | jq -e '.secrets.findings == null' > /dev/null
  echo "$output" | jq -e '.secrets.skipped == "--skip-secrets"' > /dev/null
  # Nothing was measured on this path, so no count claims to be one.
  echo "$output" | jq -e '.secrets.unscanned_files == null' > /dev/null
  # Recorded in the entry, on stdout and in the permanent record.
  echo "$output" | jq -e '.manifest_entry.overrides_used | index("skip-secrets") != null' > /dev/null
  grep -q 'skip-secrets' "$MANIFEST"
  # Archive does not scrub: the file travels as it is...
  grep -q 'AKIAQWERTYUIOPASDFGH' "$PROJ/.epico/archive/005-leakskip/notes-creds.md"
  # ...but the secret is never copied into the manifest. (`[[ != ]]` rather than
  # `! grep`: see the note in the no-secret-material case - a `!` that is not
  # the last line of the body can never fail a bats test.)
  [[ "$(cat "$MANIFEST")" != *AKIAQWERTYUIOPASDFGH* ]]
}

@test "the findings count is the real count, not a boolean" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The guard reports the findings count. A guard that answers 1 for any
  # number of leaks tells the operator nothing about the size of the clean-up.
  make_story 005-two complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epico/stories/005-two/creds-a.md"
  printf 'aws_access_key_id = "AKIAZXCVBNMASDFGHJKL"\n' \
    > "$PROJ/.epico/stories/005-two/creds-b.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-two
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.secrets.findings == 2' > /dev/null
  echo "$output" | jq -e '.secrets.findings | type == "number"' > /dev/null
  # The human reason carries the count too - it is what the orchestrator surfaces.
  echo "$output" | jq -e '.reason | contains("2 secret")' > /dev/null
}

@test "no secret material reaches stdout, stderr or the permanent record" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # A guard that quotes the leak into its own diagnostics copies it into every
  # log that captures the run - CI output, shell history, an orchestrator
  # transcript. The count and the report PATH are what leave this process.
  make_story 005-quiet complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epico/stories/005-quiet/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-quiet
  [ "$status" -eq 1 ]
  # `[[ != ]]`, NOT `! grep -q ...`: bash exempts a `!`-inverted command from
  # `set -e`, so a `! cmd` anywhere but the LAST line of a bats test body is a
  # no-op that can never fail the case.
  [[ "$output" != *AKIAQWERTYUIOPASDFGH* ]]
  [[ "$stderr" != *AKIAQWERTYUIOPASDFGH* ]]
  [ ! -e "$MANIFEST" ]
  # The report path IS reported, so the operator can go and read it.
  echo "$output" | jq -e '.secrets.report | test("gitleaks-report.json")' > /dev/null
}

@test "a story blocked on secrets leaves no manifest entry and no archive directory" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The step order, asserted from the outside: the secrets guard runs BEFORE the
  # prune (step 4), the append (step 5) and the move (step 6). A blocked story
  # already written into the permanent record would be a record of an archive
  # that never happened, under a tree that is deliberately hard to repair.
  make_story 005-order complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epico/stories/005-order/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-order
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | jq -e '.manifest_entry == {}' > /dev/null
  [ ! -e "$MANIFEST" ]
  [ ! -d "$PROJ/.epico/archive" ]
  [ -f "$PROJ/.epico/stories/005-order/notes-creds.md" ]
  [ -f "$PROJ/.epico/stories/005-order/story.md" ]
}

@test "the scan report lives outside the project and never rides into the archive" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # gitleaks' JSON report holds the MATCHED SECRET, the file and the line. Two
  # places it must never be: world-readable in a shared temp directory, and
  # inside the story - where it would travel into .epico/archive/ with the move
  # and become a permanent copy of exactly what the guard just objected to.
  make_story 005-reportpath complete
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' \
    > "$PROJ/.epico/stories/005-reportpath/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-reportpath
  [ "$status" -eq 1 ]
  local rp
  rp=$(echo "$output" | jq -r '.secrets.report')
  [ -n "$rp" ] && [ "$rp" != "null" ]
  [[ "$rp" != "$PROJ"/* ]]
  [ -f "$rp" ]
  grep -q 'AKIAQWERTYUIOPASDFGH' "$rp"
  [ "$(stat -c %a "$rp")" = "600" ]
  [ "$(stat -c %a "$(dirname "$rp")")" = "700" ]
  rm -rf "$(dirname "$rp")"
  # A CLEAN scan keeps nothing: `[]` is not evidence, and nothing gitleaks-shaped
  # may end up in the archived story.
  make_story 005-reportgone complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-reportgone
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.secrets.report == null' > /dev/null
  [ -z "$(find "$PROJ/.epico/archive/005-reportgone" -name '*gitleaks*' -print -quit)" ]
}

@test "a file over the scanner's size limit is reported as unscanned, not as clean" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # PINNED AS A DECISION, not left to be rediscovered: --max-target-megabytes 15
  # makes gitleaks skip any file over 15,000,000 bytes (decimal MB: 15000000
  # is scanned, 15000001 is not) WITHOUT saying so - it exits
  # 0 and reports "no leaks found". A scanner that silently skips the biggest
  # file in the tree while reporting clean is the exact failure the secrets
  # guard exists to prevent. Step 2 blocks anything over 10 MB, so only --allow-heavy can bring
  # a file this size to the scanner at all - and when it does, the archive says
  # what the pass does NOT cover.
  make_story 005-toobig complete
  {
    printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n'
    head -c 15000001 /dev/zero | tr '\0' 'a'
  } > "$PROJ/.epico/stories/005-toobig/huge-notes.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-toobig --allow-heavy
  [ "$status" -eq 0 ]
  # The scan passes with a plaintext key sitting in the story...
  echo "$output" | jq -e '.secrets.scanned == true and .secrets.findings == 0' > /dev/null
  # ...so it must not be allowed to imply the file was looked at.
  echo "$output" | jq -e '.secrets.unscanned_files == 1' > /dev/null
  echo "$stderr" | grep -q 'huge-notes.md'
  echo "$stderr" | grep -qi 'skips'
}

# --- Log pruning ---

@test "draft logs collapse into a single summary file" {
  make_story 005-logs complete
  mkdir -p "$PROJ/.epico/stories/005-logs/.draft/logs"
  seq 1 20000 > "$PROJ/.epico/stories/005-logs/.draft/logs/build.log"
  { seq 1 200; echo "FINAL LINE MARKER 005"; } \
    > "$PROJ/.epico/stories/005-logs/.draft/logs/test-run.log"
  touch -d '2026-08-01 10:00' "$PROJ/.epico/stories/005-logs/.draft/logs/build.log"
  touch -d '2026-08-01 11:00' "$PROJ/.epico/stories/005-logs/.draft/logs/test-run.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-logs
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-logs"
  # One summary carrying names + the tail of the most recent log...
  [ -f "$arch/.draft/logs-summary.md" ]
  grep -q 'build.log' "$arch/.draft/logs-summary.md"
  grep -q 'test-run.log' "$arch/.draft/logs-summary.md"
  grep -q 'FINAL LINE MARKER 005' "$arch/.draft/logs-summary.md"
  # ...and the raw log files are gone.
  [ ! -e "$arch/.draft/logs/build.log" ]
  [ ! -e "$arch/.draft/logs/test-run.log" ]
  echo "$output" | jq -e '.pruned.logs_kb > 0' > /dev/null
}

@test "--keep-logs preserves logs and records the override" {
  make_story 005-keeplogs complete
  mkdir -p "$PROJ/.epico/stories/005-keeplogs/.draft/logs"
  seq 1 200 > "$PROJ/.epico/stories/005-keeplogs/.draft/logs/build.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-keeplogs --keep-logs
  [ "$status" -eq 0 ]
  [ -f "$PROJ/.epico/archive/005-keeplogs/.draft/logs/build.log" ]
  # The override is recorded.
  grep -q 'keep-logs' "$MANIFEST"
}

# `--keep-logs preserves logs and records the override` alone cannot tell "the
# flag was honoured" from "nothing prunes at all", which is why `--keep-logs
# writes no summary at all` sits beside it.

# make_log_story <dir-name> [lines] - a COMPLETE story with .draft/logs/build.log
make_log_story() {
  local dir="$PROJ/.epico/stories/$1"
  make_story "$1" complete
  mkdir -p "$dir/.draft/logs"
  seq 1 "${2:-500}" > "$dir/.draft/logs/build.log"
}

@test "a story blocked by the weight guard keeps every log file" {
  # THE STEP ORDER, asserted from outside the script. Prune is the FIRST
  # destructive step in the pipeline, so it must be unreachable on any path that
  # can still return `blocked`. A prune that ran before the guards would collapse
  # these logs and THEN refuse the archive - evidence destroyed for a story that
  # was never archived at all, and nothing left to re-run against.
  make_log_story 005-blockedlogs 2000
  local story="$PROJ/.epico/stories/005-blockedlogs"
  yes 'padding line for the weight guard fixture' | head -c 10485761 > "$story/big.txt"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-blockedlogs
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # The logs are untouched, byte for byte, and no summary was written...
  [ -f "$story/.draft/logs/build.log" ]
  [ "$(wc -l < "$story/.draft/logs/build.log")" -eq 2000 ]
  [ ! -e "$story/.draft/logs-summary.md" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  # ...and the prune never announced itself at all. (`[[ != ]]`, not `! grep`:
  # an inverted command is exempt from set -e - see the note in the secrets
  # guard's no-secret-material case.)
  [[ "$stderr" != *"prune=logs"* ]]
}

@test "a story blocked by the secrets guard keeps every log file" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The same assertion against the OTHER guard, because the two block from
  # different steps and only running both proves the prune sits after each.
  make_log_story 005-leakylogs 2000
  local story="$PROJ/.epico/stories/005-leakylogs"
  printf 'aws_access_key_id = "AKIAQWERTYUIOPASDFGH"\n' > "$story/notes-creds.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-leakylogs
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  [ -f "$story/.draft/logs/build.log" ]
  [ "$(wc -l < "$story/.draft/logs/build.log")" -eq 2000 ]
  [ ! -e "$story/.draft/logs-summary.md" ]
  [[ "$stderr" != *"prune=logs"* ]]
}

@test "the prune reports itself after both guards, never before" {
  # The other half of the pair: the two cases above prove the prune does not run
  # when a guard blocks; this proves that when it DOES run, it runs last. All
  # three verdicts are key=value lines on stderr, so the ORDER is readable
  # without parsing prose - and `guards_passed=true` is the script's own
  # sequence assertion, stated where a test can see it.
  make_log_story 005-order-logs 500
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-order-logs
  [ "$status" -eq 0 ]
  local weight secrets prune
  weight=$(echo "$stderr" | grep -n 'guard=weight-binary' | head -1 | cut -d: -f1)
  secrets=$(echo "$stderr" | grep -n 'guard=secrets' | head -1 | cut -d: -f1)
  prune=$(echo "$stderr" | grep -n 'prune=logs' | head -1 | cut -d: -f1)
  [ -n "$weight" ]
  [ -n "$secrets" ]
  [ -n "$prune" ]
  [ "$prune" -gt "$weight" ]
  [ "$prune" -gt "$secrets" ]
  echo "$stderr" | grep -q 'prune=logs verdict=pruned.*guards_passed=true'
}

@test "logs_kb measures what was actually freed, not a constant" {
  # pruned.logs_kb must equal the freed size. A constant, a boolean or a file
  # count would satisfy the basic `> 0` just as well, so this asserts the EXACT arithmetic on two fixtures whose log sizes
  # differ by two orders of magnitude. Rounded UP, deliberately: integer division
  # reports 0 for anything under a kilobyte, and `logs_kb: 0` already means
  # "nothing was freed".
  make_story 005-kbsmall complete
  mkdir -p "$PROJ/.epico/stories/005-kbsmall/.draft/logs"
  head -c 30000 /dev/zero | tr '\0' 'a' \
    > "$PROJ/.epico/stories/005-kbsmall/.draft/logs/small.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-kbsmall
  [ "$status" -eq 0 ]
  # ceil(30000 / 1024) == 30
  echo "$output" | jq -e '.pruned.logs_kb == 30' > /dev/null

  make_story 005-kbbig complete
  mkdir -p "$PROJ/.epico/stories/005-kbbig/.draft/logs"
  head -c 3000000 /dev/zero | tr '\0' 'a' \
    > "$PROJ/.epico/stories/005-kbbig/.draft/logs/big.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-kbbig
  [ "$status" -eq 0 ]
  # ceil(3000000 / 1024) == 2930
  echo "$output" | jq -e '.pruned.logs_kb == 2930' > /dev/null
  # ...and the measurement reaches the permanent record, not just stdout.
  grep -Eq 'logs_kb:[[:space:]]*2930' "$MANIFEST"
}

@test "the summary records each log's size and last-modified time, not just its name" {
  # The summary records the NAME, the SIZE and the LAST-MODIFIED TIME of every
  # log. The basic case greps for the two names only - which a summary listing
  # nothing but names would satisfy exactly as well.
  make_story 005-facts complete
  local d="$PROJ/.epico/stories/005-facts/.draft/logs"
  mkdir -p "$d"
  head -c 4096 /dev/zero | tr '\0' 'x' > "$d/first.log"
  head -c 8192 /dev/zero | tr '\0' 'y' > "$d/second.log"
  touch -d '2026-08-01 10:00' "$d/first.log"
  touch -d '2026-08-02 11:30' "$d/second.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-facts
  [ "$status" -eq 0 ]
  local s="$PROJ/.epico/archive/005-facts/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'size_bytes: 4096' "$s"
  grep -q 'size_bytes: 8192' "$s"
  # `touch -d` and `stat %y` both speak local time, so the two agree whatever
  # TZ the machine running the suite is set to.
  grep -q '2026-08-01 10:00' "$s"
  grep -q '2026-08-02 11:30' "$s"
}

@test "a single log collapses, and its own tail is the one recorded" {
  # The degenerate case of "the most recently modified log": one file, which is
  # both the newest and the oldest. It must not crash and must not skip the tail.
  make_story 005-onelog complete
  local d="$PROJ/.epico/stories/005-onelog/.draft/logs"
  mkdir -p "$d"
  { seq 1 100; echo 'ONLY LOG MARKER'; } > "$d/only.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-onelog
  [ "$status" -eq 0 ]
  local s="$PROJ/.epico/archive/005-onelog/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'only.log' "$s"
  grep -q 'ONLY LOG MARKER' "$s"
  [ ! -e "$PROJ/.epico/archive/005-onelog/.draft/logs/only.log" ]
  echo "$output" | jq -e '.pruned.logs_kb > 0' > /dev/null
}

@test "an empty logs directory produces no summary and reports no prune" {
  # DECIDED, not left to chance: with no log files there is nothing to record and
  # nothing to replace, so NO summary is written - a file listing zero logs and
  # holding no tail would be a permanent record of nothing. It must also not
  # crash, and must not report a prune that did not happen.
  make_story 005-emptylogs complete
  mkdir -p "$PROJ/.epico/stories/005-emptylogs/.draft/logs"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-emptylogs
  [ "$status" -eq 0 ]
  [ ! -e "$PROJ/.epico/archive/005-emptylogs/.draft/logs-summary.md" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  echo "$stderr" | grep -q 'prune=logs verdict=none'
}

@test "a log that cannot be read is reported and kept, never deleted unrecorded" {
  # A file whose evidence could not be captured must not be destroyed by the step
  # whose whole purpose is to preserve that evidence. And it must be a REPORTED
  # verdict with JSON on stdout: a bare `set -e` abort would end the run with
  # zero bytes on stdout, which the output contract promises never happens.
  # --allow-heavy is needed to reach step 4 at all - the weight/binary guard
  # blocks an unreadable file first, which is the step order doing its job.
  make_story 005-unreadlog complete
  local d="$PROJ/.epico/stories/005-unreadlog/.draft/logs"
  mkdir -p "$d"
  { seq 1 50; echo 'OLDER READABLE MARKER'; } > "$d/older.log"
  { seq 1 50; echo 'NEWER UNREADABLE MARKER'; } > "$d/newer.log"
  touch -d '2026-08-01 10:00' "$d/older.log"
  touch -d '2026-08-01 12:00' "$d/newer.log"
  chmod 000 "$d/newer.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-unreadlog --allow-heavy
  # `|| true` on both: whichever side of the move the file ended on, the fixture
  # cleanup must not kill the case before its assertions run.
  chmod 644 "$d/newer.log" 2> /dev/null || true
  chmod 644 "$PROJ/.epico/archive/005-unreadlog/.draft/logs/newer.log" 2> /dev/null || true
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "archived"' > /dev/null
  local arch="$PROJ/.epico/archive/005-unreadlog"
  # The readable log collapsed...
  [ ! -e "$arch/.draft/logs/older.log" ]
  # ...and the one whose tail could not be read is still there, untouched.
  [ -f "$arch/.draft/logs/newer.log" ]
  grep -q 'NEWER UNREADABLE MARKER' "$arch/.draft/logs/newer.log"
  # The summary names it and says why, and stderr carries the same verdict.
  grep -q 'newer.log' "$arch/.draft/logs-summary.md"
  grep -q 'could not be read' "$arch/.draft/logs-summary.md"
  echo "$stderr" | grep -q 'prune=logs verdict=partial'
}

@test "a log name with a quote, a space and a newline lands intact in the summary" {
  # A file name is arbitrary bytes, and it reaches the summary as CONTENT - so it
  # goes through quote_scalar, the one escaper whose output BOTH JSON and YAML
  # decode the same way, and never through some second rule invented for this
  # file. It is also why the log list is a YAML block and not a markdown table:
  # a name holding `|` would silently grow a column there.
  make_story 005-oddname complete
  local d="$PROJ/.epico/stories/005-oddname/.draft/logs"
  mkdir -p "$d"
  local odd
  odd=$(printf 'we"ird na\nme.log')
  { seq 1 20; echo 'ODD NAME MARKER'; } > "$d/$odd"
  printf 'plain\n' > "$d/plain.log"
  touch -d '2026-08-01 10:00' "$d/plain.log"
  touch -d '2026-08-01 12:00' "$d/$odd"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-oddname
  [ "$status" -eq 0 ]
  local s="$PROJ/.epico/archive/005-oddname/.draft/logs-summary.md"
  [ -f "$s" ]
  # One line, escaped exactly as both formats decode it.
  grep -qF 'name: "we\"ird na\nme.log"' "$s"
  # ...and it round-trips: the block still PARSES as YAML and gives back the
  # bytes that went in. A grep alone would pass on an escape that is merely
  # present; this fails on one that is merely plausible.
  python3 -c '
import sys, yaml
txt = open(sys.argv[1]).read()
block = txt.split("~~~yaml\n", 1)[1].split("\n~~~", 1)[0]
names = [e["name"] for e in yaml.safe_load(block)["logs"]]
assert sys.argv[2] in names, (sys.argv[2], names)
' "$s" "$odd"
  # The odd-named log is the newest, so the tail is its own - and it is gone.
  grep -q 'ODD NAME MARKER' "$s"
  [ ! -e "$PROJ/.epico/archive/005-oddname/.draft/logs/$odd" ]
}

@test "--keep-logs writes no summary at all" {
  # The basic --keep-logs case cannot by itself tell "the flag was honoured"
  # from "the feature is missing". This is the half that can: the flag means keep the logs INSTEAD
  # of collapsing them, so a run that wrote a summary AND kept the logs would be
  # honouring neither reading.
  make_log_story 005-keepnosum 500
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-keepnosum --keep-logs
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-keepnosum"
  [ -f "$arch/.draft/logs/build.log" ]
  [ "$(wc -l < "$arch/.draft/logs/build.log")" -eq 500 ]
  [ ! -e "$arch/.draft/logs-summary.md" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  echo "$stderr" | grep -q 'prune=logs verdict=skipped reason=--keep-logs'
}

@test "an existing logs-summary.md is never overwritten" {
  # The summary is the artifact this step produces, so one already sitting there
  # was written by a hand or by an interrupted run. Replacing a document about
  # the logs with a generated one - and then deleting the logs it described - is
  # exactly the quiet loss this step exists to end. Fail-safe: skip, keep the
  # logs, and say so.
  make_log_story 005-hassum 300
  printf '# Hand-written notes about these logs\n' \
    > "$PROJ/.epico/stories/005-hassum/.draft/logs-summary.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-hassum
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-hassum"
  grep -q 'Hand-written notes' "$arch/.draft/logs-summary.md"
  [ -f "$arch/.draft/logs/build.log" ]
  echo "$output" | jq -e '.pruned.logs_kb == 0' > /dev/null
  echo "$stderr" | grep -q 'prune=logs verdict=skipped reason=summary-exists'
}

# --- The log summary and the secrets scan ---
# Step 3 scans `.draft/logs/*` as they are, and the summary is written
# AFTERWARDS - so no guard ever looks at it, and 40 lines of arbitrary log
# output enter the archive unscanned. ACCEPTED, deliberately: the prune only
# ever REMOVES, so every byte of that tail was already in the story when
# gitleaks read it and would have travelled into the archive verbatim under
# --keep-logs. Collapsing a log cannot introduce a credential the archive was
# not already about to receive - it can only reduce one, and re-scanning would
# re-read a strict subset (or, where nothing was scanned, scan exactly what the
# operator chose not to scan). Blocking is worse still: the verdict would land
# AFTER a destructive step, which is what the step order forbids.
# What is NOT accepted is silence about the guarantee. These two cases pin that.

@test "an unscanned story says so in the summary it leaves behind" {
  make_log_story 005-provenance 300
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-provenance --skip-secrets
  [ "$status" -eq 0 ]
  local s="$PROJ/.epico/archive/005-provenance/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'secrets_scan:' "$s"
  grep -q 'NOT SCANNED' "$s"
  grep -q 'skip-secrets' "$s"
}

@test "a scanned story records the scan, and the two summaries differ" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # The pair is what makes either half a discriminator rather than a constant:
  # in a permanent record, "scanned and clean" and "nobody looked" must not be
  # the same sentence.
  make_log_story 005-prov-scanned 300
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-prov-scanned
  [ "$status" -eq 0 ]
  make_log_story 005-prov-unscanned 300
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-prov-unscanned --skip-secrets
  [ "$status" -eq 0 ]
  local a b
  a=$(grep 'secrets_scan:' "$PROJ/.epico/archive/005-prov-scanned/.draft/logs-summary.md")
  b=$(grep 'secrets_scan:' "$PROJ/.epico/archive/005-prov-unscanned/.draft/logs-summary.md")
  [[ "$a" == *"scanned by gitleaks"* ]]
  [[ "$b" == *"NOT SCANNED"* ]]
  [[ "$a" != "$b" ]]
}

@test "a log too big for the scanner is recorded as unscanned in its own summary" {
  command -v gitleaks > /dev/null || skip "gitleaks not installed"
  # THE one case where `scanned: true, findings: 0` genuinely does NOT cover the
  # tail: gitleaks silently skips any file over --max-target-megabytes (no
  # report entry, no exit code, `INF no leaks found`).
  # Step 2 blocks anything over 10 MB, so only --allow-heavy brings a log this
  # size to the scanner at all; when it does, the summary refuses to let a clean
  # verdict stand for lines nothing ever looked at.
  make_story 005-bigunscanned complete
  local d="$PROJ/.epico/stories/005-bigunscanned/.draft/logs"
  mkdir -p "$d"
  { head -c 15000001 /dev/zero | tr '\0' 'a'; echo; echo 'HUGE LOG MARKER'; } > "$d/huge.log"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-bigunscanned --allow-heavy
  [ "$status" -eq 0 ]
  local s="$PROJ/.epico/archive/005-bigunscanned/.draft/logs-summary.md"
  [ -f "$s" ]
  grep -q 'HUGE LOG MARKER' "$s"
  # The scan reported clean, with the file never opened...
  echo "$output" | jq -e '.secrets.scanned == true and .secrets.findings == 0' > /dev/null
  echo "$output" | jq -e '.secrets.unscanned_files == 1' > /dev/null
  # ...and the summary says exactly that, in the artifact that outlives the run.
  grep -q 'NOT scanned' "$s"
  grep -q '15000000-byte limit' "$s"
}


#!/usr/bin/env bats
# Contract tests for scripts/archive-story.sh: the manifest append is one write, and the resume keys on a complete entry.
# The contract and the fixtures are in tests/lib/archive-story-common.sh.

bats_require_minimum_version 1.5.0
. "$BATS_TEST_DIRNAME/lib/archive-story-common.sh"

# --- The append is one write, and the resume keys on a COMPLETE entry ---

@test "a truncated manifest entry blocks instead of being resumed behind" {
  # `  - story: "<id>"` is the FIRST line the writer emits, so a run killed
  # mid-entry leaves exactly that line. A resume check keyed on it would
  # "resume": skip the append, archive the story, exit 0, and leave the
  # permanent record a stub with no tasks_total, no archived_at, no
  # overrides_used - an entry that claims nothing at all, silently.
  make_story 005-trunc complete
  chmod 555 "$PROJ/.epico/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-trunc
  chmod 755 "$PROJ/.epico/stories"
  [ "$status" -ne 0 ]
  # Truncate the entry right after `status:` - what a kill mid-append leaves.
  python3 -c '
import sys
p = sys.argv[1]
out = []
for ln in open(p).read().splitlines(True):
    out.append(ln)
    if ln.startswith("    status:"):
        break
open(p, "w").write("".join(out))
' "$MANIFEST"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-trunc
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | grep -qi 'truncated'
  # Fail-closed on both counts: nothing moved, and no second entry beside it.
  [ -d "$PROJ/.epico/stories/005-trunc" ]
  [ ! -d "$PROJ/.epico/archive/005-trunc" ]
  [ "$(grep -c 'story: "005-trunc"' "$MANIFEST")" -eq 1 ]
}

# make_bulky_story <dir-name> [deferred-count]
# A COMPLETE story (no `[ ]` left, status done) whose manifest entry runs to
# MANY LINES: `deferred_items:` gets one line per `[~]` box.
#
# Entry LENGTH IN LINES is what makes the append race reproducible. Bash
# line-buffers stdout, so `printf '%s\n' "$entry" >> file` is one write(2) PER
# LINE, and every one of those is a seam a concurrent archive can cut into.
# A short entry collides only under heavy contention; 40 boxes give a ~58-line
# entry that exposes the race reliably.
make_bulky_story() {
  local dir="$PROJ/.epico/stories/$1" n="${2:-40}" i
  mkdir -p "$dir"
  cat > "$dir/story.md" <<EOF
---
story: ${1#*-}
type: feature
scale: standard
version: 1
created: 2026-08-01
status: validated
---

# Story - concurrency fixture
EOF
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-01'
    echo '---'
    echo
    echo '## Task List'
    echo '- [x] 1 - The one closed thing'
    for i in $(seq 1 "$n"); do
      echo "- [~] 2.$i - deferred item number $i with a reasonably long title (deferred: waiting on an external actor)"
    done
  } > "$dir/tasks.md"
}

# keep_concurrent_evidence <n-runs> - surface AND preserve everything a failure
# needs: the corrupt manifest, every run's verdict and every stderr line would
# otherwise die with the temp directory. EVERYTHING is copied out of $WORK (teardown deletes it) and the path
# is printed; inline, only the runs that did NOT archive are echoed, because 80
# successful JSON reports in a failure report bury the two that matter.
keep_concurrent_evidence() {
  local n keep verdict shown=0
  keep=$(mktemp -d "${TMPDIR:-/tmp}/archive-conc-evidence.XXXXXX")
  cp -- "$MANIFEST" "$keep/manifest.yaml" 2> /dev/null || true
  for n in $(seq 1 "$1"); do
    cp -- "$WORK/run.$n.out" "$keep/run.$n.out" 2> /dev/null || true
    cp -- "$WORK/run.$n.err" "$keep/run.$n.err" 2> /dev/null || true
    verdict=$(jq -r '.status // "NO-JSON"' < "$WORK/run.$n.out" 2> /dev/null || echo NO-JSON)
    if [ "$verdict" != archived ] && [ "$shown" -lt 5 ]; then
      shown=$((shown + 1))
      echo "--- run $n verdict=$verdict ---"
      cat -- "$WORK/run.$n.out" 2>&1 || true
      echo "--- run $n stderr ---"
      tail -5 -- "$WORK/run.$n.err" 2>&1 || true
    fi
  done
  echo "--- every run's stdout/stderr and the manifest preserved in $keep ---"
}

@test "concurrent first-runs keep one header and lose no entry" {
  # TWO bugs, one case.
  #
  # (1) `manifest_header > "$MANIFEST_FILE"` used `>`, which TRUNCATES. Two runs
  # could both pass `[[ ! -e ]]`, and the second erased the first run's entry
  # while that first run reported exit 0 and moved its story - the moved-story-
  # without-its-entry state append-before-move exists to make impossible.
  #
  # (2) the append itself was unsynchronized. `printf '%s\n' "$entry" >> file`
  # is NOT one write(2): bash line-buffers, so it is one write PER LINE, and two
  # concurrent archives interleave INSIDE an entry - entry B's keys landing in
  # the middle of entry A's `deferred_items:` list. O_APPEND loses no byte, so
  # the LINE COUNTS SURVIVE: `grep -c '^  - story: '` still reports N and every
  # entry still looks present. That is why this case must PARSE the document.
  #
  # WHY TEN ROUNDS. A collision needs two writers inside their append at the
  # same instant, and the append is ~60us against a spread of arrival times of
  # several ms - so ONE burst is a coin flip, not a proof. Ten independent
  # bursts make a miss unlikely. Bigger entries do NOT help (the longer census
  # de-synchronizes the writers faster than it widens the window), and neither
  # does a FIFO start barrier. Repetition is what buys the power; the
  # deterministic pin of the mechanism itself is the mutual-exclusion case
  # below. All rounds share ONE manifest, exactly as real archives do, so a
  # single parse at the end catches a corruption from any of them.
  local rounds=10 writers=8 r n idx total=80
  for idx in $(seq 1 "$total"); do
    make_bulky_story "$(printf '%03d-race' "$idx")" 40
  done
  for r in $(seq 1 "$rounds"); do
    for n in $(seq 1 "$writers"); do
      idx=$(((r - 1) * writers + n))
      bash "$ARCHIVE_SH" ".epico/stories/$(printf '%03d-race' "$idx")" --skip-secrets \
        > "$WORK/run.$idx.out" 2> "$WORK/run.$idx.err" &
    done
    wait
  done

  local failed="" archived entries headers yamlerr
  [ -f "$MANIFEST" ] || failed+="no manifest was created; "
  archived=$(ls -1 "$PROJ/.epico/archive" 2> /dev/null | grep -c -- '-race' || true)
  [ "${archived:-0}" -eq "$total" ] || failed+="archived dirs ${archived:-0} != $total; "
  entries=$(grep -c '^  - story: ' "$MANIFEST" 2> /dev/null || true)
  [ "${entries:-0}" -eq "$total" ] || failed+="entry lines ${entries:-0} != $total; "
  headers=$(grep -c '^archived:' "$MANIFEST" 2> /dev/null || true)
  [ "${headers:-0}" -eq 1 ] || failed+="headers ${headers:-0} != 1; "
  # The load-bearing one: a document that PARSES, with N complete entries.
  yamlerr=$(python3 -c '
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1]))
except Exception as e:
    m = getattr(e, "problem_mark", None)
    where = " at line %d" % (m.line + 1) if m else ""
    print("PARSE " + str(e).splitlines()[0] + where)
    raise SystemExit(0)
a = (d or {}).get("archived") or []
if len(a) != int(sys.argv[2]):
    print("COUNT %d != %s" % (len(a), sys.argv[2]))
    raise SystemExit(0)
for e in a:
    if not e.get("archived_at") or not e.get("story"):
        print("INCOMPLETE " + repr(e)[:200])
        raise SystemExit(0)
print("OK")
' "$MANIFEST" "$total" 2>&1 || true)
  [ "$yamlerr" = OK ] || failed+="yaml: $yamlerr; "
  # No lock may survive a run that finished.
  [ ! -e "$PROJ/.epico/archive/.manifest.lock" ] || failed+="a manifest lock was left behind; "

  if [ -n "$failed" ]; then
    echo "CONCURRENCY FAILURE: $failed"
    case "$yamlerr" in
      *"at line "*)
        local ln="${yamlerr##*at line }"
        echo "--- manifest lines $((ln > 20 ? ln - 20 : 1))-$((ln + 5)) ---"
        sed -n "$((ln > 20 ? ln - 20 : 1)),$((ln + 5))p" "$MANIFEST" || true
        ;;
    esac
    keep_concurrent_evidence "$total"
    false
  fi
}

@test "an archive cannot append while another run holds the manifest lock" {
  # The DETERMINISTIC pin of the mechanism the case above can only pin
  # statistically. Mutual exclusion is not "two writers rarely collide" - it is
  # "while one run holds the lock, no other run writes a byte". So this case
  # takes the lock by hand, exactly the way manifest_append takes it, and
  # watches: with the lock honoured the archive waits and the manifest does not
  # grow; without it the append lands immediately and the assertion below fails
  # on every run, not on some of them.
  make_story 005-excl complete
  mkdir -p "$PROJ/.epico/archive"
  local lock="$PROJ/.epico/archive/.manifest.lock"
  mkdir "$lock"
  : > "$lock/owner.test-holder"
  # A pre-existing manifest, so "did it append?" is a question about SIZE and
  # not about whether the file was created at all.
  printf '%s\n' 'archived:' > "$MANIFEST"
  local before
  before=$(wc -c < "$MANIFEST")
  env EPICO_ARCHIVE_LOCK_TIMEOUT=30 bash "$ARCHIVE_SH" .epico/stories/005-excl \
    > "$WORK/excl.out" 2> "$WORK/excl.err" &
  local archiver=$!
  # Long enough for an unsynchronized append to have happened many times over:
  # the whole critical section is ~1ms.
  sleep 1
  local during
  during=$(wc -c < "$MANIFEST")
  [ "$during" -eq "$before" ] || {
    echo "the manifest grew from $before to $during bytes while the lock was held:"
    diff <(printf '%s\n' 'archived:') "$MANIFEST" || true
    kill "$archiver" 2> /dev/null || true
    wait "$archiver" 2> /dev/null || true
    false
  }
  # The story has not moved either - the append is before the move.
  [ -d "$PROJ/.epico/stories/005-excl" ]
  # Release, and it finishes normally.
  rm -f "$lock"/owner.*
  rmdir "$lock"
  wait "$archiver"
  [ -d "$PROJ/.epico/archive/005-excl" ]
  [ "$(grep -c 'story: "005-excl"' "$MANIFEST")" -eq 1 ]
  jq -e '.status == "archived"' < "$WORK/excl.out" > /dev/null
}

@test "the manifest lock holds even when mkdir tells every caller it created it" {
  # uutils coreutils' mkdir (Ubuntu 25.10 and later) can report success to two
  # concurrent callers for one directory, so winning mkdir proves nothing on
  # its own. RacyMkdir is that worst case made deterministic: it succeeds
  # whether or not the directory exists. The archive must still not write a
  # byte while another run's marker is in the lock.
  make_story 005-racy complete
  mkdir -p "$PROJ/.epico/archive" "$WORK/racy-mkdir"
  printf '#!/usr/bin/env bash\nexec %q -p "$@"\n' "$(command -v mkdir)" > "$WORK/racy-mkdir/mkdir"
  chmod +x "$WORK/racy-mkdir/mkdir"
  local lock="$PROJ/.epico/archive/.manifest.lock"
  mkdir "$lock"
  : > "$lock/owner.test-holder"
  printf '%s\n' 'archived:' > "$MANIFEST"
  local before
  before=$(wc -c < "$MANIFEST")
  env PATH="$WORK/racy-mkdir:$PATH" EPICO_ARCHIVE_LOCK_TIMEOUT=30 bash "$ARCHIVE_SH" .epico/stories/005-racy \
    > "$WORK/racy.out" 2> "$WORK/racy.err" &
  local archiver=$!
  sleep 1
  [ "$(wc -c < "$MANIFEST")" -eq "$before" ] || {
    echo "the manifest grew while the lock was held, under a mkdir that always succeeds"
    kill "$archiver" 2> /dev/null || true
    wait "$archiver" 2> /dev/null || true
    false
  }
  [ -d "$PROJ/.epico/stories/005-racy" ]
  # Release. The archiver's own marker comes and goes while it retries, so the
  # rmdir may meet it; either way the archiver ends up alone and finishes.
  rm -f "$lock/owner.test-holder"
  rmdir "$lock" 2> /dev/null || true
  wait "$archiver"
  [ "$(grep -c 'story: "005-racy"' "$MANIFEST")" -eq 1 ]
  jq -e '.status == "archived"' < "$WORK/racy.out" > /dev/null
}

@test "a stale manifest lock left by a killed run is broken, not inherited" {
  # The append is serialized by a lock directory. A run SIGKILLed inside the
  # critical section cannot release it, and a lock nobody will ever release
  # would wedge every future archive on the machine - the tool blocking forever
  # on a corpse. The break is identity-targeted (see manifest_lock_acquire) and
  # only fires on a marker that has not changed for the whole timeout, so it
  # cannot take a live lock. Timeout shortened here so the case does not sit
  # for the production 30s.
  make_story 005-stale complete
  mkdir -p "$PROJ/.epico/archive/.manifest.lock"
  : > "$PROJ/.epico/archive/.manifest.lock/owner.dead-4242-1"
  run --separate-stderr env EPICO_ARCHIVE_LOCK_TIMEOUT=1 \
    bash "$ARCHIVE_SH" .epico/stories/005-stale
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-stale" ]
  # It says so, on stderr - breaking somebody's lock is never silent.
  echo "$stderr" | grep -qi 'breaking the manifest lock'
  # ...and the entry really is in there, and the lock is gone again.
  [ "$(grep -c 'story: "005-stale"' "$MANIFEST")" -eq 1 ]
  [ ! -e "$PROJ/.epico/archive/.manifest.lock" ]
}

@test "a manifest lock that keeps changing hands is waited for, never broken" {
  # The other half of the stale rule, and the one that keeps the break safe: a
  # lock is stale only when ONE identity has held it for the whole timeout. A
  # holder that finishes hands it on to the next run's nonce, which resets the
  # waiter's clock. A timeout measured against elapsed time ALONE would break
  # this busy lock and let a second writer into the middle of an entry.
  #
  # The simulated holder KEEPS THE DIRECTORY the whole time and only rotates the
  # marker inside it - the new marker is created BEFORE the old one is removed,
  # so the directory is never empty and never legitimately breakable. That is
  # the point being isolated: identity changed, ownership did not. The
  # holder-stderr assertion at the end turns a scaffold that holds nothing into
  # a loud failure rather than a mysterious one.
  make_story 005-busy complete
  local lock="$PROJ/.epico/archive/.manifest.lock"
  mkdir -p "$PROJ/.epico/archive"
  mkdir "$lock"
  : > "$lock/owner.holder-0"
  # Held for ~2s - TWICE the timeout, so a stale check that ignored identity
  # would certainly fire - while the marker changes every ~0.1s.
  (
    i=1
    while [ "$i" -lt 20 ]; do
      sleep 0.1
      : > "$lock/owner.holder-$i"
      rm -f "$lock/owner.holder-$((i - 1))"
      i=$((i + 1))
    done
    rm -f "$lock"/owner.*
    rmdir "$lock"
  ) 2> "$WORK/holder.err" &
  local holder=$!
  run --separate-stderr env EPICO_ARCHIVE_LOCK_TIMEOUT=1 \
    bash "$ARCHIVE_SH" .epico/stories/005-busy
  wait "$holder" || true
  # The scaffold really did hold the lock for the whole window.
  [ ! -s "$WORK/holder.err" ] || {
    echo "holder scaffold failed:"
    cat "$WORK/holder.err"
    false
  }
  [ "$status" -eq 0 ]
  # It waited for the holder instead of taking the lock away from it...
  [[ "$stderr" != *"breaking the manifest lock"* ]]
  # ...and then did its own append, exactly once.
  [ "$(grep -c 'story: "005-busy"' "$MANIFEST")" -eq 1 ]
  [ -d "$PROJ/.epico/archive/005-busy" ]
  [ ! -e "$lock" ]
}

@test "a lock path that cannot be a lock is a verdict, not a 30-second wait" {
  # `mkdir` failing is TWO different answers: EEXIST means somebody holds the
  # lock and waiting is right; anything else (a plain file in the way, a
  # read-only archive directory, ENOSPC) means the lock can never appear and
  # waiting only delays the same verdict. Reading every failure as contention
  # costs a full timeout - twice, once for the stale break - before reporting.
  make_story 005-lockfile complete
  mkdir -p "$PROJ/.epico/archive"
  : > "$PROJ/.epico/archive/.manifest.lock"
  local t0=$SECONDS
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-lockfile
  local elapsed=$((SECONDS - t0))
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # Fail-closed: no entry, nothing moved.
  [ -d "$PROJ/.epico/stories/005-lockfile" ]
  [ ! -d "$PROJ/.epico/archive/005-lockfile" ]
  # Reported at once - the default timeout is 30s, so anything near it means
  # the run sat waiting for a lock that could not exist.
  [ "$elapsed" -lt 10 ]
}


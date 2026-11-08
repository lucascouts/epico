#!/usr/bin/env bats
# Contract tests for scripts/archive-story.sh: preflight, flags and the JSON contract; the derived manifest; the move and the status transition; the escaping rule; the superseded preflight state.
# The contract and the fixtures are in tests/lib/archive-story-common.sh.

bats_require_minimum_version 1.5.0
. "$BATS_TEST_DIRNAME/lib/archive-story-common.sh"

# --- Preflight, flags, JSON contract ---

@test "help flag exits 0" {
  run bash "$ARCHIVE_SH" --help
  [ "$status" -eq 0 ]
}

@test "unknown flag exits 2 with nothing moved" {
  make_story 005-flagged complete
  run bash "$ARCHIVE_SH" .epico/stories/005-flagged --bogus
  [ "$status" -eq 2 ]
  [ -d "$PROJ/.epico/stories/005-flagged" ]
  [ ! -d "$PROJ/.epico/archive/005-flagged" ]
}

@test "incomplete story without --force is refused with the open count" {
  make_story 005-open incomplete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-open
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  # The refusal reports the open items count (2 in this fixture).
  echo "$output" | grep -qi 'open'
  echo "$output" | grep -q '2'
  [ -d "$PROJ/.epico/stories/005-open" ]
  [ ! -d "$PROJ/.epico/archive/005-open" ]
}

@test "a done story that was never validated is refused, naming validate and --force" {
  # `done` means the run closed its boxes, not that anyone checked the result.
  make_story 005-unvalidated complete
  sed -i 's/^status: validated$/status: done/' "$PROJ/.epico/stories/005-unvalidated/story.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-unvalidated
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | contains("not validated") and contains("validate 005") and contains("--force")' > /dev/null
  [ -d "$PROJ/.epico/stories/005-unvalidated" ]
  [ ! -e "$MANIFEST" ]
}

@test "a superseded story archives only through --force, which records the reason" {
  make_story 005-absorbed complete
  sed -i 's/^status: validated$/status: superseded/' "$PROJ/.epico/stories/005-absorbed/story.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-absorbed
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-absorbed --force "absorbed by 012"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.overrides_used == ["force"] and .manifest_entry.status == "superseded"' > /dev/null
  grep -q 'absorbed by 012' "$MANIFEST"
}

@test "a validated story with a box reopened since is still refused" {
  make_story 005-reopened incomplete
  sed -i 's/^status: in-progress$/status: validated/' "$PROJ/.epico/stories/005-reopened/story.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-reopened
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused" and (.reason | contains("still open"))' > /dev/null
}

@test "already-archived story is refused untouched" {
  mkdir -p "$PROJ/.epico/archive/004-old"
  cat > "$PROJ/.epico/archive/004-old/story.md" <<'EOF'
---
story: old
status: archived
---
EOF
  run --separate-stderr bash "$ARCHIVE_SH" .epico/archive/004-old
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  # Nothing modified - the story stays, no manifest springs into existence.
  [ -d "$PROJ/.epico/archive/004-old" ]
  [ ! -e "$MANIFEST" ]
}

# Spike preflight.
# A spike is complete for archive purposes ONLY via its Verdict - `wont-do`, or
# `promote` with a `promoted-to:` target recorded.

@test "spike with an open verdict is refused" {
  make_spike 005-spike-open open
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-spike-open
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  [ -d "$PROJ/.epico/stories/005-spike-open" ]
  [ ! -d "$PROJ/.epico/archive/005-spike-open" ]
  [ ! -e "$MANIFEST" ]
}

@test "spike promoted without promoted-to is refused" {
  make_spike 005-spike-nopromo promote
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-spike-nopromo
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | grep -q 'promoted-to'
  [ -d "$PROJ/.epico/stories/005-spike-nopromo" ]
  [ ! -d "$PROJ/.epico/archive/005-spike-nopromo" ]
}

@test "spike with a wont-do verdict passes preflight" {
  # Open probe box: only the verdict rule can make this complete.
  make_spike 005-spike-wontdo wont-do "" " "
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-spike-wontdo
  # Preflight is the whole assertion: a terminal verdict is never a refusal.
  # The exit code belongs to the later pipeline steps, not to preflight.
  echo "$output" | jq -e '.status != "refused"' > /dev/null
}

@test "spike promoted with promoted-to passes preflight" {
  make_spike 005-spike-promo promote 012 " "
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-spike-promo
  echo "$output" | jq -e '.status != "refused"' > /dev/null
}

# --- Derived manifest, append-before-move ---

@test "manifest entry counts are derived from the checkboxes" {
  make_story 005-counts complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-counts
  [ "$status" -eq 0 ]
  [ -f "$MANIFEST" ]
  grep -Eq 'tasks_total:[[:space:]]*3' "$MANIFEST"
  grep -Eq 'tasks_closed:[[:space:]]*2' "$MANIFEST"
  grep -Eq 'tasks_deferred:[[:space:]]*1' "$MANIFEST"
}

@test "forced archive records the true open count and the reason" {
  make_story 005-forced incomplete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-forced --force "schedule pressure"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.moved == true' > /dev/null
  [ -d "$PROJ/.epico/archive/005-forced" ]
  # Totals expose the truth (3 total, only 1 closed => 2 still open).
  grep -Eq 'tasks_total:[[:space:]]*3' "$MANIFEST"
  grep -Eq 'tasks_closed:[[:space:]]*1' "$MANIFEST"
  # The --force reason lands in the manifest entry.
  grep -q 'schedule pressure' "$MANIFEST"
}

@test "manifest is created with the never-recycled policy header" {
  make_story 005-header complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-header
  [ "$status" -eq 0 ]
  [ -f "$MANIFEST" ]
  grep -qi 'never recycled' "$MANIFEST"
}

@test "manifest append failure aborts before anything moves" {
  make_story 005-interrupt complete
  mkdir -p "$PROJ/.epico/archive"
  chmod 555 "$PROJ/.epico/archive"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-interrupt
  # The append is before the move; an unappendable manifest means no move.
  [ "$status" -ne 0 ]
  echo "$output" | jq -e . > /dev/null
  [ -d "$PROJ/.epico/stories/005-interrupt" ]
  [ ! -d "$PROJ/.epico/archive/005-interrupt" ]
}

@test "interrupted archive keeps its entry and the re-run completes it once" {
  # The other half of append-before-move: the case above pins the append
  # FAILING; this pins the append SUCCEEDING and the move not completing - the state a kill between
  # step 5 and step 6 leaves behind.
  # The interruption is produced BY the script (a read-only stories/ lets the
  # append through and makes the rename fail) rather than hand-planted: a real
  # SIGKILL is racy - the mv wins the race on a warm tmpfs - and would flake.
  make_story 005-resume complete
  chmod 555 "$PROJ/.epico/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-resume
  chmod 755 "$PROJ/.epico/stories"
  [ "$status" -ne 0 ]
  # The entry is written; the story has NOT moved.
  [ -f "$MANIFEST" ]
  grep -q '005-resume' "$MANIFEST"
  [ -d "$PROJ/.epico/stories/005-resume" ]
  [ ! -d "$PROJ/.epico/archive/005-resume" ]
  # The re-run finishes that archive and does not append a second entry.
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-resume
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-resume" ]
  [ ! -d "$PROJ/.epico/stories/005-resume" ]
  [ "$(grep -c 'story: "005-resume"' "$MANIFEST")" -eq 1 ]
}

@test "deferred boxes are recorded as items, not just as a count" {
  # "3 deferred" tells a future reader nothing about what is still owed.
  # make_story's [~] box carries no qualifier; this adds one that does, so both
  # renderer branches run.
  make_story 005-deferred complete
  cat >> "$PROJ/.epico/stories/005-deferred/tasks.md" <<'EOF'
- [~] 4 - Register the callback URL (deferred: needs the provider live account)
EOF
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-deferred
  [ "$status" -eq 0 ]
  grep -Eq 'tasks_deferred:[[:space:]]*2' "$MANIFEST"
  grep -q 'Register the callback URL' "$MANIFEST"
  grep -q 'needs the provider live account' "$MANIFEST"
  echo "$output" | jq -e '.manifest_entry.deferred_items | length == 2' > /dev/null
  # Id, title and the qualified reason all survive into the item.
  echo "$output" | jq -e '.manifest_entry.deferred_items[1] | startswith("4 ")' > /dev/null
  echo "$output" | jq -e '.manifest_entry.deferred_items[1]
    | contains("Register the callback URL")
      and contains("(deferred: needs the provider live account)")' > /dev/null
}

@test "the entry reports the story's own frontmatter status, never a verdict" {
  # A forced archive of an in-progress story must say `in-progress` and show
  # the open boxes: the entry is derived from the artifact, never a declared
  # verdict.
  make_story 005-truth incomplete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-truth --force "schedule pressure"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.manifest_entry.status == "in-progress"' > /dev/null
  echo "$output" | jq -e '.manifest_entry.tasks_open == 2' > /dev/null
  grep -Eq 'status:[[:space:]]*"in-progress"' "$MANIFEST"
  grep -Eq 'tasks_open:[[:space:]]*2' "$MANIFEST"
}

# --- Move, history preservation, status transition ---

@test "complete story moves to .epico/archive with structured report" {
  make_story 005-move complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-move
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  [ -d "$PROJ/.epico/archive/005-move" ]
  [ ! -d "$PROJ/.epico/stories/005-move" ]
}

@test "moved artifacts carry status archived in frontmatter" {
  make_story 005-status complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-status
  [ "$status" -eq 0 ]
  grep -q '^status: archived' "$PROJ/.epico/archive/005-status/story.md"
}

@test "tracked story preserves git history across the move" {
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-hist complete
  git -C "$PROJ" add .epico
  git -C "$PROJ" commit -qm "seed story"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-hist
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-hist" ]
  git -C "$PROJ" add -A
  git -C "$PROJ" commit -qm "archive commit"
  # The rename is tracked - history from before the move is reachable.
  run git -C "$PROJ" log --follow --format=%s -- .epico/archive/005-hist/story.md
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'seed story'
}

@test "untracked story is moved without git" {
  git -C "$PROJ" init -q
  make_story 005-loose complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-loose
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-loose" ]
  [ ! -d "$PROJ/.epico/stories/005-loose" ]
  # Plain filesystem move - nothing staged in git for the story.
  run git -C "$PROJ" ls-files -- .epico/archive/005-loose
  [ -z "$output" ]
}

# The `preserves git history` case above also passes with a plain `mv`. It
# commits first (`git add -A` + commit), and git then recovers the rename by
# CONTENT SIMILARITY - so `git log --follow` succeeds whichever
# branch ran, and the case cannot tell `git mv` from `mv`. The cases below
# inspect the index BEFORE anything is committed, where only `git mv` can have
# left a trace, which is what actually pins history preservation.

@test "tracked move stages the rename in git before anything is committed" {
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-staged complete
  git -C "$PROJ" add .epico
  git -C "$PROJ" commit -qm "seed story"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-staged
  [ "$status" -eq 0 ]
  # No `git add` runs here on purpose: a plain `mv` leaves the index completely
  # untouched (an unstaged ` D` plus an untracked directory), so anything
  # staged at all can only have come from `git mv`. `-M` forces rename
  # detection on the command line, so no repo or global config can change the
  # answer (status.renames / diff.renames are irrelevant here).
  run git -C "$PROJ" diff --cached -M --name-status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^R.*\.epico/stories/005-staged/story\.md.*\.epico/archive/005-staged/story\.md'
  echo "$output" | grep -q '^R.*\.epico/stories/005-staged/tasks\.md.*\.epico/archive/005-staged/tasks\.md'
}

@test "untracked story in a repo leaves the index untouched" {
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-noindex complete
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-noindex
  [ "$status" -eq 0 ]
  # The mirror image of the case above - it is the pair that makes
  # either one a discriminator rather than a tautology.
  run git -C "$PROJ" diff --cached -M --name-status
  [ -z "$output" ]
  [ -d "$PROJ/.epico/archive/005-noindex" ]
}

@test "partially tracked story still takes the git branch" {
  # The rule, stated: ANY tracked file under the story dir means `git mv`.
  # `git mv` on a directory is one rename(2) of the whole directory, so the
  # untracked files travel with it exactly as `mv` would move them while the
  # tracked ones keep their history - a strict superset of the plain branch.
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-partial complete
  git -C "$PROJ" add .epico
  git -C "$PROJ" commit -qm "seed story"
  echo 'work-tree scratch, committed nowhere' > "$PROJ/.epico/stories/005-partial/notes.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-partial
  [ "$status" -eq 0 ]
  # The tracked half keeps its history...
  run git -C "$PROJ" diff --cached -M --name-status
  echo "$output" | grep -q '^R.*005-partial/story\.md'
  # ...and the untracked file rides along with the directory rename.
  [ -f "$PROJ/.epico/archive/005-partial/notes.md" ]
  [ ! -d "$PROJ/.epico/stories/005-partial" ]
}

@test "legacy artifact without a status field has one added, in every artifact" {
  # Legacy stories may carry no `status:` at all. The transition must ADD the field there, not silently skip the file
  # - a skipped artifact would sit in archive/ claiming nothing forever.
  local dir="$PROJ/.epico/stories/005-legacy"
  mkdir -p "$dir"
  cat > "$dir/story.md" <<'EOF'
---
story: legacy
version: 1
created: 2026-08-01
---

# Story - legacy fixture
status: this line is body text, not frontmatter
EOF
  cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-01
---

## Task List
- [x] 1 - Done
EOF
  # No status field means nothing says it was validated: --force carries it.
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-legacy --force "legacy story, predates status"
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-legacy"
  # One story, one status: EVERY artifact carrying frontmatter gets the field.
  grep -q '^status: archived' "$arch/story.md"
  grep -q '^status: archived' "$arch/tasks.md"
  # Exactly once, and inside the frontmatter block...
  [ "$(sed -n '2,/^---$/p' "$arch/story.md" | grep -c '^status: archived')" -eq 1 ]
  # ...so a body line that merely starts with `status:` is left alone.
  grep -q '^status: this line is body text' "$arch/story.md"
}

# ============================================================================
# Regression cases: each pins a failure mode of the preflight, manifest and
# move code above.
# ============================================================================

# --- One escaping rule that BOTH formats accept ---

@test "control characters in a forced reason keep the report and the manifest parseable" {
  # A --force reason is arbitrary user input by definition - a paste from a
  # coloured terminal carries ESC (0x1b). Escaping only \n \r \t left every
  # other C0 byte raw, and the run still reported exit 0: the story archived
  # behind a manifest.yaml no YAML parser would ever load again, under a tree
  # that is deliberately hard to repair.
  # DEL (0x7f) and the C1 block are here too because they are the half JSON
  # accepts and YAML does not - valid stdout, permanently broken manifest, no
  # signal at all to the consumer.
  make_story 005-ctl incomplete
  local reason
  reason=$(printf 'rushed \033[1mrelease\033[0m del=\177 c1=\302\206 bs=\b ff=\f')
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-ctl --force "$reason"
  [ "$status" -eq 0 ]
  # stdout is still JSON...
  echo "$output" | jq -e . > /dev/null
  # ...and it round-trips: the escapes decode back to the bytes that went in.
  echo "$output" | jq -e '.manifest_entry.forced_reason | contains("[1mrelease")' > /dev/null
  echo "$output" | jq -e '.manifest_entry.forced_reason | contains("del=")' > /dev/null
  echo "$output" | jq -e '.manifest_entry.forced_reason | contains("c1=")' > /dev/null
  # ...and the manifest is loadable YAML carrying the same value.
  python3 -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
r = d["archived"][0]["forced_reason"]
assert "[1mrelease" in r, r
assert "del=" in r, r
assert "c1=" in r, r
assert "bs=\b" in r and "ff=\f" in r, r
' "$MANIFEST"
}

# --- The superseded preflight state ---
# `superseded` is the third word in assess_completion's status alternation, and
# supersede mode depends on it: it offers the archive by DELEGATING to this
# script, so the offer is only honest if `superseded` clears the completion
# gate here.
#
# TWO cases, because one cannot do both jobs:
#   - the canonical post-supersede shape has every box closed, so BOX_OPEN is 0
#     and the LATER `elif [[ "$BOX_OPEN" -eq 0 ]]` branch would carry it even
#     with `superseded` deleted from the alternation. It pins the realistic
#     artifact, not the word.
#   - the second keeps one box open, so the status branch is the ONLY thing
#     that can complete it. That is the mutation guard: deleting `superseded`
#     turns it red (the archive is refused with the open count).
# Supersede itself does not write the interrupted shape (it closes the boxes
# before flipping the status, so the status write is the commit point), but
# this gate is a READER, and the shape still arrives: a hand-edited
# frontmatter, an artifact predating the op. Archive must accept it because
# assess_completion takes the status OR the boxes, never both - a `status:`
# naming a completion state carries the story through whatever the boxes say.

# make_superseded_story <dir-name> <MMM> [leftover-open-box]
# The artifacts as the supersede op leaves them (references/supersede-mode.md,
# Closure + Walkthrough): `status: superseded` plus the machine-readable
# `superseded-by: MMM` companion in EVERY artifact with frontmatter, and every
# open sub-task closed on its own line as a terminal `[~] ... (superseded-by:
# MMM)` - the checkbox grammar, verbatim.
# A non-empty third argument leaves box 3.1 OPEN - the status-written,
# closures-unfinished shape described above, however it came to be written.
make_superseded_story() {
  local dir="$PROJ/.epico/stories/$1" by="$2" leftover="${3:-}"
  mkdir -p "$dir"
  {
    echo '---'
    echo "story: ${1#*-}"
    echo 'type: feature'
    echo 'scale: standard'
    echo 'version: 1'
    echo 'created: 2026-05-14'
    echo 'status: superseded'
    echo "superseded-by: $by"
    echo '---'
    echo
    echo '# Story - superseded fixture'
  } > "$dir/story.md"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-05-14'
    echo 'status: superseded'
    echo "superseded-by: $by"
    echo '---'
    echo
    echo '## Task List'
    echo '- [x] 1.1 - Parse the legacy CSV export'
    echo "- [~] 2.1 - Map legacy fields to the new schema (superseded-by: $by)"
    echo "- [~] 2.2 - Validate mapped rows (superseded-by: $by)"
    if [ -n "$leftover" ]; then
      echo '- [ ] 3.1 - Import against the live feed'
    else
      echo "- [~] 3.1 - Import against the live feed (superseded-by: $by)"
    fi
  } > "$dir/tasks.md"
  return 0
}

@test "a superseded story is refused alone and archives with the offer's --force" {
  # The walkthrough's own fixture: 042 superseded by 051, one [x] survivor and
  # three boxes the op closed. Absorbed work was never validated, so the gate
  # refuses it; the step-5 offer passes the reason it names on acceptance.
  make_superseded_story 042-legacy-import 051
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/042-legacy-import
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused" and (.reason | contains("not validated"))' > /dev/null
  [ -d "$PROJ/.epico/stories/042-legacy-import" ]
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/042-legacy-import --force "superseded by 051"
  # A REAL archive, not merely a run that did not crash.
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.manifest_entry.forced_reason == "superseded by 051"' > /dev/null
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  [ -d "$PROJ/.epico/archive/042-legacy-import" ]
  [ ! -d "$PROJ/.epico/stories/042-legacy-import" ]
  # The entry records the story's OWN pre-archive status, so the manifest says
  # what the story was when it was archived, never a verdict this script coined.
  [ -f "$MANIFEST" ]
  grep -q 'story: "042-legacy-import"' "$MANIFEST"
  grep -Eq 'status:[[:space:]]*"superseded"' "$MANIFEST"
  echo "$output" | jq -e '.manifest_entry.status == "superseded"' > /dev/null
  # 4 boxes, none open: `superseded-by:` is terminal, so nothing stays owed.
  echo "$output" | jq -e '.tasks == {total: 4, closed: 1, deferred: 3, open: 0}' > /dev/null
  # The terminal qualifier survives verbatim into the recorded items, which is
  # what tells a future reader these were remapped, not abandoned.
  echo "$output" | jq -e '.manifest_entry.deferred_items | length == 3' > /dev/null
  echo "$output" | jq -e '.manifest_entry.deferred_items[0]
    | contains("Map legacy fields to the new schema")
      and contains("(superseded-by: 051)")' > /dev/null
  grep -q 'superseded-by: 051' "$MANIFEST"
}

@test "status superseded no longer clears the gate for a story whose closures were interrupted" {
  # THE MUTATION GUARD, inverted: `superseded` used to complete this story on
  # its own. One box is still `[ ]` and the status is not `validated`, so only
  # --force can carry it through — and the manifest says so.
  make_superseded_story 043-interrupted 051 leftover-open-box
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/043-interrupted
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/043-interrupted --force "superseded by 051"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "archived" and .moved == true' > /dev/null
  [ -d "$PROJ/.epico/archive/043-interrupted" ]
  [ ! -d "$PROJ/.epico/stories/043-interrupted" ]
  [ -f "$MANIFEST" ]
  grep -q 'story: "043-interrupted"' "$MANIFEST"
  grep -Eq 'status:[[:space:]]*"superseded"' "$MANIFEST"
  # The open box is REAL and recorded as such - the archive does not launder it.
  echo "$output" | jq -e '.tasks == {total: 4, closed: 1, deferred: 2, open: 1}' > /dev/null
  grep -Eq 'tasks_open:[[:space:]]*1' "$MANIFEST"
  # ...and the escape hatch is on the record, never implied by the status.
  echo "$output" | jq -e '.manifest_entry.overrides_used == ["force"]' > /dev/null
  echo "$output" | jq -e '.manifest_entry.forced_reason == "superseded by 051"' > /dev/null
}

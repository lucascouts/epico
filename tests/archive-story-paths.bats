#!/usr/bin/env bats
# Contract tests for scripts/archive-story.sh: a verdict with JSON on every path, derived values, the destination, git errors, CRLF artifacts, the resume's stdout and cheap hardening.
# The contract and the fixtures are in tests/lib/archive-story-common.sh.

bats_require_minimum_version 1.5.0
. "$BATS_TEST_DIRNAME/lib/archive-story-common.sh"

# --- A verdict, with JSON, on every path that could otherwise die silently ---

@test "an unreadable tasks.md is refused with JSON, not a bare non-zero" {
  # `census_tasks` guarded with `[[ -f ]]` and then redirected `done < "$file"`.
  # `-f` says the file EXISTS, not that it opens: a bare failed redirection at
  # top level under `set -e` killed the shell with ZERO bytes on stdout - the
  # one thing the output contract promises never happens.
  make_story 005-noread complete
  chmod 000 "$PROJ/.epico/stories/005-noread/tasks.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-noread
  chmod 644 "$PROJ/.epico/stories/005-noread/tasks.md"
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "refused" and .moved == false' > /dev/null
  echo "$output" | grep -q 'tasks.md'
  [ -d "$PROJ/.epico/stories/005-noread" ]
  [ ! -e "$MANIFEST" ]
}

@test "an unreadable clock blocks with JSON, not a bare non-zero" {
  # `ARCHIVED_AT=$(date -Iseconds)` takes the command's status, and `set -e` is
  # armed - so a `date` that fails (and `date -I` is GNU-only, so every BSD or
  # macOS host is that case) ended the run with no JSON at all.
  make_story 005-clock complete
  mkdir "$WORK/nodate"
  local t
  for t in /usr/bin/*; do ln -s "$t" "$WORK/nodate/${t##*/}" 2> /dev/null || true; done
  # rm first: writing THROUGH the symlink would try to overwrite /usr/bin/date.
  rm -f "$WORK/nodate/date"
  printf '#!/bin/sh\nexit 1\n' > "$WORK/nodate/date"
  chmod +x "$WORK/nodate/date"
  run --separate-stderr env PATH="$WORK/nodate" bash "$ARCHIVE_SH" .epico/stories/005-clock
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  # Fail-closed: an entry with no archived_at is a derived field the run cannot
  # support, so nothing is written and nothing moves.
  [ -d "$PROJ/.epico/stories/005-clock" ]
  [ ! -d "$PROJ/.epico/archive/005-clock" ]
}

# --- A derived value must appear in the artifact it was derived from ---

@test "a frontmatter value with a trailing comment is not squeezed into the manifest" {
  # `tr -d '[:space:]'` deleted whitespace INSIDE the value, not just at its
  # edges: `status: done  # closed early` became `done#closedearly`, which was
  # written verbatim into the permanent record - a derived field that appears
  # nowhere in the source artifact - and which no longer equals `validated`, so
  # the completion branch refused a story that was genuinely validated.
  make_story 005-cmt complete
  sed -i 's/^status: validated$/status: validated  # closed early/' \
    "$PROJ/.epico/stories/005-cmt/story.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-cmt
  # The status branch sees `validated`, so the story archives without --force.
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.manifest_entry.status == "validated"' > /dev/null
  grep -Eq 'status:[[:space:]]*"validated"' "$MANIFEST"
  # NOT `! grep -q …`: bash's set -e exempts a command inverted with `!`, so
  # such an assertion is a NO-OP anywhere but the last line of the body — and
  # one appended line turns even a working one into silence. See the secrets
  # guard section.
  [[ "$(cat "$MANIFEST")" != *closedearly* ]]
}

# --- The destination is derived from the story's PHYSICAL location ---

@test "a symlinked story directory is refused, not archived outside the project" {
  # `pwd -P` resolves the symlink and EPICO_DIR was re-derived from the physical
  # path, so a `.epico/stories/005-sym -> /elsewhere/shared/stories/005-sym`
  # created /elsewhere/shared/archive/, wrote the manifest there, reported
  # `path: .epico/stories/005-sym` (where the story is NOT) and exited 0 - with
  # the destination outside the tree hook-archive-guard.sh protects.
  mkdir -p "$WORK/elsewhere/stories"
  make_story 005-real complete
  mv "$PROJ/.epico/stories/005-real" "$WORK/elsewhere/stories/005-sym"
  ln -s "$WORK/elsewhere/stories/005-sym" "$PROJ/.epico/stories/005-sym"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-sym
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused" and .moved == false' > /dev/null
  echo "$output" | grep -qi 'symlink'
  # Nothing was created anywhere: not in the project, not at the target.
  [ ! -d "$PROJ/.epico/archive" ]
  [ ! -e "$WORK/elsewhere/archive" ]
  [ -d "$WORK/elsewhere/stories/005-sym" ]
}

# --- A git error is not the same answer as "untracked" ---

@test "an ambient GIT_DIR does not send the story down the plain branch" {
  # `git -C <dir>` sets the working directory; it does NOT override GIT_DIR /
  # GIT_WORK_TREE / GIT_INDEX_FILE. Any run from a git hook or from
  # `git rebase --exec` exports them, so the probe answered about a DIFFERENT
  # repository - and a tracked story took the plain `mv`, silently dropping the
  # history the git branch exists to preserve (or staged the rename into a
  # foreign index).
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-env complete
  git -C "$PROJ" add .epico
  git -C "$PROJ" commit -qm "seed story"
  mkdir "$WORK/other"
  git -C "$WORK/other" init -q
  run --separate-stderr env GIT_DIR="$WORK/other/.git" GIT_WORK_TREE="$WORK/other" \
    bash "$ARCHIVE_SH" .epico/stories/005-env
  [ "$status" -eq 0 ]
  # The rename is staged in the story's OWN repository...
  run git -C "$PROJ" diff --cached -M --name-status
  echo "$output" | grep -q '^R.*005-env/story\.md'
  # ...and the unrelated repository's index was never touched.
  run git -C "$WORK/other" diff --cached --name-status
  [ -z "$output" ]
}

@test "a tracked story whose trackedness git cannot answer is blocked, never guessed" {
  # `ls-files --error-unmatch` exits 1 for "untracked" and 128 for "could not
  # answer" (story inside a submodule, path outside the work tree, unreadable
  # index). Collapsing both into "take the plain branch" fails in the UNSAFE
  # direction, so 128 blocks instead.
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email test@example.com
  git -C "$PROJ" config user.name "Test"
  make_story 005-unreadable complete
  git -C "$PROJ" add .epico
  git -C "$PROJ" commit -qm "seed story"
  chmod 000 "$PROJ/.git/index"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-unreadable
  chmod 644 "$PROJ/.git/index"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  [ -d "$PROJ/.epico/stories/005-unreadable" ]
  [ ! -d "$PROJ/.epico/archive/005-unreadable" ]
}

# --- CRLF artifacts are transitioned, and a partial pass is not silent ---

@test "a CRLF artifact gets status archived instead of being silently skipped" {
  # `head -1 | grep -q '^---$'` fails on `---\r`, so on a checkout with
  # core.autocrlf=true the artifact was skipped - and the story archived with
  # story.md still claiming `done` while tasks.md said `archived`. The
  # "nothing applied" note stayed silent, because something HAD been applied.
  make_story 005-crlf complete
  python3 -c '
import sys
p = sys.argv[1]
d = open(p, "rb").read().replace(b"\n", b"\r\n")
open(p, "wb").write(d)
' "$PROJ/.epico/stories/005-crlf/story.md"
  grep -qa $'^---\r$' "$PROJ/.epico/stories/005-crlf/story.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-crlf
  [ "$status" -eq 0 ]
  local arch="$PROJ/.epico/archive/005-crlf"
  # One story, one status - both artifacts agree, whatever their line endings.
  grep -q $'^status: archived\r$' "$arch/story.md"
  grep -q '^status: archived$' "$arch/tasks.md"
  # ...and the file keeps its CRLF endings rather than growing a mixed one.
  # `run` + an explicit status check, not `! grep …` — see the note at the
  # closedearly assertion: an inverted command is exempt from set -e.
  run grep -qa $'[^\r]$' "$arch/story.md"
  [ "$status" -ne 0 ]
}

@test "an artifact left without frontmatter is named, not passed over in silence" {
  # The note must fire on a PARTIAL application too, not only when NOTHING was
  # applied. A partial application is the worse case: the story sits in archive/ with its own artifacts
  # contradicting each other, which is the divergence validate-story.sh reports.
  make_story 005-partialfm complete
  printf '# Plain notes, no frontmatter block\n' \
    > "$PROJ/.epico/stories/005-partialfm/notes.md"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-partialfm
  [ "$status" -eq 0 ]
  grep -q '^status: archived' "$PROJ/.epico/archive/005-partialfm/story.md"
  # The skipped artifact is named on stderr, with the divergence spelled out.
  echo "$stderr" | grep -q 'notes.md'
  echo "$stderr" | grep -qi 'disagree'
}

# --- On the resume path, stdout describes what is actually RECORDED ---

@test "the resumed report describes the recorded entry, not a fresh derivation" {
  # Both renderings read the live variables, so a resume re-derived the entry
  # and reported values the manifest does not hold: archived_at always differed
  # (date re-runs) and so did every flag whenever the two runs were invoked
  # differently.
  make_story 005-recorded complete
  chmod 555 "$PROJ/.epico/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-recorded \
    --force "waiting on vendor" --keep-logs
  chmod 755 "$PROJ/.epico/stories"
  [ "$status" -ne 0 ]
  [ -d "$PROJ/.epico/stories/005-recorded" ]
  local recorded_at
  recorded_at=$(grep -m1 'archived_at:' "$MANIFEST" | sed 's/.*archived_at: "\(.*\)"/\1/')
  [ -n "$recorded_at" ]
  # Re-run with DIFFERENT flags: the resume must report run 1's entry.
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-recorded \
    --force "giving up" --allow-heavy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/005-recorded" ]
  echo "$output" | jq -e '.manifest_entry.forced_reason == "waiting on vendor"' > /dev/null
  echo "$output" | jq -e '.manifest_entry.overrides_used == ["force","keep-logs"]' > /dev/null
  echo "$output" | jq --arg t "$recorded_at" -e '.manifest_entry.archived_at == $t' > /dev/null
  # Still exactly one entry, and the file is untouched by the second run.
  [ "$(grep -c 'story: "005-recorded"' "$MANIFEST")" -eq 1 ]
  grep -q 'forced_reason: "waiting on vendor"' "$MANIFEST"
  [[ "$(cat "$MANIFEST")" != *"giving up"* ]]
}

@test "a refusal names the orphan entry an interrupted forced run left behind" {
  # Run 1 with --force dies before the move; run 2 WITHOUT --force is refused
  # at preflight and never reaches the resume, so the orphan entry has no
  # command of its own to clean it. The refusal has to say so.
  make_story 005-orphan incomplete
  chmod 555 "$PROJ/.epico/stories"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-orphan --force "vendor"
  chmod 755 "$PROJ/.epico/stories"
  [ "$status" -ne 0 ]
  grep -q '005-orphan' "$MANIFEST"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-orphan
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "refused"' > /dev/null
  echo "$output" | jq -e '.reason | contains("interrupted run")' > /dev/null
  echo "$output" | jq -e '.reason | contains("--force")' > /dev/null
}

# --- Cheap hardening ---

@test "a story directory whose name starts with a dash is reachable after --" {
  make_story -005-dashy complete
  run --separate-stderr bash "$ARCHIVE_SH" -- .epico/stories/-005-dashy
  [ "$status" -eq 0 ]
  [ -d "$PROJ/.epico/archive/-005-dashy" ]
}

@test "a DANGLING symlink in the destination slot blocks before the move" {
  # The pre-move check used `[[ -e ]]`, which FOLLOWS the link and is false for
  # a dangling one - so the move went ahead and failed with a bare ENOTDIR.
  make_story 005-dangle complete
  mkdir -p "$PROJ/.epico/archive"
  ln -s "$PROJ/.epico/archive/nowhere-at-all" "$PROJ/.epico/archive/005-dangle"
  run --separate-stderr bash "$ARCHIVE_SH" .epico/stories/005-dangle
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "blocked" and .moved == false' > /dev/null
  echo "$output" | grep -q 'already exists'
  [ -d "$PROJ/.epico/stories/005-dangle" ]
}


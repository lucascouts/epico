#!/usr/bin/env bash
# Runs a story's Validation commands and generated-gate commands, and writes the
# Auditor's Part 1 report — so the deterministic half of validation costs seconds
# instead of a sub-agent's turns.
#
#   validate-run.sh --story <dir> [--only <id,id,...> | --since-last] [--timeout <s>]
#
# Reads tasks.md. Every [x] sub-task's `Validation:` field is run from its first
# backtick span — and a field with more than one span is JUDGE once that first
# command passes, since the script cannot know what "with the server running"
# asks of the second; its `Tests:` path must exist; its group's `Commit:` message must
# be in git log. A [~] sub-task is SKIP with its qualifier. Every Quality Gate
# whose text carries a backtick command is run the same way. What cannot be run
# — a prose check, a span that is a file name, a span holding a `<placeholder>`,
# a gate with no command — is JUDGE:
# the Auditor settles those, and only those. Entries sharing a command run it
# once per invocation and share its result: they check the same tree.
#
# Every run records its fixed point: `head` (the commit) and `tree` (the work
# tree outside .epico/, ignored files left out, as a git tree id written from a
# throwaway index — the user's index is never touched), and each entry's
# `source` line from tasks.md.
#
# --since-last revalidates from that fixed point. It diffs the recorded tree
# against the current one and re-runs the failed entries, the entries whose
# source changed or are new, and what the changed paths can reach:
#   unchanged      nothing outside .epico/ changed — nothing more
#   same-versions  only lockfiles changed, every resolved name@version the same
#                  (lib-lock-versions.sh) — every gate as well
#   code           anything else, or a lockfile that moved or cannot be read —
#                  everything
#   full           no fixed point to trust: no previous run, none recorded, the
#                  recorded tree gone, history rewritten, no git — everything
# Every other entry keeps its result, marked `kept`. The rule, its reason and
# each changed path with its class are written under `scope`: the proof that
# what was not re-run could not have changed.
#
# --only re-runs the named entries (sub-task ids, or gate:<text prefix>) and keeps
# every other entry of the previous run, with no proof — for a targeted check.
#
# Writes .draft/validation-run.json (the machine form) and
# .draft/validation-report.yaml (the schema validate-mode.md defines, with
# verdict pass | fail | pending — pending while a JUDGE entry is open), each
# through a temporary file and a rename.
# Output: one JSON line {verdict, pass, fail, skip, judge, report}, plus
# {scope, rerun, kept} under --since-last.
# Exit 0 on pass or pending, 1 on fail, 2 on bad usage.

set -euo pipefail

usage() { sed -n '5,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

STORY="" ONLY="" SINCE=0 TIMEOUT=300
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --only) ONLY="${2-}"; shift 2 ;;
    --since-last) SINCE=1; shift ;;
    --timeout) TIMEOUT="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "validate-run.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$STORY" ] || [ ! -f "$STORY/tasks.md" ]; then
  echo "validate-run.sh: --story <dir> is required and must hold tasks.md" >&2; exit 2
fi
if [ -n "$ONLY" ] && [ "$SINCE" = 1 ]; then
  echo "validate-run.sh: --only and --since-last cannot be combined — one names the entries, the other proves them" >&2; exit 2
fi
case "$TIMEOUT" in '' | *[!0-9]*) echo "validate-run.sh: --timeout takes whole seconds" >&2; exit 2 ;; esac
command -v jq >/dev/null || { echo "validate-run.sh: jq is required" >&2; exit 2; }
# shellcheck source=scripts/lib-lock-versions.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-lock-versions.sh"

STORY="$(cd "$STORY" && pwd)"
# The project root holds .epico/: stories live at .epico/stories/<dir> or
# .epico/archive/<dir>, so it is three levels up.
ROOT="$(cd "$STORY/../../.." && pwd)"
DRAFT="$STORY/.draft"
JSON="$DRAFT/validation-run.json" YAML="$DRAFT/validation-report.yaml"
mkdir -p "$DRAFT"

# One row per entry, fields split by \x1f: kind, id, box, command-or-text,
# tests-path, commit-msg, and the whole text when it holds more than one span. Not TAB: `read` folds runs of whitespace separators,
# which shifts every field after an empty one.
# Sub-task fields are collected until the next box; a group's Commit applies to
# the sub-task it is written under (the last one of the group, by convention).
entries() {
  awk '
    function flush() {
      if (id != "") printf "sub\037%s\037%s\037%s\037%s\037%s\037%s\n", id, box, val, tst, cmt, more
      id = ""; val = ""; tst = ""; cmt = ""; more = ""
    }
    function span(s,   a) { if (match(s, /`[^`]+`/)) return substr(s, RSTART + 1, RLENGTH - 2); return "" }
    function spans(s,   c) { c = s; return gsub(/`[^`]+`/, "", c) }
    /^## Quality Gates/ { flush(); gates = 1; next }
    /^## / { flush(); gates = 0; next }
    gates && /^- \[[ x~]\] / {
      b = substr($0, 4, 1); t = substr($0, 7)
      printf "gate\037%s\037%s\037%s\037\037\037%s\n", t, b, span(t), (spans(t) > 1 ? t : ""); next
    }
    /^[[:space:]]*- \[[ x~]\] [0-9]+\.[0-9]+/ {
      flush(); box = substr($0, index($0, "[") + 1, 1)
      s = $0; sub(/^[[:space:]]*- \[[ x~]\] /, "", s); split(s, w, /[ :—-]/); id = w[1]
      if (box == "~") { q = $0; sub(/.*\(/, "", q); sub(/[:)].*/, "", q); val = q }
      next
    }
    /^- \[[ x~]\] / { flush(); next }
    id != "" && /^[[:space:]]+- Validation:/ && box != "~" {
      val = span($0); if (val == "") val = "!" substr($0, index($0, ":") + 2)
      if (spans($0) > 1) more = substr($0, index($0, ":") + 2)
    }
    id != "" && /^[[:space:]]+- Tests:/ { t = $0; if (index(t, "·")) { t = substr(t, index(t, "·")); tst = span(t) } }
    id != "" && /^[[:space:]]+- Commit:/ { c = $0; sub(/^[^"]*"/, "", c); sub(/".*$/, "", c); cmt = c }
    END { flush() }' "$STORY/tasks.md"
}

runnable() {  # <command> — is its first word something the shell can run?
  local first
  # A `<job>`-style placeholder means the span describes a command rather than
  # being one: run, it fails on the placeholder and reads as the check failing.
  # A redirection (`cmd <in >out`) has a space or no closing `>` and passes.
  if printf '%s' "$1" | grep -qE '<[A-Za-z][A-Za-z0-9_-]*>'; then return 1; fi
  first="$(printf '%s' "$1" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//' | awk '{print $1}')"
  [ -n "$first" ] || return 1
  case "$first" in
    */*) [ -x "$ROOT/$first" ] || [ -x "$first" ] ;;
    *) command -v "$first" >/dev/null 2>&1 ;;
  esac
}

# Output goes to a file, not a pipe, and the command runs in its own session:
# a `cargo run &` inside a gate kept a captured pipe open until the timeout
# (300 s lost in a rust run). The session is killed once the command returns,
# so a server it started never outlives its check.
run_cmd() {  # <command> — prints "<exit>\t<evidence line>"
  local log sidf code evidence
  log="$(mktemp)" sidf="$(mktemp)"
  set +e
  # --fork makes setsid succeed even where this shell's job is a group leader;
  # the new session's leader writes its own pid, which names the group to kill.
  # shellcheck disable=SC2016  # $$ and $0 belong to the inner bash
  (cd "$ROOT" && setsid --fork --wait bash -c 'echo "$$" > "$0"; exec timeout "$1" bash -c "$2"' "$sidf" "$TIMEOUT" "$1") </dev/null >"$log" 2>&1
  code=$?
  set -e
  if [ -s "$sidf" ]; then kill -TERM -- "-$(cat "$sidf")" 2>/dev/null || true; fi
  if [ "$code" -eq 124 ]; then
    evidence="timed out after ${TIMEOUT}s"
  else
    evidence="$(tr -d '\r' < "$log" | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' | runner_totals)"
  fi
  rm -f "$log" "$sidf"
  printf '%s\t%s\n' "$code" "$(printf '%s' "$evidence" | cut -c1-200)"
}

# cargo prints one "test result:" per test binary and ends on the doc-test one,
# often "0 passed" — so the last line alone reads as if nothing ran. With more
# than one summary, they are added up; any other output keeps its last line.
runner_totals() {
  local out
  out="$(cat)"
  printf '%s' "$out" | grep -oE 'test result: [a-z]+\. [0-9]+ passed; [0-9]+ failed' |
    awk '{ p += $4; f += $6; n++ } END { if (n > 1) printf "cargo test: %d passed, %d failed in %d binaries", p, f, n }' |
    grep . || printf '%s' "$out" | awk 'NF' | tail -1
}


# The work tree as it is now, as a git tree id: tracked and untracked files,
# ignored ones and every .epico/ left out — the story's own bookkeeping is not
# code, and counting it would make every revalidation a full one. Built in a
# throwaway copy of the index (the copy keeps git's stat cache, so unchanged
# files are not hashed again); the user's index is never touched.
fingerprint() {
  local idx tmp tree=""
  tmp="$(mktemp)" || return 0
  idx="$(git -C "$TOP" rev-parse --git-path index)"
  case "$idx" in /*) ;; *) idx="$TOP/$idx" ;; esac
  if [ -f "$idx" ]; then cp "$idx" "$tmp"; else rm -f "$tmp"; fi
  if GIT_INDEX_FILE="$tmp" git -C "$TOP" add -A -- . ':(exclude,glob)**/.epico/**' >/dev/null 2>&1 &&
    GIT_INDEX_FILE="$tmp" git -C "$TOP" rm -r -q --cached --ignore-unmatch -- ':(glob)**/.epico/**' >/dev/null 2>&1; then
    tree="$(GIT_INDEX_FILE="$tmp" git -C "$TOP" write-tree 2>/dev/null || true)"
  fi
  rm -f "$tmp" "$tmp.lock"
  printf '%s' "$tree"
}

lock_same() {  # <path> — do the recorded tree and the current one resolve the same name@version set?
  local a b
  a="$(git -C "$TOP" cat-file -p "$PREV_TREE:$1" 2>/dev/null | lock_versions "${1##*/}")" || return 1
  b="$(git -C "$TOP" cat-file -p "$TREE:$1" 2>/dev/null | lock_versions "${1##*/}")" || return 1
  [ "$a" = "$b" ]
}

# Sets RULE, REASON and CHANGED (a JSON array of {path, class}) for
# --since-last. Anything it cannot prove falls back to `full`, with the reason:
# when a proof is missing, the slower correct path.
scope_rule() {
  local path class moved="" since="${PREV_HEAD:0:7}" rows=()
  if [ "$PREV_OK" != 1 ]; then RULE=full REASON="no previous run"; return; fi
  if [ -z "$TOP" ]; then RULE=full REASON="not a git repository"; return; fi
  if [ -z "$PREV_TREE" ] || [ -z "$TREE" ]; then RULE=full REASON="the previous run recorded no fixed point"; return; fi
  if ! git -C "$TOP" cat-file -e "$PREV_TREE^{tree}" 2>/dev/null; then
    RULE=full REASON="the recorded tree ${PREV_TREE:0:7} is gone from the repository"; return
  fi
  if [ -n "$PREV_HEAD" ] && ! git -C "$TOP" merge-base --is-ancestor "$PREV_HEAD" HEAD 2>/dev/null; then
    RULE=full REASON="history rewritten since $since: the recorded commit is not an ancestor of HEAD"; return
  fi
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "${path##*/}" in
      package-lock.json | npm-shrinkwrap.json | go.sum | Cargo.lock | uv.lock | poetry.lock | composer.lock | Gemfile.lock)
        class=lock
        lock_same "$path" || moved="${moved:+$moved, }$path" ;;
      *) class=code ;;
    esac
    rows+=("$path"$'\x1f'"$class")
  done < <(git -C "$TOP" diff-tree -r --name-only --no-renames "$PREV_TREE" "$TREE")
  CHANGED="$(printf '%s\n' "${rows[@]+"${rows[@]}"}" |
    jq -Rc 'select(length > 0) | split("\u001f") | {path: .[0], class: .[1]}' | jq -sc '.')"
  if [ "${#rows[@]}" -eq 0 ]; then
    RULE=unchanged REASON="nothing outside .epico/ changed since $since"
  elif printf '%s\n' "${rows[@]}" | grep -q $'\x1fcode$'; then
    RULE=code REASON="code changed since $since"
  elif [ -n "$moved" ]; then
    RULE=code REASON="a resolved version moved, or the lockfile cannot be read: $moved"
  else
    RULE=same-versions REASON="only lockfiles changed since $since, every resolved version the same"
  fi
}

prev_entry() {  # <kind> <id> — the previous run's entry, or nothing
  printf '%s' "$PREV" | jq -c --arg k "$1" --arg i "$2" 'first(.[] | select(.kind == $k and .id == $i)) // empty'
}

selected() {  # <kind> <id> <source json> — is this entry run (again)?
  if [ -n "$ONLY" ]; then
    local want IFS=','
    for want in $ONLY; do
      if [ "$1" = sub ] && [ "$want" = "$2" ]; then return 0; fi
      if [ "$1" = gate ] && [ "${want#gate:}" != "$want" ] && [ "${2#"${want#gate:}"}" != "$2" ]; then return 0; fi
    done
    return 1
  fi
  [ "$SINCE" = 1 ] || return 0
  case "$RULE" in full | code) return 0 ;; esac
  if [ "$RULE" = same-versions ] && [ "$1" = gate ]; then return 0; fi
  local prev
  prev="$(prev_entry "$1" "$2")"
  [ -n "$prev" ] || return 0
  [ "$(jq -r '.result' <<< "$prev")" != FAIL ] || return 0
  [ "$(jq -c '.source // null' <<< "$prev")" = "$3" ] || return 0
  return 1
}

# Entries sharing a command check the same tree in the same invocation: the
# command runs once and every entry naming it takes the result. A command that
# changes the tree for the next one is the story's defect, not a reason to run
# the same check twice.
declare -A RAN=()

check() {  # <kind> <id> <box> <value> <tests> <commit> <whole text if compound> <source json> — prints one JSON entry
  local kind=$1 id=$2 box=$3 val=$4 tst=$5 cmt=$6 more=$7 src=$8 result detail qualifier="" res code last first shared=""
  if [ "$box" = "~" ]; then
    result=SKIP qualifier="$val" detail="closed without the work"
  elif [ "$box" = " " ] && [ "$kind" = sub ]; then
    return 0  # not done yet; an open gate is exactly what validation settles
  elif [ -z "$val" ] || [ "${val#!}" != "$val" ] || ! runnable "$val"; then
    result=JUDGE detail="${val#!}"; [ -z "$detail" ] && detail="no command in the text"
  else
    if [ -n "${RAN[$val]+x}" ]; then
      IFS=$'\x1f' read -r code last first <<< "${RAN[$val]}"
      shared=" (run once, for $first)"
    else
      res="$(run_cmd "$val")"; code="${res%%$'\t'*}"; last="${res#*$'\t'}"
      RAN[$val]="$code"$'\x1f'"$last"$'\x1f'"$id"
    fi
    if [ "$code" -eq 0 ]; then result=PASS; else result=FAIL; fi
    detail="\`$val\` exit $code${last:+ — $last}$shared"
    if [ "$result" = PASS ] && [ -n "$more" ]; then result=JUDGE detail="$detail; the rest is not run: $more"; fi
  fi
  if [ "$kind" = sub ] && { [ "$result" = PASS ] || [ "$result" = JUDGE ]; }; then
    if [ -n "$tst" ] && [ ! -e "$ROOT/$tst" ]; then result=FAIL detail="test file missing: $tst"; fi
    if [ -n "$cmt" ] && ! git -C "$ROOT" log --fixed-strings --grep="$cmt" -1 --format=%h 2>/dev/null | grep -q .; then
      result=FAIL detail="commit not found: \"$cmt\""
    fi
  fi
  jq -nc --arg kind "$kind" --arg id "$id" --arg result "$result" --arg detail "$detail" --arg q "$qualifier" --argjson source "$src" \
    '{kind: $kind, id: $id, result: $result, qualifier: (if $q == "" then null else $q end), detail: $detail, source: $source}'
}

write_atomic() {  # <file> — stdin to <file> through a temporary file and a rename
  local tmp
  tmp="$(mktemp "$1.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$1"
}

# The fixed point of this run, and the previous run's.
TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
HEAD_SHA="" TREE=""
if [ -n "$TOP" ]; then
  HEAD_SHA="$(git -C "$TOP" rev-parse --verify -q HEAD 2>/dev/null || true)"
  TREE="$(fingerprint)"
fi
PREV='[]' PREV_HEAD="" PREV_TREE="" PREV_OK=0
if [ -f "$JSON" ] && jq -e 'type == "object"' "$JSON" >/dev/null 2>&1; then
  PREV="$(jq -c '.entries // []' "$JSON")"
  PREV_HEAD="$(jq -r '.head // empty' "$JSON")"
  PREV_TREE="$(jq -r '.tree // empty' "$JSON")"
  PREV_OK=1
fi
RULE="" REASON="" CHANGED='[]'
[ "$SINCE" = 1 ] && scope_rule
KEPT_NOTE="unchanged since ${PREV_HEAD:0:7}"

NEW="$(entries | while IFS=$'\x1f' read -r kind id box val tst cmt more; do
  src="$(jq -nc --arg box "$box" --arg command "$val" --arg tests "$tst" --arg commit "$cmt" --arg more "$more" \
    '{box: $box, command: $command, tests: $tests, commit: $commit, more: $more}')"
  if selected "$kind" "$id" "$src"; then check "$kind" "$id" "$box" "$val" "$tst" "$cmt" "$more" "$src"
  elif [ "$SINCE" = 1 ]; then prev_entry "$kind" "$id" | jq -c --arg k "$KEPT_NOTE" '. + {kept: $k}'
  else prev_entry "$kind" "$id"; fi
done | jq -sc '.')"

# "All task validations pass" is the sub-task results themselves: derived on
# every run — a revalidation included — so the Auditor never re-judges
# what the runs just proved, and a stale FAIL never outlives its fix.
NEW="$(printf '%s' "$NEW" | jq -c '
  ([.[] | select(.kind == "sub")]) as $subs
  | map(if .kind == "gate" and (.id | startswith("All task validations pass")) then
      (if any($subs[]; .result == "FAIL") then .result = "FAIL" | .detail = "a sub-task validation failed"
      elif any($subs[]; .result == "JUDGE") then .result = "JUDGE" | .detail = "waits on the JUDGE sub-tasks"
      else .result = "PASS" | .detail = "no FAIL in results[]" end) | del(.kept)
    else . end)')"
verdict="$(printf '%s' "$NEW" | jq -r 'if any(.[]; .result == "FAIL") then "fail" elif any(.[]; .result == "JUDGE") then "pending" else "pass" end')"
SCOPE=null
if [ "$SINCE" = 1 ]; then
  SCOPE="$(jq -nc --arg since "$PREV_HEAD" --arg rule "$RULE" --arg reason "$REASON" --argjson changed "$CHANGED" --argjson entries "$NEW" '
    {since: (if $since == "" then null else $since end), rule: $rule, reason: $reason, changed: $changed,
     rerun: [$entries[] | select(.kept == null) | .id], kept: [$entries[] | select(.kept != null) | .id]}')"
fi
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n --arg story "$(basename "$STORY")" --arg at "$NOW" --arg verdict "$verdict" --argjson entries "$NEW" \
  --arg head "$HEAD_SHA" --arg tree "$TREE" --argjson scope "$SCOPE" \
  '{story: $story, generated_at: $at, generated_by: "epico-validate-run",
    head: (if $head == "" then null else $head end), tree: (if $tree == "" then null else $tree end),
    verdict: $verdict, scope: $scope, entries: $entries}' | write_atomic "$JSON"

# JSON strings are valid YAML double-quoted scalars, so every value goes out
# through tojson and needs no escaping of its own.
jq -r '
  "story: \(.story | tojson)",
  "generated_at: \(.generated_at | tojson)",
  "generated_by: epico-validate-run",
  "head: \(.head | tojson)",
  "verdict: \(.verdict)",
  (if .scope then "scope: \(.scope.rule | tojson)", "scope_reason: \(.scope.reason | tojson)" else empty end),
  "results:",
  (.entries[] | select(.kind == "sub") |
    "  - task: \(.id | tojson)", "    result: \(.result)", "    qualifier: \(.qualifier // null | tojson)", "    detail: \(.detail | tojson)"),
  "gates:",
  (.entries[] | select(.kind == "gate") |
    "  - gate: \(.id | tojson)", "    result: \(.result)", "    evidence: \(.detail | tojson)")
' "$JSON" | write_atomic "$YAML"

jq -c --arg report "$YAML" '{verdict, pass: ([.entries[] | select(.result == "PASS")] | length),
  fail: ([.entries[] | select(.result == "FAIL")] | length), skip: ([.entries[] | select(.result == "SKIP")] | length),
  judge: ([.entries[] | select(.result == "JUDGE")] | length), report: $report}
  + (if .scope then {scope: .scope.rule, rerun: (.scope.rerun | length), kept: (.scope.kept | length)} else {} end)' "$JSON"
[ "$verdict" = fail ] && exit 1
exit 0

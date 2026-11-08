#!/usr/bin/env bash
# Resolves a story's `refs:` — `<doc>#<anchor>` — to a file and a line range.
#
# Usage: resolve-refs.sh --story <dir> | --root <dir> <ref>...
#
# `refs:` in tasks.md names the sections of the project's documents the story
# starts from. They are hints, never limits (references/context-discovery.md):
# the agent reads whatever else it needs, so nothing here refuses.
#
# <doc>, resolved through the same discovery claude-md.sh uses, at the root and
# under docs/:
#   ADR-<n>      adr/<n, zero-padded to 4>-*.md
#   <name>       <name>.md, or <name>-*.md (so `stages/03` finds stages/03-api.md)
#   <name>.md    that file
# More than one match is `ambiguous`, with every candidate named. A doc that is
# absolute or climbs out with `..` is `malformed`: refs name the project's own docs.
#
# <anchor>, outside fenced blocks:
#   a number (`5.2`)    the heading whose text starts with it, followed by a
#                       space, the end of the line, or a `.` that is itself
#                       followed by one (`## 1. Stack`) — so 4.1 never matches
#                       4.10, and 4 never matches 4.1; then, when no heading
#                       has it, the task line `- [.] **<id> ` of a stage file
#   anything else       a GitHub heading slug (`#decision`)
# A heading's section runs to the next heading of the same or a higher level; a
# task's to the next line indented no deeper than the task.
#
# Output: one JSON object {refs: [{ref, status, file, start, end, candidates}],
# unresolved}. status: found | no-doc | ambiguous | no-anchor | malformed.
# Exit 0 (a hint that does not resolve is reported, not refused); 2 bad usage.

set -euo pipefail

usage() { sed -n '4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

STORY="" ROOT="" REFS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --story) STORY="${2-}"; shift 2 ;;
    --root) ROOT="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "resolve-refs.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    *) REFS+=("$1"); shift ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "resolve-refs.sh: jq is required" >&2; exit 2; }

if [ -n "$STORY" ]; then
  [ -f "$STORY/tasks.md" ] || { echo "resolve-refs.sh: no tasks.md in $STORY" >&2; exit 2; }
  STORY=$(cd "$STORY" && pwd)
  case "$STORY" in */.epico/*) ROOT="${STORY%%/.epico/*}" ;; *) echo "resolve-refs.sh: $STORY is not under .epico/" >&2; exit 2 ;; esac
  # The frontmatter line, as validate-story.sh reads it: `refs: [a, b]`.
  line=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } /^refs:/ { sub(/^refs:[[:space:]]*/, ""); print; exit }' "$STORY/tasks.md")
  line=${line#[}; line=${line%]}
  IFS=',' read -r -a parts <<< "$line"
  for p in ${parts[@]+"${parts[@]}"}; do
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
    [ -n "$p" ] && REFS+=("$p")
  done
elif [ -z "$ROOT" ] || [ ${#REFS[@]} -eq 0 ]; then
  usage >&2; exit 2
fi
[ -d "$ROOT" ] || { echo "resolve-refs.sh: root not found: $ROOT" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)

# candidates <doc> — one relative path per line, every file the doc could mean.
candidates() {
  local doc=$1 base pat f
  if [[ "$doc" =~ ^ADR-([0-9]+)$ ]]; then
    printf -v base '%04d' "$((10#${BASH_REMATCH[1]}))"
    pat=("adr/$base-"*.md "docs/adr/$base-"*.md)
  elif [[ "$doc" == *.md ]]; then
    pat=("$doc" "docs/$doc")
  else
    pat=("$doc.md" "docs/$doc.md" "$doc-"*.md "docs/$doc-"*.md)
  fi
  for f in "${pat[@]}"; do [ -f "$f" ] && printf '%s\n' "$f"; done | LC_ALL=C sort -u
}

# The anchor search. Prints "start end" or nothing. Slugs follow GitHub's:
# lowercase, ASCII punctuation and the common Unicode dashes and quotes
# removed, each space a hyphen.
read -r -d '' FIND_AWK <<'AWK' || true
function level(s) { match(s, /^#+/); return RLENGTH }
function slug(s) {
  s = tolower(s)
  gsub(/—|–|“|”|‘|’|…|·/, "", s)
  gsub(/[!"#$%&'()*+,.\/:;<=>?@\[\\\]^`{|}~]/, "", s)
  gsub(/ /, "-", s)
  return s
}
function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
BEGIN { isnum = (a ~ /^[0-9]+(\.[0-9]+)*$/); n = 0 }
/^[ \t]*(```|~~~)/ { fence = !fence; lines[++n] = ""; kind[n] = "f"; next }
{ lines[++n] = $0; kind[n] = fence ? "f" : "t" }
END {
  for (i = 1; i <= n; i++) {
    if (kind[i] != "t" || lines[i] !~ /^#+[ \t]/) continue
    text = lines[i]; sub(/^#+[ \t]+/, "", text); sub(/[ \t]+#*[ \t]*$/, "", text)
    hit = 0
    if (isnum) {
      if (index(text, a) == 1) {
        rest = substr(text, length(a) + 1)
        hit = (rest == "" || rest ~ /^[ \t]/ || rest ~ /^\.([ \t]|$)/)
      }
    } else hit = (slug(text) == a)
    if (!hit) continue
    l = level(lines[i])
    for (j = i + 1; j <= n; j++) if (kind[j] == "t" && lines[j] ~ /^#+[ \t]/ && level(lines[j]) <= l) break
    print i, j - 1; exit
  }
  if (!isnum) exit
  for (i = 1; i <= n; i++) {
    if (kind[i] != "t" || index(lines[i], "**" a " ") == 0 || lines[i] !~ /^[ \t]*- \[.\] \*\*/) continue
    d = indent(lines[i]); last = i
    for (j = i + 1; j <= n; j++) {
      if (lines[j] ~ /^[ \t]*$/) continue
      if (indent(lines[j]) <= d) break
      last = j
    }
    print i, last; exit
  }
}
AWK

cd "$ROOT"
out='[]'
for ref in ${REFS[@]+"${REFS[@]}"}; do
  obj=$(jq -cn --arg r "$ref" '{ref: $r, status: "malformed", file: null, start: null, end: null, candidates: []}')
  # A doc outside the project is malformed, never looked up: `/etc/x` or `../x`.
  if [[ "$ref" == *#* && -n "${ref%%#*}" && -n "${ref#*#}" && "${ref%%#*}" != /* && "/${ref%%#*}/" != */../* ]]; then
    doc=${ref%%#*} anchor=${ref#*#}
    mapfile -t cands < <(candidates "$doc")
    if [ ${#cands[@]} -eq 0 ]; then
      obj=$(jq -c '.status = "no-doc"' <<< "$obj")
    elif [ ${#cands[@]} -gt 1 ]; then
      obj=$(jq -c '.status = "ambiguous" | .candidates = $ARGS.positional' --args "${cands[@]}" <<< "$obj")
    else
      range=$(awk -v a="$anchor" "$FIND_AWK" "${cands[0]}")
      if [ -n "$range" ]; then
        obj=$(jq -c --arg f "${cands[0]}" --argjson s "${range% *}" --argjson e "${range#* }" \
          '.status = "found" | .file = $f | .start = $s | .end = $e' <<< "$obj")
      else
        obj=$(jq -c --arg f "${cands[0]}" '.status = "no-anchor" | .file = $f' <<< "$obj")
      fi
    fi
  fi
  out=$(jq -c --argjson o "$obj" '. + [$o]' <<< "$out")
done
jq -c '{refs: ., unresolved: (map(select(.status != "found")) | length)}' <<< "$out"

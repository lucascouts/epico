#!/usr/bin/env bash
# The checks epico-doctor runs only under --deep: the ones that read across the
# project's documents, which the session-start doctor must stay too fast to run.
#
# Usage: doctor-deep.sh --root <project root>
#
#   refs, roadmap      each open story's `refs:` and `roadmap:` — the warnings
#                      validate-story.sh gives, so there is one parser for each
#   adr                a number two ADRs share; a `Supersedes: ADR-<n>` with no
#                      such ADR; an `## Enforcement` line that is not a typed
#                      bullet (`- check: \`<cmd>\`` or `- judgment-only: <why>`,
#                      references/memory-modes.md#sync-docs)
#   docs-frontmatter   PRD, ARCHITECTURE or ROADMAP without `version` or `as_of`
#   task-ids           one task ID on a task line in two places
#   gitpolicy-verdict  epico-gitpolicy's verdict when it is not `consistent`
#
# Output: one JSON finding per line, {severity: "warning", check, target,
# detail} — the shape doctor.sh collects. Exit 0; 2 on bad usage.

set -euo pipefail

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2-}"; shift 2 ;;
    -h | --help) sed -n '5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "doctor-deep.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "doctor-deep.sh: --root <dir> is required" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$ROOT"

finding() { jq -cn --arg c "$1" --arg t "$2" --arg d "$3" '{severity: "warning", check: $c, target: $t, detail: $d}'; }

# --- refs, roadmap: validate-story's own warnings for each open story ---
for t in .epico/stories/*/tasks.md; do
  [ -f "$t" ] || continue
  bash "$HERE/validate-story.sh" "$ROOT/${t%/tasks.md}" 2>/dev/null \
    | jq -r '.warnings[]? | select(test("frontmatter .(refs|roadmap).")) | [(if test("frontmatter .refs.") then "refs" else "roadmap" end), .] | @tsv' 2>/dev/null \
    | while IFS=$'\t' read -r check detail; do finding "$check" "$t" "$detail"; done || true
done

# --- adr ---
ADRS=()
for f in adr/[0-9][0-9][0-9][0-9]-*.md docs/adr/[0-9][0-9][0-9][0-9]-*.md; do [ -f "$f" ] && ADRS+=("$f"); done
if [ ${#ADRS[@]} -gt 0 ]; then
  while IFS= read -r num; do
    files=$(printf '%s\n' "${ADRS[@]}" | awk -F/ -v n="$num" 'index($NF, n "-") == 1' | paste -sd ' ' -)
    finding adr "ADR-$num" "ADR number $num is used by more than one file: $files — renumber the later one"
  done < <(printf '%s\n' "${ADRS[@]}" | awk -F/ '{ print substr($NF, 1, 4) }' | sort | uniq -d)
  for f in "${ADRS[@]}"; do
    while IFS= read -r target; do
      printf -v padded '%04d' "$((10#$target))"
      printf '%s\n' "${ADRS[@]}" | awk -F/ -v n="$padded" 'index($NF, n "-") == 1 { found = 1 } END { exit !found }' \
        || finding adr "$f" "Supersedes: ADR-$target names an ADR that does not exist"
    done < <(sed -nE 's/.*Supersedes:[[:space:]]*ADR-([0-9]+).*/\1/p' "$f")
    awk '/^## Enforcement[[:space:]]*$/ { on = 1; next } /^## / { on = 0 } on && NF' "$f" | while IFS= read -r line; do
      [[ "$line" =~ ^-\ check:\ \`[^\`]+\`(\ \(warn-only:\ [^\)]+\))?$ || "$line" =~ ^-\ judgment-only:\ .+ ]] \
        || finding adr "$f" "Enforcement line is not a typed bullet — use '- check: \`<command>\`' or '- judgment-only: <reason>': $line"
    done
  done
fi

# --- docs-frontmatter ---
for d in PRD.md docs/PRD.md ARCHITECTURE.md docs/ARCHITECTURE.md ROADMAP.md docs/ROADMAP.md; do
  [ -f "$d" ] || continue
  fm=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1' "$d")
  for key in version as_of; do
    grep -qE "^$key:[[:space:]]*[^[:space:]]" <<< "$fm" || finding docs-frontmatter "$d" "$d has no '$key:' in its frontmatter — the checkpoint bumps version and as_of when it changes the doc"
  done
done

# --- task-ids ---
TASK_DOCS=()
for f in ROADMAP.md docs/ROADMAP.md docs/stages/*.md; do [ -f "$f" ] && TASK_DOCS+=("$f"); done
if [ ${#TASK_DOCS[@]} -gt 0 ]; then
  awk 'match($0, /^[[:space:]]*- \[.\] \*\*[0-9]+(\.[0-9]+)+ /) { id = $0; sub(/^[[:space:]]*- \[.\] \*\*/, "", id); sub(/ .*/, "", id); print id "\t" FILENAME }' "${TASK_DOCS[@]}" \
    | sort | awk -F'\t' '{ files[$1] = files[$1] (files[$1] ? " " : "") $2; n[$1]++ } END { for (id in n) if (n[id] > 1) print id "\t" files[id] }' \
    | LC_ALL=C sort | while IFS=$'\t' read -r id files; do
        finding task-ids "$id" "task $id is written more than once: $files — the checkpoint cannot tell which one a story closes"
      done
fi

# --- gitpolicy-verdict ---
verdict=$(bash "$HERE/epico-gitpolicy.sh" 2>/dev/null | jq -r '.verdict // empty' 2>/dev/null || true)
if [ -n "$verdict" ] && [ "$verdict" != consistent ]; then
  finding gitpolicy-verdict .epico/.gitpolicy "the git policy lint reports $verdict — run epico-gitpolicy for the counts; init explains how to settle it"
fi
exit 0

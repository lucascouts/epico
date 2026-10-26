#!/usr/bin/env bash
# The new runtime dependencies between two revisions of a repository, and the
# ADRs that name them. A stage checkpoint runs it to catch a dependency nobody
# recorded a decision for.
#
# Usage: diff-dependencies.sh --base <rev> [--head <rev>] [--root <dir>]
#
#   --base  the revision the stage started from (required)
#   --head  the revision it ended at (default HEAD)
#   --root  the repository (default the current directory)
#
# Reads git objects only — `git ls-tree` and `git show` at each revision, never
# the working tree or the index — so the answer for two revisions never moves
# with uncommitted edits. Manifests are found at any depth, except under
# node_modules/ and vendor/ (vendored copies are someone else's choices):
#   package.json  go.mod  Cargo.toml  pyproject.toml  requirements.txt
#   Gemfile  composer.json
#
# Only runtime dependencies count (the parsers, one per format, live in
# lib-depdiff-parsers.sh with the rule for each). A name is new when the head's
# copy of a manifest lists it and the base's copy of the same path does not;
# a manifest absent at the base has every name new; version changes and
# removals are never reported. Python names compare lower-cased, as pip does.
# A manifest gone at the head adds nothing and is not read.
#
# Coverage: a new dependency is covered by each *.md directly under adr/ or
# docs/adr/ at the head revision whose text names it whole, case-insensitive.
#
# Output: one JSON object on stdout.
#   {"base": "<sha>", "head": "<sha>",
#    "adr_dir": ["adr", "docs/adr"] | null      the ADR directories found
#    "new": [{"name", "ecosystem", "manifest", "covered_by": ["<adr path>"…]}…],
#    "uncovered": [ the entries of new whose covered_by is empty, same shape ],
#    "unparsed": [{"manifest", "ecosystem", "revision": "base"|"head",
#                  "reason"}…]}
# ecosystem is one of npm, go, cargo, pypi, rubygems, composer. A manifest in
# unparsed contributes no name to new, at either revision.
#
# Exit 0 when the diff is printed; 1 when it cannot be taken — no temporary
# directory, an ADR whose object cannot be read; 2 on bad usage — a missing
# --base, a root that is not a git repository, a revision that does not
# resolve to a commit. Exits 1 and 2 print {"error": "<reason>"} on stdout.

set -euo pipefail

usage() { sed -n '6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# refuse <reason> — the bad-usage exit, with the reason in the JSON contract.
refuse() {
  jq -cn --arg e "diff-dependencies.sh: $1" '{error: $e}'
  exit 2
}

command -v jq >/dev/null 2>&1 || { echo '{"error": "diff-dependencies.sh: jq is required"}'; exit 2; }

BASE_REV="" HEAD_REV=HEAD ROOT=$PWD
while [ $# -gt 0 ]; do
  case "$1" in
    # A flag given last with no value counts as missing: shift past it alone.
    --base) BASE_REV="${2-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --head) HEAD_REV="${2-}"; shift $(($# > 1 ? 2 : 1)) ;;
    --root) ROOT="${2-}"; shift $(($# > 1 ? 2 : 1)) ;;
    -h | --help) usage; exit 0 ;;
    *) refuse "unknown argument: $1 — $(usage)" ;;
  esac
done
[ -n "$BASE_REV" ] || refuse "--base <rev> is required"
[ -n "$HEAD_REV" ] || refuse "--head needs a revision"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then refuse "root not found: $ROOT"; fi
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || refuse "not a git repository: $ROOT"

# resolve <rev> — the commit a revision names; an annotated tag peels to it,
# a tree or a blob does not. The caller refuses: a refusal inside the command
# substitution would print its JSON into the variable, not on stdout.
resolve() { git -C "$ROOT" rev-parse --verify --quiet "$1^{commit}" 2>/dev/null; }
BASE=$(resolve "$BASE_REV") || refuse "base revision does not resolve to a commit: $BASE_REV"
HEAD=$(resolve "$HEAD_REV") || refuse "head revision does not resolve to a commit: $HEAD_REV"

# Every list between the steps below lives in a file, never in one argument or
# one environment string: Linux caps either at 128 KiB, and a stage that adds a
# few thousand dependencies would end in "Argument list too long" with no JSON.
WORK=$(mktemp -d 2>/dev/null) || {
  jq -cn --arg e "diff-dependencies.sh: no temporary directory under ${TMPDIR:-/tmp}" '{error: $e}'
  exit 1
}
trap 'rm -rf "$WORK"' EXIT

# fail <reason> — the refusal exit: the repository could not be read whole.
fail() {
  jq -cn --arg e "diff-dependencies.sh: $1" '{error: $e}'
  exit 1
}

# manifests <commit> — tracked manifest paths, NUL-terminated (a path may hold
# a tab or a newline), from the whole tree whatever subdirectory --root names.
manifests() {
  local path
  git -C "$ROOT" ls-tree -r -z --full-tree --name-only "$1" | while IFS= read -r -d '' path; do
    case "/$path" in */node_modules/* | */vendor/*) continue ;; esac
    case "${path##*/}" in
      package.json | go.mod | Cargo.toml | pyproject.toml | requirements.txt | Gemfile | composer.json)
        printf '%s\0' "$path" ;;
    esac
  done
}

# blob <commit> <path> — a file's content at a revision, never from disk.
blob() { git -C "$ROOT" show "$1:$2"; }

# shellcheck source=scripts/lib-depdiff-parsers.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-depdiff-parsers.sh"

# ecosystem_of <path> — the registry a manifest's names belong to.
ecosystem_of() {
  case "${1##*/}" in
    package.json) echo npm ;;
    go.mod) echo go ;;
    Cargo.toml) echo cargo ;;
    pyproject.toml | requirements.txt) echo pypi ;;
    Gemfile) echo rubygems ;;
    composer.json) echo composer ;;
  esac
}

# names_at <commit> <path> — the manifest's runtime names, sorted; on a
# manifest its parser refuses, the reason and status 1.
names_at() {
  local parser out
  case "${2##*/}" in
    package.json) parser=depdiff_names_npm ;;
    go.mod) parser=depdiff_names_go ;;
    Cargo.toml) parser=depdiff_names_cargo ;;
    pyproject.toml) parser=depdiff_names_pyproject ;;
    requirements.txt) parser=depdiff_names_requirements ;;
    Gemfile) parser=depdiff_names_gemfile ;;
    composer.json) parser=depdiff_names_composer ;;
    *) return 0 ;;
  esac
  out=$(blob "$1" "$2" | "$parser") || { printf '%s' "$out" | tr '\n\t' '  '; return 1; }
  # Names are read back one per line: a name holding a tab or a carriage return
  # is no name a registry serves, and is refused rather than passed on. Tested
  # on the variable — a pipe into `grep -q` dies of SIGPIPE on a long list.
  case $out in *[$'\t\r']*)
    printf 'a dependency name holds a tab or a carriage return'; return 1 ;;
  esac
  printf '%s\n' "$out" | LC_ALL=C sort -u | sed '/^$/d'
}

# unparsed_entry <path> <ecosystem> <revision> <reason> — one JSON line.
unparsed_entry() {
  jq -cn --arg m "$1" --arg e "$2" --arg r "$3" --arg why "$4" \
    '{manifest: $m, ecosystem: $e, revision: $r, reason: $why}' >> "$WORK/unparsed.jsonl"
}

declare -A AT_BASE=()
while IFS= read -r -d '' path; do AT_BASE[$path]=1; done < <(manifests "$BASE")

# new.jsonl and unparsed.jsonl: one JSON object per line, each field set with
# --arg, so no character of a path or a reason can reach another field. A
# manifest gone at the head adds nothing and is not read; one absent at the
# base has every name new.
: > "$WORK/new.jsonl"; : > "$WORK/unparsed.jsonl"
while IFS= read -r -d '' path; do
  eco=$(ecosystem_of "$path")
  ok=1 base_names=""
  if ! head_names=$(names_at "$HEAD" "$path"); then
    unparsed_entry "$path" "$eco" head "$head_names"; ok=0
  fi
  if [ -n "${AT_BASE[$path]+set}" ] && ! base_names=$(names_at "$BASE" "$path"); then
    unparsed_entry "$path" "$eco" base "$base_names"; ok=0
  fi
  [ "$ok" -eq 1 ] || continue
  LC_ALL=C comm -13 <(printf '%s\n' "$base_names" | sed '/^$/d') <(printf '%s\n' "$head_names" | sed '/^$/d') \
    | jq -cR --arg e "$eco" --arg m "$path" '{name: ., ecosystem: $e, manifest: $m, covered_by: []}' \
    >> "$WORK/new.jsonl"
done < <(manifests "$HEAD")

# ADRs: the *.md files directly under adr/ and docs/adr/ at the head — the
# directories scripts/claude-md.sh lists as project docs.
ADR_DIRS=() ADRS=()
for d in adr docs/adr; do
  [ "$(git -C "$ROOT" cat-file -t "$HEAD:$d" 2>/dev/null)" = tree ] || continue
  ADR_DIRS+=("$d")
  while IFS= read -r -d '' entry; do
    # entry: "<mode> <type> <object>\t<path>"; a subdirectory is not an ADR.
    type=${entry#* } path=${entry#*$'\t'}
    [ "${type%% *}" = blob ] || continue
    case "$path" in *.md) ADRS+=("$path") ;; esac
  done < <(git -C "$ROOT" ls-tree -z --full-tree "$HEAD" -- "$d/")
done
ADR_DIR=$(printf '%s\n' ${ADR_DIRS[@]+"${ADR_DIRS[@]}"} | jq -R -s 'split("\n") | map(select(. != "")) | if . == [] then null else . end')

# cover.jsonl: one ["<name>", "<adr path>"] pair per line.
jq -r -s 'map(.name) | unique | .[]' "$WORK/new.jsonl" > "$WORK/names"
: > "$WORK/cover.jsonl"
if [ -s "$WORK/names" ]; then
  for adr in ${ADRS[@]+"${ADRS[@]}"}; do
    blob "$HEAD" "$adr" > "$WORK/adr" 2>/dev/null || fail "cannot read the ADR $adr at $HEAD"
    depdiff_covering "$WORK/names" < "$WORK/adr" | jq -cR --arg a "$adr" '[., $a]' >> "$WORK/cover.jsonl"
  done
fi

# uncovered: the entries of `new` whose covered_by is empty, the same objects,
# so a consumer reads one shape in both lists.
jq -n --arg base "$BASE" --arg head "$HEAD" --argjson adr_dir "$ADR_DIR" \
  --slurpfile new "$WORK/new.jsonl" --slurpfile unparsed "$WORK/unparsed.jsonl" \
  --slurpfile cover "$WORK/cover.jsonl" '
  (reduce $cover[] as $p ({}; .[$p[0]] += [$p[1]])) as $by
  | ($new | map(.covered_by = (($by[.name] // []) | unique)) | sort_by(.manifest, .name)) as $n
  | {base: $base, head: $head, adr_dir: $adr_dir,
     new: $n, uncovered: [$n[] | select(.covered_by == [])],
     unparsed: ($unparsed | sort_by(.manifest, .revision))}'

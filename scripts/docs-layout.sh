#!/usr/bin/env bash
# Writes the optional docs/ template that init offers a Standard or Full project.
#
# Usage: docs-layout.sh [--root <dir>] [--date YYYY-MM-DD] [--dry-run]
#
# The template lives in assets/templates/docs/: PRD, ARCHITECTURE and ROADMAP
# (frontmatter version + as_of), one file per stage under stages/, and ADRs
# under adr/ with Enforcement and Amendments. These are the shapes
# epico-checkpoint, the doc writer and claude-md.sh already read
# (references/checkpoint-mode.md, references/memory-modes.md#sync-docs), so a
# project started from it needs no migration later.
#
# Writes only what is missing, each file through a temporary file renamed over
# the target; an existing file is kept byte for byte and listed as kept.
# REFUSES a project that already keeps a ROADMAP (ROADMAP.md, docs/ROADMAP.md or
# docs/stages/*.md): its plan already has a shape, and an existing project
# migrates to this one only if its owner asks — through a story, not this script.
#
# Output: one JSON object {status: written|dry-run|refused, root, written, kept}
# or {status: refused, reason}. Exit 0 written or dry-run, 1 refused, 2 bad usage.

set -euo pipefail
# Bash 5.2 expands `&` in a ${var//pat/rep} replacement to the matched text; a
# project named `R&D` would come out as `R{{project}}D`.
shopt -u patsub_replacement 2>/dev/null || true

usage() { sed -n '4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ROOT=$PWD DATE="" DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2-}"; shift 2 ;;
    --date) DATE="${2-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "docs-layout.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "docs-layout.sh: root not found: $ROOT" >&2; exit 2; }
[ -n "$DATE" ] || DATE=$(date +%F)
[[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "docs-layout.sh: --date takes YYYY-MM-DD, got: $DATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "docs-layout.sh: jq is required" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd)
TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/templates/docs" && pwd)"
PROJECT=$(basename "$ROOT")

refuse() { jq -cn --arg r "$1" --arg root "$ROOT" '{status: "refused", root: $root, reason: $r}'; exit 1; }

for f in ROADMAP.md docs/ROADMAP.md "$ROOT"/docs/stages/*.md; do
  f=${f#"$ROOT/"}
  [ -f "$ROOT/$f" ] && refuse "the project already keeps a ROADMAP in $f — migrating it to the docs/ layout is a story of its own, asked for by the owner"
done

WRITTEN=() KEPT=()
while IFS= read -r src; do
  rel="docs/${src#"$TEMPLATES/"}"
  dst="$ROOT/$rel"
  if [ -e "$dst" ]; then KEPT+=("$rel"); continue; fi
  WRITTEN+=("$rel")
  [ "$DRY" = 1 ] && continue
  mkdir -p "$(dirname "$dst")"
  body=$(cat "$src"; printf x); body=${body%x}   # keep the trailing newline
  body=${body//\{\{date\}\}/$DATE}
  body=${body//\{\{project\}\}/$PROJECT}
  tmp=$(mktemp "$dst.XXXXXX")
  printf '%s' "$body" > "$tmp"
  mv "$tmp" "$dst"
done < <(find "$TEMPLATES" -type f -name '*.md' | LC_ALL=C sort)

status=written; [ "$DRY" = 1 ] && status=dry-run
jq -cn --arg s "$status" --arg root "$ROOT" \
  --args '{status: $s, root: $root,
           written: ($ARGS.positional | map(select(startswith("w:")) | .[2:])),
           kept: ($ARGS.positional | map(select(startswith("k:")) | .[2:]))}' \
  ${WRITTEN[@]+"${WRITTEN[@]/#/w:}"} ${KEPT[@]+"${KEPT[@]/#/k:}"}

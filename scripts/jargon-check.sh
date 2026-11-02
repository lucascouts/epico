#!/usr/bin/env bash
# Checks a layperson-facing text for process words (assets/jargon-terms.txt).
# Reads the text from --file or stdin; inline code spans and fenced blocks are
# skipped, because the command a beginner is told to type is not jargon.
#
# A term is allowed when the same text carries its LEGEND: a line of the form
# `*term* — what it means here` (also `**term**`, `:` or `-` instead of the dash,
# optionally behind `>` or a list marker). The legend line itself is not
# scanned. What reaches a beginner unexplained is the defect, not the word.
#
# --max-chars N also fails a text longer than N characters (code points, the
# code spans included: the requester reads them too). A layperson closing is
# checked with 600 — "mto texto" was the complaint in 13/14 runs of the
# 2026-10-30 SDD battery.
#
# Output: one JSON object {pass, hits: [{term, count}], explained: [term],
# chars, max_chars}. Exit 0 when every term found has a legend and the text
# fits, 1 when a term has none or the text is too long, 2 on bad usage. The orchestrator rewrites the closing — plain words, or a legend under
# the term — and runs this again until it exits 0.

set -euo pipefail

usage() { echo "Usage: jargon-check.sh [--file <path>] [--terms <path>] [--max-chars <n>]   (text on stdin when no --file)"; }

FILE="" MAX_CHARS="" TERMS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/jargon-terms.txt"
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="${2-}"; shift 2 ;;
    --terms) TERMS="${2-}"; shift 2 ;;
    --max-chars) MAX_CHARS="${2-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "jargon-check.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$MAX_CHARS" in
  '') ;;
  *[!0-9]* | 0) echo "jargon-check.sh: --max-chars needs a positive number: $MAX_CHARS" >&2; usage >&2; exit 2 ;;
esac
[ -r "$TERMS" ] || { echo "jargon-check.sh: term list not readable: $TERMS" >&2; exit 2; }
if [ -n "$FILE" ]; then
  [ -r "$FILE" ] || { echo "jargon-check.sh: not readable: $FILE" >&2; exit 2; }
  TEXT=$(cat "$FILE")
else
  TEXT=$(cat)
fi

# Drop fenced blocks, then inline code spans (the backticks are literal).
# shellcheck disable=SC2016
PROSE=$(printf '%s\n' "$TEXT" | awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } !f' | sed -E 's/`[^`]*`//g')

# Legend lines: the explained terms (lowercased), then the prose without them.
LEGEND_RE='^[[:space:]]*(>[[:space:]]*)?([-*][[:space:]]+)?[*_]{1,2}([^*_]+)[*_]{1,2}[[:space:]]*(—|–|:|-)[[:space:]]+[^[:space:]]'
EXPLAINED=$(printf '%s\n' "$PROSE" | sed -nE "s/${LEGEND_RE}.*/\\3/p" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sort -u)
PROSE=$(printf '%s\n' "$PROSE" | grep -vE "$LEGEND_RE" || true)

# explained <found> — true when the found word, or its singular, has a legend.
explained() {
  local w; w=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [ -n "$EXPLAINED" ] || return 1
  # Here-strings, not pipes: grep -q exits on the first match, and under
  # pipefail the writer's SIGPIPE (141) would read as "not explained" once the
  # legend list outgrows the pipe buffer.
  grep -qxF -- "$w" <<<"$EXPLAINED" && return 0
  grep -qxF -- "${w%s}" <<<"$EXPLAINED"
}

json_escape() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

HITS=() SEEN_EXPLAINED=()
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  mode=${line%%:*} re=${line#*:}
  flag=-E; [ "$mode" = ci ] && flag=-Ei
  found=$( { printf '%s\n' "$PROSE" | grep -o "$flag" -- "$re" 2>/dev/null || true; } )
  [ -n "$found" ] || continue
  kept=""
  while IFS= read -r w; do
    if explained "$w"; then SEEN_EXPLAINED+=("$w"); else kept+="$w"$'\n'; fi
  done <<< "$found"
  found=${kept%$'\n'}
  [ -n "$found" ] || continue
  n=$(printf '%s\n' "$found" | wc -l | tr -d ' ')
  HITS+=("{\"term\": \"$(json_escape "$(printf '%s\n' "$found" | head -n 1)")\", \"count\": $n}")
done < "$TERMS"

EXPL_JSON=""
if [ ${#SEEN_EXPLAINED[@]} -gt 0 ]; then
  while IFS= read -r w; do
    EXPL_JSON+="\"$(json_escape "$w")\", "
  done < <(printf '%s\n' "${SEEN_EXPLAINED[@]}" | sort -u)
  EXPL_JSON=${EXPL_JSON%, }
fi

# Code points, not bytes: jq counts the same under any locale, and an accented
# Portuguese closing would otherwise read longer than it is.
CHARS=$(printf '%s' "$TEXT" | jq -Rs 'length')
FITS=true
[ -n "$MAX_CHARS" ] && [ "$CHARS" -gt "$MAX_CHARS" ] && FITS=false
SIZE_JSON="\"chars\": $CHARS, \"max_chars\": ${MAX_CHARS:-null}"

joined=""
if [ ${#HITS[@]} -gt 0 ]; then
  joined=$(printf '%s, ' "${HITS[@]}"); joined=${joined%, }
fi
if [ ${#HITS[@]} -eq 0 ] && [ "$FITS" = true ]; then
  printf '{"pass": true, "hits": [], "explained": [%s], %s}\n' "$EXPL_JSON" "$SIZE_JSON"
  exit 0
fi
printf '{"pass": false, "hits": [%s], "explained": [%s], %s}\n' "$joined" "$EXPL_JSON" "$SIZE_JSON"
exit 1

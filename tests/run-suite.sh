#!/usr/bin/env bash
# Runs every bats file of a directory, one bats process per file, JOBS files at
# once — the one command that runs every test. Nothing beyond bats and xargs:
# `bats --jobs` needs GNU parallel, which a runner or a contributor may not have.
#
#   tests/run-suite.sh [dir]     default: the directory this script is in
#   JOBS=<n> tests/run-suite.sh  files at once; default: the core count
#
# Prints the failing files' TAP, then one line: "<ok> ok, <not ok> not ok,
# <files> files". Exit 0 when every case passed and every file loaded, 1 when
# anything failed, 2 on bad usage.

set -euo pipefail

DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
case "$JOBS" in '' | *[!0-9]* | 0) echo "run-suite.sh: JOBS takes a positive whole number" >&2; exit 2 ;; esac
[ -d "$DIR" ] || { echo "run-suite.sh: no such directory: $DIR" >&2; exit 2; }
command -v bats >/dev/null || { echo "run-suite.sh: bats is required" >&2; exit 2; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
export OUT

shopt -s nullglob
files=("$DIR"/*.bats)
[ "${#files[@]}" -gt 0 ] || { echo "run-suite.sh: no .bats file in $DIR" >&2; exit 2; }

# A file's exit status is the only verdict that also catches a file bats could
# not load at all — it prints no "not ok" line, only an error.
# shellcheck disable=SC2016  # $1 and $OUT belong to the inner bash
printf '%s\0' "${files[@]}" | xargs -0 -P "$JOBS" -n 1 bash -c \
  'bats --tap "$1" > "$OUT/$(basename "$1").tap" 2>&1 || basename "$1" >> "$OUT/failed"' _

ok=$(cat "$OUT"/*.tap | grep -c '^ok ' || true)
nok=$(cat "$OUT"/*.tap | grep -c '^not ok ' || true)
if [ -s "$OUT/failed" ]; then
  while IFS= read -r f; do
    echo "--- $f"
    cat "$OUT/$f.tap"
  done < <(sort "$OUT/failed")
fi
echo "$ok ok, $nok not ok, ${#files[@]} files"
[ -s "$OUT/failed" ] && exit 1
exit 0

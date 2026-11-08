#!/usr/bin/env bash
# Sourced library: the resolved dependency set a lockfile pins, one
# `name@version` per line, sorted and unique. validate-run.sh --since-last
# compares two of them to tell a lockfile that only moved hashes or formatting
# (same versions: the code that runs is the same) from one that moved a version
# (the code that runs changed).
#
#   lock_versions <basename> < <lockfile content>
#
# Formats read, by basename: package-lock.json and npm-shrinkwrap.json
# (lockfileVersion 2 and 3, the `packages` map), go.sum, Cargo.lock, uv.lock,
# poetry.lock, composer.lock, Gemfile.lock. Return 0 with the set (possibly
# empty), or 3 when the content cannot be read as that format, or the format is
# not one of these (pnpm-lock.yaml, yarn.lock, bun.lock, an npm v1 lock) — the
# caller must then treat the change as a change of code, never as "the same".

# shellcheck shell=bash

lock_versions() {  # <basename> — reads the lockfile on stdin
  local out
  case "$1" in
    package-lock.json | npm-shrinkwrap.json)
      # v1 locks have no `packages` map: unread rather than misread as empty.
      out=$(jq -r 'if (.packages | type) == "object" then
          .packages | to_entries[] | select(.key != "") | "\(.key)@\(.value.version // "")"
        else error("no packages map") end' 2>/dev/null) || return 3 ;;
    go.sum)
      # module version[/go.mod] h1:hash — every line has the three fields.
      out=$(awk 'NF == 0 { next } NF != 3 || $3 !~ /^h1:/ { bad = 1; exit }
        { v = $2; sub(/\/go\.mod$/, "", v); print $1 "@" v } END { exit bad }') || return 3 ;;
    Cargo.lock | uv.lock | poetry.lock)
      # [[package]] blocks; name and version are the block's own keys, quoted.
      out=$(awk '
        function emit() { if (n != "") print n "@" v; n = ""; v = "" }
        /^\[\[package\]\]/ { emit(); on = 1; next }
        /^\[/ { emit(); on = 0; next }
        on && /^name = "/ { n = $0; sub(/^name = "/, "", n); sub(/".*/, "", n) }
        on && /^version = "/ { v = $0; sub(/^version = "/, "", v); sub(/".*/, "", v) }
        END { emit() }') || return 3 ;;
    composer.lock)
      out=$(jq -r '((.packages // []) + (."packages-dev" // []))[] | "\(.name)@\(.version)"' 2>/dev/null) || return 3 ;;
    Gemfile.lock)
      # A resolved spec sits at four spaces under `specs:`; six spaces are its
      # own requirements, which are ranges, not resolutions.
      out=$(awk '/^    [^ ][^ ]* \([^)]*\)$/ { n = $1; v = $2; gsub(/[()]/, "", v); print n "@" v }') || return 3 ;;
    *) return 3 ;;
  esac
  [ -n "$out" ] && printf '%s\n' "$out" | LC_ALL=C sort -u
  return 0
}

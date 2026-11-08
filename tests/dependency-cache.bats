#!/usr/bin/env bats
# Dependencies and tool data come from the machine's caches, not from Docker
# Hub, GitHub or a registry on every run (owner's point, 2026-11-08). The
# pillars' order bounds it: a cache never skips a security update and never
# turns an integrity check off. references/dependency-cache.md holds the rule;
# the run and the Executor read it before a sub-task that installs, builds an
# image, runs a gate tool or sets up E2E; the catalog's commands use it.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
REF="$ROOT/references/dependency-cache.md"

@test "the reference covers every stage that downloads" {
  [ -f "$REF" ] || { echo "no references/dependency-cache.md" >&2; return 1; }
  local want
  for want in 'npm ci --prefer-offline' 'uv sync --frozen' 'go mod download' 'cargo fetch' 'composer install' 'bundle install --prefer-local' \
    'trivy' 'opengrep' '--action-offline-mode' 'type=cache' '@sha256:' 'ms-playwright' 'actions/cache'; do
    grep -qF -- "$want" "$REF" || { echo "dependency-cache.md: nothing on $want" >&2; return 1; }
  done
}

@test "a forced re-download is named and allowed only when it is the sub-task's purpose" {
  local flag
  for flag in '--no-cache' '--pull' 'go clean -modcache' 'npm cache clean' '--no-cache-dir'; do
    grep -qF -- "$flag" "$REF" || { echo "dependency-cache.md: $flag not named" >&2; return 1; }
  done
  grep -qF "unless re-downloading is the sub-task's purpose" "$REF" || { echo "dependency-cache.md: no purpose exception" >&2; return 1; }
}

@test "a cache never skips a security update or an integrity check" {
  grep -qiF 'a cache never skips a security update' "$REF" || { echo "dependency-cache.md: no security bound" >&2; return 1; }
  grep -qF -- '--skip-db-update' "$REF" || { echo "dependency-cache.md: trivy's skip flag not forbidden" >&2; return 1; }
  grep -qF 'older than seven days' "$REF" || { echo "dependency-cache.md: no refresh bound on a cached ruleset" >&2; return 1; }
  grep -qF 'GONOSUMDB' "$REF" || { echo "dependency-cache.md: checksum bypasses not forbidden" >&2; return 1; }
}

@test "the run and the Executor read it before a sub-task that downloads" {
  local f
  for f in "$ROOT/references/run-mode.md" "$ROOT/agents/executor.md"; do
    grep -qF 'dependency-cache.md' "$f" || { echo "${f#"$ROOT"/}: does not point to dependency-cache.md" >&2; return 1; }
  done
}

@test "the catalog's commands use the caches" {
  local q="$ROOT/references/quality-catalog.md"
  grep -qF 'act --pull=false --action-offline-mode -j <job>' "$q" || { echo "quality-catalog.md: the CI mirror pulls every run" >&2; return 1; }
  grep -qF 'a ruleset file cached by [dependency-cache.md]' "$q" || { echo "quality-catalog.md: SAST fetches the registry every scan" >&2; return 1; }
}

# shellcheck shell=bash
# Shared fixtures of the contract tests for scripts/archive-story.sh, sourced by
# every tests/archive-story*.bats file. The suite is split by subject so the
# files run in parallel; one file held 108 cases and 44 s of the suite's wall
# clock on 2026-11-08.
#
# Contract tests for scripts/archive-story.sh.
#
# Contract under test:
#   archive-story.sh <NNN|story-dir> [--allow-heavy] [--skip-secrets]
#                    [--keep-logs] [--keep-copies] [--force <reason>]
#   JSON on stdout: {story, status: archived|blocked|refused, moved,
#                    pruned{logs_kb, copies_removed}, guard{violations[]},
#                    secrets{}, manifest_entry{}}
#   Exit 0 only on a completed move; 1 = guard hit / refusal; 2 = invalid input.
#   Step order: guards -> prune -> manifest append -> move -> status -> index.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ARCHIVE_SH="$PLUGIN_ROOT/scripts/archive-story.sh"
  WORK=$(mktemp -d)
  PROJ="$WORK/proj"
  MANIFEST="$PROJ/.epico/archive/manifest.yaml"
  mkdir -p "$PROJ/.epico/stories"
  cd "$PROJ"
}

teardown() {
  cd /
  chmod -R u+rwX "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}

# make_story <dir-name> <complete|incomplete>
# complete:   3 tasks - 2 [x], 1 [~]  (total 3, closed 2, deferred 1, open 0)
# incomplete: 3 tasks - 1 [x], 2 [ ]  (total 3, closed 1, deferred 0, open 2)
make_story() {
  local dir="$PROJ/.epico/stories/$1" mode="${2:-complete}" status=validated
  [ "$mode" = incomplete ] && status=in-progress
  mkdir -p "$dir"
  cat > "$dir/story.md" <<EOF
---
story: ${1#*-}
type: feature
scale: standard
version: 1
created: 2026-08-01
status: $status
---

# Story - fixture
EOF
  if [ "$mode" = complete ]; then
    cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-01
---

## Task List
- [x] 1 - First done thing
  - Validation: ok
- [x] 2 - Second done thing
  - Validation: ok
- [~] 3 - Deferred external thing
  - Validation: ok
EOF
  else
    cat > "$dir/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-01
---

## Task List
- [x] 1 - First done thing
  - Validation: ok
- [ ] 2 - Still open thing
  - Validation: ok
- [ ] 3 - Also open thing
  - Validation: ok
EOF
  fi
}

# make_spike <dir-name> <verdict-status> [promoted-to] [probe-box]
# scale: spike - tasks-only, no story.md, no requirements chain, and a
# mandatory `## Verdict` section that IS the spike's conclusion.
# The probe box state is a parameter so each case isolates the verdict rule:
# refusals use a CLOSED box (only the verdict can refuse) and passes use an
# OPEN one (only the verdict can complete). Frontmatter status stays
# `in-progress` so the status branch never decides either.
make_spike() {
  local dir="$PROJ/.epico/stories/$1" vstatus="$2" promoted="${3:-}" probe="${4:-x}"
  mkdir -p "$dir"
  {
    echo '---'
    echo 'version: 1'
    echo 'created: 2026-08-01'
    echo 'scale: spike'
    echo 'status: in-progress'
    echo '---'
    echo
    echo '## Probe'
    echo "- [$probe] 1 - Run the probe"
    echo
    echo '## Verdict'
    echo "- status: $vstatus"
    echo '- conclusion: what the probe showed'
    if [ -n "$promoted" ]; then echo "- promoted-to: $promoted"; fi
  } > "$dir/tasks.md"
  return 0
}


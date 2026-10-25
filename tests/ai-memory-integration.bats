#!/usr/bin/env bats
# ai-memory as an optional, detected dependency — the doc contract.
#
# The surface is agent-executed prose, so every case pins a BLOCK found by a
# structural anchor (a heading, a numbered step) and asserts a keyword inside
# it, case-insensitively. No case requires a sentence verbatim: a correct
# rewrite of the prose must stay green.
#
#   M1  mcp-integration.md has a Memory MCP section that names the health
#       check, Fast (memory is the one check Fast does not skip) and the opt-out
#   M2  the same section carries the three hard rules: memory is never
#       evidence, memory_feedback is never called, ignore_paths is recommended
#   M3  SKILL.md triage has a memory step that names Fast, and the proposal
#       block has a Memory line
#   M4  context-discovery.md has a Prior Knowledge section naming both reads
#       and scoped to all scales
#   M5  run-mode.md recalls at the procedure and writes the deviations page at
#       End of Run, at a stable path
#   M6  validate-mode.md hands prior findings to the Auditor as things to
#       verify, and writes audit pages at a stable path
#   M7  plugin.json exposes aiMemory, default auto
#   M8  init-mode.md recommends ignore_paths
#   M9  no agent definition names a memory tool — the orchestrator is the only
#       writer, and the agents' own memory directories are left alone
#
# Note on awk patterns: passed as strings, so no backslash escapes; literal
# punctuation goes in a bracket class.

ROOT="$BATS_TEST_DIRNAME/.."

# section <file> <start-regex> <end-regex> — the block from the first line
# matching start up to (not including) the next line matching end.
section() {
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

has() { # has <label> <block> <keyword>
  if ! printf '%s' "$2" | grep -qi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

@test "M1: mcp-integration.md has a Memory MCP section naming the health check, Fast and the opt-out" {
  block=$(section "$ROOT/references/mcp-integration.md" '^## Memory MCP' '^## ')
  [ -n "$block" ]
  has "M1" "$block" "memory_status"
  has "M1" "$block" "fast"
  has "M1" "$block" "aiMemory"
}

@test "M2: the Memory MCP section carries the three hard rules" {
  block=$(section "$ROOT/references/mcp-integration.md" '^### Hard rules' '^## ')
  # the doc has two 'Hard rules' headings (research, memory); take the memory one
  block=$(section "$ROOT/references/mcp-integration.md" '^## Memory MCP' '^## Rules')
  has "M2 never evidence" "$block" "never evidence"
  has "M2 no feedback" "$block" "memory_feedback"
  has "M2 ignore_paths" "$block" "ignore_paths"
}

@test "M3: SKILL.md triage has a memory step that names Fast, and the proposal has a Memory line" {
  step=$(grep -E '^7a[.] ' "$ROOT/references/triage.md")
  [ -n "$step" ]
  has "M3 step" "$step" "memory"
  has "M3 step" "$step" "fast"
  grep -q '^> - \*\*Memory:\*\*' "$ROOT/references/triage.md"
}

@test "M4: context-discovery.md has a Prior Knowledge section naming both reads, in all scales" {
  block=$(section "$ROOT/references/context-discovery.md" '^## Prior Knowledge' '^## ')
  [ -n "$block" ]
  has "M4" "$block" "memory_recent"
  has "M4" "$block" "memory_query"
  has "M4" "$block" "all scales"
}

@test "M5: run-mode.md recalls in the procedure and writes the deviations page at End of Run" {
  proc=$(section "$ROOT/references/run-mode.md" '^## Procedure' '^## ')
  has "M5 recall" "$proc" "memory_query"
  end=$(section "$ROOT/references/run-mode.md" '^### End of Run' '^## ')
  has "M5 page" "$end" "epico/deviation/"
}

@test "M6: validate-mode.md hands prior findings to the Auditor to verify, and writes audit pages" {
  aud=$(section "$ROOT/references/validate-mode.md" '^## Audit — Part 2' '^## ')
  has "M6 prior" "$aud" "memory"
  has "M6 verify" "$aud" "verify"
  proc=$(section "$ROOT/references/validate-mode.md" '^## Validate Mode Procedure' '^## ')
  has "M6 page" "$proc" "epico/finding/"
}

@test "M7: plugin.json exposes aiMemory with default auto" {
  run jq -r '.userConfig.aiMemory.default' "$ROOT/.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
}

@test "M8: init-mode.md recommends ignore_paths when memory is detected" {
  proc=$(section "$ROOT/references/init-mode.md" '^## Procedure' '^## ')
  has "M8" "$proc" "ignore_paths"
}

@test "M9: no agent definition names a memory tool — the orchestrator is the only writer" {
  if grep -l 'ai-memory\|memory_query\|memory_write_page' "$ROOT"/agents/*.md; then
    echo 'an agent definition names a memory tool; the orchestrator must stay the only writer' >&2
    return 1
  fi
}

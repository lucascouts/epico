#!/usr/bin/env bats
# The Tech Reviewer's edge-case questions: seven questions it answers for the
# code under review, one line each in its report file, never a quota of
# findings — a review that finds nothing is a valid PASS.
#
# The surface is agent-executed prose, so every case scopes its grep to the
# block that carries the rule: a whole-file grep would pass on a mention in
# the wrong place. No case requires a whole sentence verbatim.
#
# The backticks inside single-quoted patterns are Markdown code spans the
# prose writes literally, never a command substitution.
# shellcheck disable=SC2016

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REVIEWER="$ROOT/agents/tech-reviewer.md"
  TECH_REVIEW_REF="$ROOT/references/run-tech-review.md"
}

# Lines of one markdown section, heading included: from the first line
# matching <start> to the next line matching <end> (exclusive).
ecq_section() { # ecq_section <file> <start regex> <end regex>
  awk -v s="$2" -v e="$3" '!f && $0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

# Case-insensitive extended-regex match inside a captured block.
ecq_has() { # ecq_has <label> <block> <extended regex>
  if ! printf '%s\n' "$2" | command grep -Eqi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

# Fixed-string match inside a captured block — for the literal answer forms.
ecq_has_fixed() { # ecq_has_fixed <label> <block> <literal>
  if ! printf '%s\n' "$2" | command grep -Fq -- "$3"; then
    echo "$1: expected the block to contain '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

questions() {
  ecq_section "$REVIEWER" '^## Edge-case questions' '^## '
}

@test "E1: the edge-case questions section follows Focus Areas" {
  # The next level-2 heading after Focus Areas is the questions section.
  next=$(awk '/^## Focus Areas/{f=1; next} f && /^## /{print; exit}' "$REVIEWER")
  [ "$next" = "## Edge-case questions" ]
}

@test "E2: the section names the seven topics" {
  sec=$(questions)
  [ -n "$sec" ]
  ecq_has "E2 boundaries" "$sec" 'boundar'
  ecq_has "E2 off-by-one" "$sec" 'off-by-one'
  ecq_has "E2 empty" "$sec" 'empty'
  ecq_has "E2 huge" "$sec" 'huge'
  ecq_has "E2 concurrency" "$sec" 'concurren'
  ecq_has "E2 time zones" "$sec" 'time zones?'
  ecq_has "E2 partial failure" "$sec" 'partial failure'
  ecq_has "E2 permissions" "$sec" 'permission'
  ecq_has "E2 retries" "$sec" 'retr(y|ies)'
}

@test "E3: each of the seven is a question about the code under review" {
  sec=$(questions)
  # Seven numbered items, every one ending in a question mark.
  items=$(printf '%s\n' "$sec" | command grep -cE '^[0-9]+\. ' || true)
  asked=$(printf '%s\n' "$sec" | command grep -cE '^[0-9]+\. .*\?$' || true)
  [ "$items" -eq 7 ]
  [ "$asked" -eq 7 ]
  ecq_has "E3 under review" "$sec" 'code under review'
}

@test "E4: a question that does not apply is answered n/a" {
  sec=$(questions)
  ecq_has "E4 n/a" "$sec" 'does not apply to this code is answered `n/a`'
}

@test "E5: the questions are never a minimum number of findings" {
  sec=$(questions)
  ecq_has "E5 no quota" "$sec" 'never a minimum number of findings'
  # A quota written back in anywhere in the agent reverses the rule.
  run command grep -ciE 'at least (one|a|[0-9]+) (finding|issue)' "$REVIEWER"
  [ "$output" -eq 0 ]
}

@test "E6: zero findings is a valid PASS, beside the PASS verdict" {
  pass=$(command grep -E '^ *- \*\*PASS\*\*' "$REVIEWER")
  [ -n "$pass" ]
  ecq_has "E6 zero findings" "$pass" 'zero findings is a valid `PASS`'
  ecq_has "E6 no quota" "$pass" 'no minimum number of findings'
  run command grep -ciE 'zero findings is (not|never|no longer)' "$REVIEWER"
  [ "$output" -eq 0 ]
}

@test "E7: the report file answers each question in one line, in one of three forms" {
  step4=$(ecq_section "$REVIEWER" '^## Protocol' '^## ' | command grep -E '^4\. ')
  [ -n "$step4" ]
  ecq_has "E7 each" "$step4" 'answers each edge-case question in one line'
  ecq_has_fixed "E7 n/a" "$step4" '`n/a`'
  ecq_has_fixed "E7 ok" "$step4" '`checked — ok`'
  ecq_has_fixed "E7 issue" "$step4" '`issue — <file:line>`'
}

@test "E8: after a PASS the orchestrator never asks a Tech Reviewer for more findings" {
  handling=$(ecq_section "$TECH_REVIEW_REF" '^### Orchestrator Handling of Tech Review' '^##')
  [ -n "$handling" ]
  # The rule sits on the PASS bullet, not elsewhere in the section.
  pass=$(printf '%s\n' "$handling" | command grep -E '^- If all Tech Reviewers report PASS' || true)
  [ -n "$pass" ]
  ecq_has "E8 no second ask" "$pass" 'never ask a Tech Reviewer for more findings after a `?PASS`?'
}

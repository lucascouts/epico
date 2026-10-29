#!/usr/bin/env bats
# The engineering level — the doc contract. How long the thing must last
# decides how much the story pays for: the catalog tier, and whether Phase 3
# authors the tests or the run does.
#
# The surface is agent-executed prose, so every case pins a BLOCK found by a
# structural anchor and asserts a keyword inside it, case-insensitively. No
# case requires a sentence verbatim: a correct rewrite must stay green. The
# validator's own behaviour (enum, per-level ceiling) is pinned in
# tests/authoring-ceiling.bats, not here.
#
#   E1  references/engineering-level.md is the single home: four levels with
#       their fishing questions and multiples, the 5× rule, how the level is
#       read (tool when unsettled, the price line, the orientation round),
#       where it is recorded, what each level pays for, what it never changes
#   E2  SKILL.md triage reads the level from the request, takes tool when
#       unsettled, and the proposal carries an Engineering line
#   E3  the Personas table gates the Test Advisor on project/product
#   E4  Phase Execution's ceiling paragraph makes the three offers
#   E5  the meta.yaml example and the frontmatter block carry engineering:
#   E6  tasks.md's Authoring Ceiling bounds bytes and the unit, never the
#       count; the Tests Field is authored only at project/product
#   E7  phase-gates.md spawns the Test Advisor only at project/product and
#       widens the Lite checklist to experiment/tool
#   E8  run-mode.md: materialization and its converse guard exempt the two
#       levels, the run-time ordering names them, the execution plan and the
#       Run Mode Rules carry the recorded line
#   E9  refine, validate-mode, auditor, test-advisor and batch-create read
#       Phase 3 through the level
#   E10 the catalog names the runtime, the justified dependencies, the atomic
#       write with its signal, the syntax-check-is-not-lint rule, and the level
#       bound
#   E11 README names the axis and the four levels
#   E12 requirements.md, plain-register.md and self-review-checklist.md know
#       the level
#
# Note on awk patterns: passed as strings, so no backslash escapes; literal
# punctuation goes in a bracket class.

ROOT="$BATS_TEST_DIRNAME/.."

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

hasF() { # hasF <label> <block> <fixed string>
  if ! printf '%s' "$2" | grep -qF -- "$3"; then
    echo "$1: expected the block to contain '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

@test "E1: engineering-level.md is the single home — four levels, questions, multiples, 5×, how read, where recorded, what each pays for" {
  f="$ROOT/references/engineering-level.md"
  [ -f "$f" ]
  levels=$(section "$f" '^## The four levels' '^## ')
  [ -n "$levels" ]
  # The words below are the distinguishing half of each level's question, not
  # decoration.
  for w in '`experiment`' '`tool`' '`project`' '`product`' "try it out" "breaks" "besides you" "product or a service"; do
    has "E1 level" "$levels" "$w"
  done
  for m in "1×" "2–3×" "4–6×" "8×+"; do hasF "E1 multiple" "$levels" "$m"; done
  hasF "E1 5× rule" "$levels" "5×"
  read_=$(section "$f" '^## How the level is read' '^## ')
  has "E1 asked when unsettled" "$read_" "does not settle it"
  has "E1 tool fallback" "$read_" "only when nobody can answer"
  has "E1 price line" "$read_" "one line"
  has "E1 orientation" "$read_" "orientation"
  has "E1 never a choice of level" "$read_" "which level is this"
  rec=$(section "$f" '^## Where it is recorded' '^## ')
  has "E1 frontmatter" "$rec" "engineering:"
  has "E1 meta" "$rec" "meta.yaml"
  has "E1 recorded line" "$rec" "recorded line"
  has "E1 boxes" "$rec" "boxes"
  pays=$(section "$f" '^## What each level pays for' '^## ')
  has "E1 advisor" "$pays" "Test Advisor"
  has "E1 run time" "$pays" "run time"
  has "E1 catalog" "$pays" "quality-catalog"
  # The level carries no plan ceiling; the row's absence is pinned, since a
  # table row is exactly what grows back by accident.
  if echo "$pays" | grep -q 'Plan ceiling'; then
    echo "E1: the per-level plan ceiling row is back in What each level pays for" >&2
    return 1
  fi
  never=$(section "$f" '^## What the level never changes' '^## ')
  [ -n "$never" ]
  has "E1 never the scale" "$never" "scale"
}

@test "E2: triage reads the engineering level from the request, asks when unsettled (tool only when nobody can answer), and the proposal carries an Engineering line" {
  block=$(section "$ROOT/references/triage.md" '^## Triage Protocol' '^### Mode Recommendation')
  [ -n "$block" ]
  has "E2 level" "$block" "engineering level"
  has "E2 reference" "$block" "engineering-level"
  for l in experiment tool project product; do has "E2 $l" "$block" "\`$l\`"; done
  has "E2 default" "$block" "ask when the request does not settle it"
  has "E2 fallback" "$block" "only when nobody can answer"
  has "E2 price" "$block" "multiple"
  has "E2 never the scale" "$block" "never changes the scale and never changes the requester level"
  grep -q '^> - \*\*Engineering:\*\*' "$ROOT/references/triage.md"
  grep -q '^3a\. \*\*Read the engineering level\*\*' "$ROOT/references/triage.md"
}

@test "E3: the Personas table gates the Test Advisor on project or product, and names the run-time alternative" {
  block=$(section "$ROOT/references/personas.md" '^## Personas' '^## Command Routing')
  row=$(printf '%s' "$block" | grep -E '^\| \*\*Test Advisor\*\*')
  [ -n "$row" ]
  has "E3 project" "$row" "project"
  has "E3 product" "$row" "product"
  has "E3 run time" "$row" "run time"
  has "E3 reference" "$row" "engineering-level"
}

@test "E4: the Phase 3 ceiling paragraph is about size, offers cut and split, and caps no count" {
  block=$(section "$ROOT/references/phase-execution.md" '^## Phase Execution' '^## Persistence')
  [ -n "$block" ]
  has "E4 cut" "$block" "cut"
  has "E4 split" "$block" "split"
  has "E4 warning" "$block" "never a block"
  has "E4 no count" "$block" "no ceiling on the number of tasks"
  has "E4 unit" "$block" "Validation"
}

@test "E5: the meta.yaml example and the frontmatter block carry engineering:" {
  draft=$(section "$ROOT/references/phase-execution.md" '^### Draft Saving' '^### Resume')
  [ -n "$draft" ]
  has "E5 meta" "$draft" "engineering:"
  out=$(cat "$ROOT/references/output-rules.md")
  [ -n "$out" ]
  hasF "E5 frontmatter" "$out" "engineering: experiment | tool | project | product"
  am=$(section "$ROOT/references/triage.md" '^## Adaptive Modes' '^## Workflow Variants')
  has "E5 two axes" "$am" "engineering level"
}

@test "E6: tasks.md's Authoring Ceiling is bytes only and bounds the unit, not the count; the Tests Field is authored only at project/product" {
  f="$ROOT/references/tasks.md"
  ceil=$(section "$f" '^### Authoring Ceiling' '^### ')
  [ -n "$ceil" ]
  has "E6 bytes" "$ceil" "32 KB"
  has "E6 no count" "$ceil" "no ceiling on the number of tasks"
  has "E6 unit" "$ceil" "one Executor pass"
  has "E6 validation" "$ceil" "Validation"
  has "E6 cut" "$ceil" "cut"
  has "E6 split" "$ceil" "split"
  has "E6 warning" "$ceil" "never a block"
  if echo "$ceil" | grep -qE 'box ceiling of its engineering level'; then
    echo "E6: the per-level box ceiling is back" >&2
    return 1
  fi
  tf=$(section "$f" '^### Tests Field' '^### ')
  has "E6 project" "$tf" "project"
  has "E6 product" "$tf" "product"
  has "E6 run time" "$tf" "run time"
  has "E6 reference" "$tf" "engineering-level"
}

@test "E7: phase-gates.md spawns the Test Advisor only at project/product and widens the Lite checklist" {
  f="$ROOT/references/phase-gates.md"
  ta=$(section "$f" '^## Test Advisor Sub-agent' '^### ')
  [ -n "$ta" ]
  has "E7 project" "$ta" "project"
  has "E7 product" "$ta" "product"
  has "E7 reference" "$ta" "engineering-level"
  has "E7 foreground kept" "$ta" "run_in_background: false"
  lite=$(section "$f" '^### Test Advisor Lite' '^## ')
  [ -n "$lite" ]
  has "E7 lite experiment" "$lite" "experiment"
  has "E7 lite tool" "$lite" "tool"
  refs=$(section "$f" '^## Reference Files Loaded Per Phase' '^## ')
  has "E7 loaded" "$refs" "engineering-level.md"
}

@test "E8: run-mode.md exempts the two levels from materialization and its guard, names them in the run-time ordering, and carries the recorded line" {
  f="$ROOT/references/run-mode.md"
  step7=$(awk '!inb && $0 ~ /^[0-9]+[.] .*Materialize pre-authored tests/ {inb=1; print; next} inb && $0 ~ /checks the converse/ {exit} inb {print}' "$f")
  [ -n "$step7" ]
  has "E8 step 7 experiment" "$step7" "experiment"
  has "E8 step 7 tool" "$step7" "tool"
  has "E8 step 7 reference" "$step7" "engineering-level"
  if grep -q 'Materialize pre-authored tests (Standard/Full only)' "$f"; then
    echo "E8: step 7 still reads Standard/Full only" >&2
    return 1
  fi
  guard=$(awk '!inb && $0 ~ /checks the converse/ {inb=1; print; next} inb && $0 ~ /^[0-9]+[.] / {exit} inb {print}' "$f")
  [ -n "$guard" ]
  has "E8 guard experiment" "$guard" "experiment"
  ord=$(section "$f" '^### Run-time test-first ordering' '^### Inline Route')
  [ -n "$ord" ]
  has "E8 ordering experiment" "$ord" "experiment"
  has "E8 ordering tool" "$ord" "tool"
  has "E8 ordering spike kept" "$ord" "spike"
  has "E8 ordering reference" "$ord" "engineering-level"
  plan=$(grep -E '^8\. \*\*Present execution plan' "$f")
  [ -n "$plan" ]
  has "E8 recorded line at plan" "$plan" "recorded line"
  rules=$(section "$f" '^## Run Mode Rules' '^### ')
  has "E8 recorded line at end" "$rules" "recorded line"
  has "E8 multiple" "$rules" "multiple"
  has "E8 boxes" "$rules" "boxes"
}

@test "E9: refine, validate-mode, auditor, test-advisor and batch-create read Phase 3 through the level" {
  refine=$(section "$ROOT/references/refine-mode.md" '^## Red Evidence for Added Sub-tasks' '^## ')
  [ -n "$refine" ]
  has "E9 refine project" "$refine" "project"
  has "E9 refine product" "$refine" "product"
  has "E9 refine run time" "$refine" "run time"
  v10=$(grep -E '^> 10\. Red precedence' "$ROOT/references/validate-mode.md")
  [ -n "$v10" ]
  has "E9 validate level" "$v10" "engineering level"
  a10=$(grep -E '^10\. \*\*Red precedence' "$ROOT/agents/auditor.md")
  [ -n "$a10" ]
  has "E9 auditor level" "$a10" "engineering level"
  role=$(section "$ROOT/agents/test-advisor.md" '^## Your Role' '^## ')
  has "E9 advisor project" "$role" "project"
  has "E9 advisor product" "$role" "product"
  has "E9 advisor reference" "$role" "engineering-level"
  batch=$(grep -E 'Phase 3 runs the Test Advisor' "$ROOT/references/batch-create.md")
  [ -n "$batch" ]
  has "E9 batch product" "$batch" "product"
}

@test "E10: the catalog names the runtime, justified dependencies, the atomic write with its signal, the syntax-check rule and the level bound" {
  f="$ROOT/references/quality-catalog.md"
  always=$(section "$f" '^## Always' '^## ')
  has "E10 runtime" "$always" "Supported and declared runtime"
  has "E10 deps" "$always" "Dependencies justified"
  has "E10 syntax" "$always" "syntax check"
  has "E10 omitted" "$always" "omitted"
  has "E10 node check" "$always" "node --check"
  context=$(section "$f" '^## By context' '^## ')
  has "E10 atomic" "$context" "Atomic write"
  has "E10 signal" "$context" "reads back"
  chosen=$(section "$f" '^## How the set is chosen' '^## ')
  has "E10 bound" "$chosen" "engineering level"
  has "E10 never installs kept" "$chosen" "never installs"
}

@test "E11: README names the axis and the four levels" {
  f="$ROOT/README.md"
  has "E11 axis" "$(cat "$f")" "engineering level"
  for l in experiment tool project product; do has "E11 $l" "$(cat "$f")" "\`$l\`"; done
  grep -q 'references/engineering-level.md' "$f"
}

@test "E12: requirements.md, plain-register.md and self-review-checklist.md know the level" {
  hasF "E12 template" "$(cat "$ROOT/references/requirements.md")" "engineering: experiment | tool | project | product"
  guide=$(section "$ROOT/references/requirements.md" '^## Writing Guidelines' '^## ')
  has "E12 guideline" "$guide" "engineering-level"
  words=$(section "$ROOT/references/plain-register.md" '^## Words that stay' '^## ')
  has "E12 plain level" "$words" "engineering level"
  has "E12 plain rendering" "$words" "how long"
  has "E12 self-review" "$(cat "$ROOT/references/self-review-checklist.md")" "Sized by the unit"
}

# --- Security floor and the `instant` shortcut ------------------------------
#
# The floor exists because a level decides how much ENGINEERING a story buys,
# never how much SAFETY. With nothing checking the runtime, a run accepts
# whatever version it finds, even one out of support, and declares none.

@test "E13: the security floor is named once, in quality-catalog.md, with its three items" {
  f="$ROOT/references/quality-catalog.md"
  floor=$(section "$f" '^### The security floor' '^## ')
  [ -n "$floor" ]
  has "E13 runtime" "$floor" "runtime"
  has "E13 secrets"  "$floor" "gitleaks"
  has "E13 sca"      "$floor" "osv-scanner"
  # The runtime item: LTS by preference, the current
  # widely-used stable when the LTS is the one carrying the vulnerability.
  has "E13 lts"      "$floor" "LTS"
  has "E13 clean"    "$floor" "vulnerab"
}

@test "E13b: the floor survives every level — experiment activates it, not nothing" {
  f="$ROOT/references/quality-catalog.md"
  bound=$(grep -n 'The engineering level bounds the set' "$f" | cut -d: -f1)
  [ -n "$bound" ]
  line=$(sed -n "${bound}p" "$f")
  has "E13b experiment floor" "$line" "security floor"
  if printf '%s' "$line" | grep -qF 'activates nothing'; then
    echo "E13b: the level bound says experiment activates nothing" >&2
    return 1
  fi
}

@test "E13c: the level table sends experiment to the floor, not to an empty legend" {
  levels=$(section "$ROOT/references/engineering-level.md" '^## What each level pays for' '^## ')
  has "E13c floor" "$levels" "security floor"
}

@test "E14: instant sets experiment and enters the lean route, never a fourth scale" {
  sec=$(cat "$ROOT/references/instant-mode.md")
  [ -n "$sec" ]
  hasF "E14 level pin"  "$sec" '`experiment`'
  hasF "E14 lean route" "$sec" 'lean-route.md'
  has  "E14 no question" "$sec" "no technical question round"
  # The whole point: it is an entrance, not a state. No artifact may carry it.
  has  "E14 not a state" "$sec" "entrance"
}

@test "E14a: triage hands an experiment to the lean route, which keeps the floor and writes no story" {
  hasF "E14a handoff" "$(cat "$ROOT/references/triage.md")" 'WHEN it reads `experiment`, stop here and follow [lean-route.md](lean-route.md)'
  lean=$(cat "$ROOT/references/lean-route.md")
  has  "E14a no story" "$lean" "No story"
  has  "E14a floor"    "$lean" "security floor"
  has  "E14a check"    "$lean" "whole check"
  # A run of an existing story never drops to the lean route, whatever its level.
  has  "E14a not inside" "$lean" "Never inside an existing story"
  grep -q '| \*\*Lean\*\* |' "$ROOT/skills/epico/SKILL.md"
}

@test "E14b: instant is routed — grammar arm and dispatch row both exist" {
  f="$ROOT/skills/epico/SKILL.md"
  grep -qE '^"instant <description>"' "$f"
  grep -q '| \*\*Instant\*\* |' "$f"
}

# --- Proposal, floor, instant, report and commit rules -----------------------
#
# Each case below pins one rule.

@test "E15: the scale is proposed beside the level — the requester sees the bigger price" {
  read_=$(section "$ROOT/references/engineering-level.md" '^## How the level is read' '^## ')
  has "E15 scale in proposal" "$read_" "scale"
}

@test "E15b: rising above the fast floor owes a written reason" {
  has "E15b field" "$(cat "$ROOT/references/tasks.md")" "scale_reason"
  why=$(section "$ROOT/references/tasks.md" '^## Why the Scale Rose' '^## ')
  [ -n "$why" ]
  has "E15b floor" "$why" "floor"
  has "E15b warns" "$why" "warns"
}

@test "E15c: the scale_reason check fails OPEN on absence — the legacy contract holds" {
  # The rule every new field in this validator follows. A story written before
  # the field must validate exactly as it did; only a field STARTED and left
  # empty is an unfinished story.
  v="$ROOT/scripts/validate-story.sh"
  grep -q 'scale_reason' "$v"
  has "E15c fail-open" "$(cat "$v")" "ABSENCE IS SILENT"
}

@test "E16: a level question carries no recommended option, in any register" {
  read_=$(section "$ROOT/references/engineering-level.md" '^## How the level is read' '^## ')
  has "E16 rule" "$read_" "ever marked recommended"
  has "E16 both registers" "$read_" "any register"
  # Every register uses the same unmarked form, changing only vocabulary.
  has "E16 direction" "$read_" "Every register asks it as its own question"
}

@test "E17: no dependencies is a verdict, not a failure" {
  floor=$(section "$ROOT/references/quality-catalog.md" '^### The security floor' '^## ')
  has "E17 verdict" "$floor" "verdict, not a failure"
  # osv-scanner exits 128 on a zero-dependency project: an error where the
  # honest answer is "nothing to report".
  has "E17 exit code" "$floor" "128"
  has "E17 never failed" "$floor" "never failed for having nothing to scan"
}

@test "E18: the README is in the floor — a program nobody can run is not usable as it is" {
  floor=$(section "$ROOT/references/quality-catalog.md" '^### The security floor' '^## ')
  has "E18 readme" "$floor" "README"
  has "E18 count" "$floor" "five items no level drops"
}

@test "E19: the lean route's closing names every protection it dropped alone" {
  sec=$(cat "$ROOT/references/lean-route.md")
  has "E19 report" "$sec" "reduces protection or documentation"
  has "E19 read, not bitten" "$sec" "never by being bitten"
}

@test "E20: the report never states the multiple the run achieved" {
  rec=$(section "$ROOT/references/engineering-level.md" '^## Where it is recorded' '^## ')
  has "E20 rule" "$rec" "never states the multiple"
}

@test "E21: the commit stages by name — never a blanket add" {
  commit=$(section "$ROOT/references/run-mode.md" '^### The Commit Field' '^### ')
  [ -n "$commit" ]
  has "E21 rule" "$commit" "Stage by name"
  has "E21 blanket" "$commit" "git add -A"
  # The hook is a convenience, not a guarantee: it does not run under -p.
  has "E21 why" "$commit" "hook"
}

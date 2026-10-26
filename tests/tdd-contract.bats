#!/usr/bin/env bats
# Tests under TDD — the doc contract of the Red, setup-repair, test-diff,
# scratch, unit-ownership, regression and breaker rules.
#
# The surface is agent-executed prose, so every case asserts keywords in the
# file that carries the rule, case-insensitively. No case requires a sentence
# verbatim: a correct rewrite must stay green.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

has() {  # <file> <extended regex> — case-insensitive, names the miss
  if ! command grep -Eqi -- "$2" "$ROOT/$1"; then
    echo "$1 does not carry: $2"
    return 1
  fi
}

@test "T1: Red is a failed assertion against a stub; setup failures are not Red" {
  has agents/test-advisor.md 'stub the api under test'
  has agents/test-advisor.md 'red is a failed assertion'
  has agents/test-advisor.md 'red_at: assertion'
  has agents/test-advisor.md 'red_at.*setup'
  has agents/auditor.md 'red_at: setup'
  has references/run-mode.md 'against a stub'
  has references/run-mode.md 'red_at: assertion'
}

@test "T2: setup repair touches fixtures, helpers, imports and paths, never an assertion, and re-runs Red" {
  has agents/executor.md 'setup-repair exception'
  has agents/executor.md 'fixtures, helpers, imports, file paths'
  has agents/executor.md 'never an assertion line'
  has agents/executor.md 're-run the repaired test'
  has references/run-mode.md 'setup repair the frozen-test rule allows'
}

@test "T3: epico-test-diff is enforced by close-subtask, run by the Auditor, released by refine" {
  has scripts/close-subtask.sh 'test-diff.sh'
  has agents/auditor.md 'epico-test-diff'
  has references/run-mode.md 'a box whose test was rewritten does not close'
  has references/refine-mode.md 'releasing a test blocked by `epico-test-diff`'
}

@test "T4: the Red scratch lives under TMPDIR/epic-red, outside .epico, and is removed" {
  has agents/test-advisor.md '\$\{TMPDIR:-/tmp\}/epic-red/'
  has agents/test-advisor.md 'git worktree remove --force'
  has agents/test-advisor.md 'never create `\.draft/red-scratch/`'
}

@test "T5: in Standard, Unit tests are the Executor's, written first with inline Red; Full unchanged" {
  has references/phase-execution.md 'who writes which test'
  has agents/test-advisor.md 'in a standard story, unit tests are the executor'
  has agents/executor.md 'executor-authored unit test'
  has agents/executor.md 'red \(inline\)'
  has references/run-mode.md 'unit test to write first'
  has references/run-mode.md 'recorded_by: executor'
  has agents/auditor.md 'recorded_by: executor'
}

@test "T6: a bugfix story's regression test must fail on the commit before the fix" {
  has agents/auditor.md 'the guard must bite'
  has agents/auditor.md 'parent of the oldest commit'
  has agents/auditor.md 'regression test does not reproduce the defect'
  has references/validate-mode.md 'the guard must bite'
}

@test "T7: three failures of the same command end the sub-task as failed, inline route included" {
  has agents/executor.md 'three failures of the same command end the sub-task'
  has agents/executor.md '--status failed'
  has references/run-mode.md 'failing three times ends the sub-task'
}

@test "T-own-file: no case is added to a file that holds another sub-task's pre-authored test" {
  has agents/executor.md 'never add a case to a test file that holds a pre-authored test'
  has agents/executor.md '(its|their) own file'
  has references/tasks.md 'never names the file of another sub-task.s pre-authored test'
}

# Stage 1 — Foundation

**Goal:** the skeleton runs end to end and its checks pass.

Each task carries five lines — TODO, WHY, DO NOT, VERIFY, REF — plus its Complexity and Tests. Its
status is the checkbox alone. A story that works on a task names its ID in `roadmap:`.

## 1.1 Skeleton

- [ ] **1.1.1 Project skeleton with one passing test**
  - TODO: the entry point, the test runner and one test that exercises it.
  - WHY: every later task needs somewhere to run and a way to prove it ran.
  - DO NOT: add a dependency the standard library already covers.
  - VERIFY: the test command named in the README passes from a clean clone.
  - REF: [ARCHITECTURE §1](../ARCHITECTURE.md#1-stack)
  - Complexity: Simple · Tests: unit
- [ ] **1.1.2 The quality checks run in one command**
  - TODO: lint, type check, tests and the secret scan behind one command.
  - WHY: a check that needs remembering is a check that gets skipped.
  - DO NOT: run anything remote to prove it.
  - VERIFY: the command exits 0 locally, and non-zero when one check fails.
  - REF: [ARCHITECTURE §3](../ARCHITECTURE.md#3-rules)
  - Complexity: Simple · Tests: integration

## Risks

What could make this stage fail, and what would show it early.

## Dependencies

What this stage needs from outside the project.

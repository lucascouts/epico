---
story: 029-checkpoint-dependency-signal-and-edge-case-questions
type: feature
scale: standard
engineering: product
version: 2
created: 2026-10-26
last-refined: 2026-10-26
history:
  - v1: Initial story
  - v2: Q9 and Q10 gates rewritten as one runnable command each, from a clean clone
status: archived
---

# Story - Checkpoint dependency signal and edge-case questions

## Introduction

Two small, independent items from wave 0.24.0 of the briefing proposal (`.epico/docs/briefing-mode-proposal.md` §9). First, a stage can add a runtime dependency that no decision record mentions: the choice was made, but nobody recorded why, and the checkpoint that closes the stage never notices. A deterministic script reads the package manifests at the stage's base and at HEAD and lists every new runtime dependency no ADR names, and the checkpoint turns each one into a question for the owner. Second, the Tech Reviewer gets a list of edge-case questions to walk — boundaries, empty and huge input, concurrency, time, partial failure, permissions, retries — as questions to answer, never as a quota of findings: a review that finds nothing is a valid review.

## Requirements

### R1. New runtime dependencies listed between two revisions

**User Story:** As an owner closing a stage, I want the checkpoint to list every runtime dependency the stage added, so that a dependency nobody decided on is seen before the next stage builds on it.

#### Acceptance Criteria

- R1.1: THE SYSTEM SHALL provide `scripts/diff-dependencies.sh`, called through `bin/epico-depdiff`, that takes `--base <rev>` and optional `--head <rev>` (default `HEAD`) and `--root <dir>` (default the current directory)
- R1.2: THE SYSTEM SHALL read the manifests tracked by git at each revision — `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `requirements.txt`, `Gemfile` and `composer.json`, at any depth except under `node_modules/` and `vendor/` — and never read the working tree
- R1.3: THE SYSTEM SHALL count only runtime dependencies: `dependencies` and `optionalDependencies` of `package.json`; `require` lines of `go.mod` not marked `// indirect`; `[dependencies]` and `[target.*.dependencies]` of `Cargo.toml`; `[project] dependencies` and `[tool.poetry.dependencies]` of `pyproject.toml`; every requirement of `requirements.txt`; `gem` lines of a `Gemfile` outside a `:development` or `:test` group; and `require` of `composer.json` except `php` and `ext-*`
- R1.4: THE SYSTEM SHALL report as new each dependency name present in a manifest at the head revision and absent from the same manifest at the base revision, comparing Python names case-insensitively as pip does
- R1.5: WHEN a dependency's version changed or the dependency was removed THE SYSTEM SHALL leave it out of `new`
- R1.6: IF a manifest cannot be parsed at either revision THEN THE SYSTEM SHALL list it under `unparsed` with the reason, and no dependency of it in `new`
- R1.7: THE SYSTEM SHALL write one JSON object on stdout with `base`, `head`, `adr_dir`, `new` (each entry with `name`, `ecosystem`, `manifest` and `covered_by`), `uncovered` and `unparsed`, and exit 0
- R1.8: IF `--base` is missing or a revision does not resolve to a commit THEN THE SYSTEM SHALL exit 2 with the reason in the JSON

### R2. A dependency is covered only when an ADR names it

**User Story:** As an owner, I want a new dependency to count as decided only when a decision record names it, so that the signal does not depend on anyone's memory.

#### Acceptance Criteria

- R2.1: THE SYSTEM SHALL look for ADRs in `adr/` and `docs/adr/` at the head revision, the same paths `scripts/claude-md.sh` discovers
- R2.2: WHEN an ADR's text contains the dependency's full name as a whole word, case-insensitive, scoped names such as `@scope/pkg` included THE SYSTEM SHALL list that ADR file in the dependency's `covered_by`
- R2.3: WHEN a new dependency's `covered_by` is empty THE SYSTEM SHALL list it in `uncovered`
- R2.4: WHEN neither ADR directory exists THE SYSTEM SHALL set `adr_dir` to `null` and list every new dependency in `uncovered`

### R3. The checkpoint asks about each uncovered dependency

**User Story:** As an owner running a checkpoint, I want each undecided dependency put to me as a question, so that I either record the decision or accept it consciously.

#### Acceptance Criteria

- R3.1: THE SYSTEM SHALL run `epico-depdiff` in step 3 (*Decisions and rules*) of `references/checkpoint-mode.md`
- R3.2: THE SYSTEM SHALL state in `references/checkpoint-mode.md` how the base revision is chosen: the last commit that touched `.epico/checkpoints/<N-1>.yaml`, or the repository's first commit when no earlier checkpoint record exists
- R3.3: WHEN `uncovered` is not empty THE SYSTEM SHALL ask the owner, per dependency, to record an ADR, accept it without one, or mark it as not a runtime dependency — a judgment item, with no `(Recommended)` marker
- R3.4: THE SYSTEM SHALL record each answer in `.epico/checkpoints/<N>.yaml` like every other judgment item, and list each `unparsed` manifest in the checkpoint's output

### R4. Edge-case questions for the Tech Reviewer

**User Story:** As a developer whose code is reviewed, I want the Tech Reviewer to walk a fixed set of edge-case questions, so that common failure modes are checked every time without the reviewer inventing findings to fill a quota.

#### Acceptance Criteria

- R4.1: THE SYSTEM SHALL add an edge-case question list to `agents/tech-reviewer.md` covering boundaries and off-by-one, empty and huge input, concurrency, time and time zones, partial failure, permissions, and retries
- R4.2: THE SYSTEM SHALL state in `agents/tech-reviewer.md` that the list is a set of questions to answer for the code under review, that a question that does not apply is answered `n/a`, and that it is never a minimum number of findings
- R4.3: THE SYSTEM SHALL state in `agents/tech-reviewer.md` that a review with zero findings is a valid `PASS`
- R4.4: THE SYSTEM SHALL require the Tech Reviewer's report file to answer each edge-case question in one line: `n/a`, `checked — ok` or `issue — <file:line>`
- R4.5: THE SYSTEM SHALL state in `references/run-tech-review.md` that the orchestrator never asks a Tech Reviewer for more findings after a `PASS`

### R5. The rules are pinned by tests

#### Acceptance Criteria

- R5.1: THE SYSTEM SHALL cover `scripts/diff-dependencies.sh` with bats cases on real temporary git repositories: one per ecosystem in R1.3, a dev-only dependency not reported, a version change not reported, an unparsable manifest, a covered and an uncovered dependency, no ADR directory, and a bad revision
- R5.2: THE SYSTEM SHALL assert the text of R3 and R4 in bats contract tests, so a later edit that drops a rule fails the suite
- R5.3: THE SYSTEM SHALL keep every existing assertion over the edited files passing

## Quality Requirements

- Q1: Lint — `shellcheck scripts/*.sh bin/*` exits 0
- Q2: Unit tests — `bats tests/` passes, as a normal user
- Q3: Error handling — `diff-dependencies.sh` runs under `set -euo pipefail` and refuses with its reason in the JSON; the bats cases prove the refusal paths
- Q4: Dependency vulnerabilities — no dependencies; `trivy fs .` gives the verdict
- Q5: Secrets — `gitleaks git .` reports no leaks
- Q6: README — the install and check commands `README.md` names exist and run
- Q7: Supported and declared runtime — Claude Code 2.1.295+ stays declared in `README.md` and `CHANGELOG.md`
- Q8: Data integrity — no persisted data: the script only reads git objects and prints JSON
- Q9: Plugin schema — `claude plugin validate --strict` passes on `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills`, `agents` (signal: a published plugin)
- Q10: CI mirror — the `shellcheck`, `validate-examples`, `plugin-validate` and `bats` jobs pass under `act` with the local ubuntu-26.04 image (signal: `.github/workflows/`)

## Success Metrics

- On a fixture repository that adds one runtime and one dev dependency, `epico-depdiff` reports exactly the runtime one, and as `uncovered` until an ADR names it
- Every rule in R3 and R4 is found by a `grep` in its reference or agent and asserted by a test
- `bats tests/` stays green with no existing assertion deleted

## Constraints

- [CONSTITUTION] Scripts depend on bash, jq and git only: manifests are parsed with bash, `sed`/`awk` and `jq`, never a language runtime
- [CONSTITUTION] Every script speaks one JSON contract on stdout, documented in its header; exit 0/1/2 mean done/refused/bad usage
- [CONSTITUTION] TDD: each bats case is written and seen failing before the change that makes it pass
- [CONSTITUTION] A script a reference tells Claude to run is called through its `bin/epico-*` wrapper by bare name
- No hook: the signal runs only inside the checkpoint
- Assumption (owner's answer): only runtime dependencies count; dev, test and build dependencies are not reported
- Assumption (owner's answer): a project with no ADR directory gets every new dependency as a question
- Assumption (owner's answer): the edge-case questions go to the Tech Reviewer only; the Executor and the inline route do not change
- Assumption: a manifest that is not valid at one revision is reported in `unparsed`, never parsed by heuristics

## Out of Scope

- Lockfiles and transitive dependencies — only the manifest's direct list
- Removed dependencies and version changes
- Checking a dependency's trust (the package selection policy, briefing proposal §12) — a later story
- The edge-case list for the Executor or the inline route
- Manifests of other ecosystems (Maven, Gradle, NuGet, Swift, Dart, Mix)

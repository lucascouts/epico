---
story: 029-checkpoint-dependency-signal-and-edge-case-questions
type: feature
scale: standard
scale_reason: a new script with a JSON contract over seven manifest formats plus two reference/agent contracts, each needing a traceable requirement and test
engineering: product
requester: developer
run-model: opus
version: 2
created: 2026-10-26
last-refined: 2026-10-26
history:
  - v1: Initial story
  - v2: Q9 and Q10 gates rewritten as one runnable command each, from a clean clone
status: archived
---

# Implementation Plan - Checkpoint dependency signal and edge-case questions

## Overview

The dependency signal comes first: one script, `scripts/diff-dependencies.sh` behind `bin/epico-depdiff`, built test-first in four slices — the contract and revision handling, two groups of manifest parsers, then ADR coverage. The checkpoint reference wires it into step 3 once the script's JSON is fixed. The Tech Reviewer's edge-case questions are independent of both and come last; a whole-suite pass closes the plan.

## Task List

- [x] 1 - The dependency diff script
  - _Complexity: Moderate | Tests: Unit (bats, real temporary git repositories) | Risks: TOML and Gemfile parsed without a language runtime — keep each parser to the documented shapes and send anything else to `unparsed` | Dependencies: None_
  - Objective: `epico-depdiff --base <rev>` prints the new runtime dependencies between two revisions as JSON, with ADR coverage

  - [x] 1.1 - Contract, revisions and manifest discovery
    - Context:
      - Files: `scripts/checkpoint-reconcile.sh` (header and JSON shape to mirror), `bin/epico-checkpoint` (wrapper shape), `tests/checkpoint-reconcile.bats` (fixture style)
    - Objective: The script parses its flags, resolves both revisions to commits, lists the tracked manifests of each revision and prints the JSON envelope
    - ToDo: Write the header (usage, inputs, output, exits); parse `--base` (required), `--head` (default `HEAD`), `--root` (default `$PWD`); resolve each with `git -C "$ROOT" rev-parse --verify "<rev>^{commit}"` and exit 2 with `{"error": …}` when either fails or `--base` is missing; list manifests with `git ls-tree -r --name-only <rev>` filtered to the seven basenames, skipping paths under `node_modules/` and `vendor/`; read file content only with `git show <rev>:<path>`, never the working tree; print `{base, head, adr_dir, new: [], uncovered: [], unparsed: []}` with `jq -n`; add `bin/epico-depdiff` mirroring `bin/epico-checkpoint`
    - Tests: Integration · `tests/diff-dependencies.bats` — missing `--base` and `--base` with no value exit 2 with the reason in one JSON object; an unknown revision refused as base and as head; a tree as base and a blob as head refused, an annotated tag to a commit accepted; valid revisions exit 0 with base/head/adr_dir/new/uncovered/unparsed and empty lists when only a README changed; `--head` defaults to HEAD; `--root` defaults to cwd and revisions resolve in `--root`, never in cwd; a root that is not a git repository exits 2; an uncommitted or staged-only manifest edit leaves the output byte-identical; the `epico-depdiff` wrapper runs by bare name (authored, Red-verified)
    - Validation: `bats tests/diff-dependencies.bats` passes
    - Requirements: R1.1, R1.2, R1.7, R1.8, R5.1
    - Quality: Q2, Q3, Q8

  - [x] 1.2 - npm, Go and Cargo manifests
    - Context:
      - Docs: npm package.json — `dependencies`, `optionalDependencies`; Go modules reference — `require` blocks and `// indirect`; Cargo reference — `[dependencies]`, `[target.'cfg(…)'.dependencies]`, `[dev-dependencies]`, `[build-dependencies]`
    - Objective: Runtime dependency names of `package.json`, `go.mod` and `Cargo.toml`, diffed per manifest path
    - ToDo: `package.json`: `jq -r '(.dependencies // {}) + (.optionalDependencies // {}) | keys[]'`, and a `jq` failure sends the manifest to `unparsed` with its reason; `go.mod`: single-line and block `require`, dropping lines ending `// indirect`; `Cargo.toml`: names under `[dependencies]` and `[target.*.dependencies]` sections only, both `name = "1"` and `name = { … }` forms; a dependency is new when its name is in the head set and not in the base set of the same manifest path; a manifest absent at the base counts every name as new; version changes and removals produce nothing
    - Tests: Unit · `tests/diff-dependencies.bats` — package.json `dependencies`/`optionalDependencies` reported, `devDependencies`/`peerDependencies` not; go.mod single-line and block `require` reported, `// indirect` not; Cargo `[dependencies]` in both forms and `[target.'cfg(unix)'.dependencies]` reported, `[dev-dependencies]`/`[build-dependencies]` not; version bump and removal not reported; a manifest missing at base reports all its runtime names; a name already in `packages/a/package.json` but new in `packages/b/package.json` reported with manifest `packages/b/package.json`; a move from `dependencies` to `optionalDependencies` not new; a dev dependency promoted to `dependencies` new; a manifest at depth read; invalid JSON at base or at head goes to `unparsed` with none of its names in `new`
    - Validation: `bats tests/diff-dependencies.bats` passes
    - Requirements: R1.3, R1.4, R1.5, R1.6, R5.1
    - Quality: Q2, Q3

  - [x] 1.3 - Python, Ruby and PHP manifests
    - Context:
      - Docs: PEP 621 `[project] dependencies`; Poetry `[tool.poetry.dependencies]`; pip requirements-file format; Bundler Gemfile `group` blocks; Composer `require`
    - Objective: Runtime dependency names of `pyproject.toml`, `requirements.txt`, `Gemfile` and `composer.json`
    - ToDo: `pyproject.toml`: the `[project]` `dependencies = [ … ]` array (one or many lines) and the keys of `[tool.poetry.dependencies]` except `python`, names cut at the first of `<>=!~;[ (`, lower-cased; `requirements.txt`: one name per line, skipping blanks, comments, `-r`/`-e`/`--` options and URLs; `Gemfile`: `gem "name"` lines outside `group :development`/`:test` blocks (the inline `group:` option counted the same); `composer.json`: keys of `.require` except `php` and `ext-*`; any shape these rules do not cover goes to `unparsed` with the line that broke it
    - Tests: Unit · `tests/diff-dependencies.bats` — pyproject `[project] dependencies` on one and many lines, names cut from specifiers, extras and markers; `[tool.poetry.dependencies]` keys except `python`; `[project.optional-dependencies]` and poetry dev groups not reported; requirements.txt skips blanks, comments, `-r`/`-e`/`--` and URLs; `requests` → `requests-oauthlib` gives a new `requests-oauthlib`; a case-only rename not new; Gemfile top-level `gem` reported, `:development`/`:test` blocks and inline `group: :test` not, `group :production` reported; composer `require` except `php`/`ext-*`, `require-dev` not, `php-http/httplug` reported; an unclosed pyproject array goes to `unparsed`
    - Validation: `bats tests/diff-dependencies.bats` passes
    - Requirements: R1.3, R1.6, R5.1
    - Quality: Q2, Q3

  - [x] 1.4 - ADR coverage
    - Context:
      - Files: `scripts/claude-md.sh` line 68 (the ADR paths it discovers)
    - Objective: Each new dependency lists the ADRs that name it, and `uncovered` holds the rest
    - ToDo: Read `adr/*.md` and `docs/adr/*.md` from the head revision with `git ls-tree`/`git show`; set `adr_dir` to the list of directories found (`["adr"]`, `["docs/adr"]` or both), or `null` when neither exists; a dependency is covered by an ADR whose text matches its full name as a whole word, case-insensitive, with `grep -F -i -w` semantics adapted so `@scope/pkg` and `name-with-dashes` match whole; fill `covered_by` and `uncovered`; no ADR directory → every new dependency uncovered
    - Tests: Unit · `tests/diff-dependencies.bats` — an ADR naming `react-dom` does not cover `react`; `@scope/pkg-extra` does not cover `@scope/pkg`; bare `pkg` does not cover `@scope/pkg`; `serde_json` does not cover `serde`; `github.com/pkg/errors/v2` does not cover `github.com/pkg/errors`; `React` and `` `@Scope/Pkg`, `` do cover; an ADR only in the working tree does not cover; `adr/` and `docs/adr/` both read and named in `adr_dir`; two ADRs both in `covered_by`; a README mention does not cover; no ADR directory → `adr_dir: null`, everything uncovered; one runtime + one dev dependency reports exactly the runtime one, uncovered, then covered once an ADR is committed
    - Validation: `bats tests/diff-dependencies.bats` passes
    - Requirements: R2.1, R2.2, R2.3, R2.4, R5.1
    - Quality: Q1, Q2, Q3

  - Commit: "feat(029): epico-depdiff lists new runtime dependencies no ADR names"

- [x] 2 - The checkpoint asks about undecided dependencies
  - _Complexity: Simple | Tests: Unit (bats contract) | Risks: `tests/checkpoint-contract.bats` already pins the step list — keep its anchors | Dependencies: Task 1_
  - Objective: Step 3 of the checkpoint runs `epico-depdiff` and turns each uncovered dependency into a judgment question

  - [x] 2.1 - Step 3 of `references/checkpoint-mode.md`
    - Context:
      - Files: `references/checkpoint-mode.md` (The user leads; Procedure step 3; The record), `tests/checkpoint-contract.bats`
    - Objective: The reference runs the script, says how the base is chosen, asks per uncovered dependency with no recommended marker, records the answers and lists unparsed manifests
    - ToDo: In step 3 add: run `epico-depdiff --base <rev>` where `<rev>` is the last commit that touched `.epico/checkpoints/<N-1>.yaml` (`git log -1 --format=%H -- …`), else the repository's first commit (`git rev-list --max-parents=0 HEAD`); for each `uncovered` entry ask record an ADR / accept without one / not a runtime dependency, as a judgment item; print every `unparsed` manifest with its reason; the answers go to `.epico/checkpoints/<N>.yaml` as `step: 3` items; write "the user", never "the owner" (the provenance lint flags it); add `depdiff` to the name list in `tests/bin-wrappers.bats`
    - Tests: Unit · `tests/checkpoint-contract.bats` — inside step 3: `epico-depdiff --base`; the base rule (last commit touching `.epico/checkpoints/<N-1>.yaml`, else the first commit); the three options per uncovered dependency; every `unparsed` manifest listed; answers in `.epico/checkpoints/<N>.yaml`; step 3 still a judgment item (no `(Recommended)`); existing anchors kept; `depdiff` added to the name list in `tests/bin-wrappers.bats`
    - Validation: `bats tests/checkpoint-contract.bats` passes
    - Requirements: R3.1, R3.2, R3.3, R3.4, R5.2, R5.3
    - Quality: Q2, Q6
    - Commit: "feat(029): the checkpoint asks about each runtime dependency no ADR names"

- [x] 3 - Edge-case questions for the Tech Reviewer
  - _Complexity: Simple | Tests: Unit (bats contract) | Risks: None | Dependencies: None_
  - Objective: The Tech Reviewer walks seven edge-case questions, answers each in its report, and a review with no findings is a valid PASS

  - [x] 3.1 - The question list in `agents/tech-reviewer.md`
    - Context:
      - Files: `agents/tech-reviewer.md` (Focus Areas; Protocol step 4 report and verdicts)
    - Objective: A `## Edge-case questions` section with the seven questions, the `n/a` / `checked — ok` / `issue — <file:line>` answer per question in the report file, and the rule that it is never a minimum number of findings and zero findings is a valid PASS
    - ToDo: Add the section after Focus Areas — boundaries and off-by-one · empty and huge input · concurrency · time and time zones · partial failure · permissions · retries — each phrased as a question about the code under review; add to Protocol step 4 that the report file answers each question in one line; add the no-quota and zero-findings sentences beside the PASS verdict; write "the user", never "the owner"
    - Tests: Unit · `tests/edge-case-questions.bats` — a list section in `agents/tech-reviewer.md` naming the seven topics; `n/a` for a question that does not apply; never a minimum number of findings; zero findings is a valid `PASS`; the report answers each question with `n/a`, `checked — ok` or `issue — <file:line>`
    - Validation: `bats tests/edge-case-questions.bats` passes
    - Requirements: R4.1, R4.2, R4.3, R4.4, R5.2
    - Quality: Q2, Q9

  - [x] 3.2 - No second ask after a PASS in `references/run-tech-review.md`
    - Context:
      - Files: `references/run-tech-review.md` (Orchestrator Handling of Tech Review)
    - Objective: The orchestrator never asks a Tech Reviewer for more findings after a PASS
    - ToDo: Add the rule to the PASS bullet of Orchestrator Handling
    - Tests: Unit · `tests/edge-case-questions.bats` — within Orchestrator Handling of `references/run-tech-review.md`, the orchestrator never asks for more findings after a `PASS`
    - Validation: `bats tests/edge-case-questions.bats` passes
    - Requirements: R4.5, R5.2
    - Quality: Q2

  - Commit: "feat(029): edge-case questions for the Tech Reviewer, never a finding quota"

- [x] 4 - Whole-suite verification
  - _Complexity: Simple | Tests: None | Risks: count-pinned assertions in other suites over the edited files | Dependencies: Task 1, Task 2, Task 3_
  - Objective: Every check the legend names passes with the story's changes in place

  - [x] 4.1 - Run the full local suite and the CI mirror
    - Objective: The legend's commands all pass, from a clean clone for the CI mirror
    - ToDo: Run `shellcheck scripts/*.sh bin/*`, `bats tests/` as a normal user, `trivy fs .`, `gitleaks git .`, `claude plugin validate --strict` on the four targets, and the four `act` jobs with the local ubuntu-26.04 image from a clean clone; fix what fails inside this story's files, and record anything pre-existing as such
    - Validation: every command above exits 0, or its failure is shown to predate the story
    - Requirements: R5.3
    - Quality: Q1, Q2, Q4, Q5, Q6, Q7, Q9, Q10
    - Commit: "test(029): whole-suite verification"

- [x] 5 - Validation fixes — round 1
  - _Complexity: Simple | Tests: Unit (bats) | Risks: None | Dependencies: Task 1, Task 2_
  - Objective: The audit's advisory warnings and untested refusal branches are closed

  - [x] 5.1 - A Gemfile statement separator goes to unparsed
    - Objective: `gem "a"; gem "b"` and a one-line `group … do; …; end` are refused rather than half-read
    - ToDo: In `depdiff_names_gemfile`, a `;` outside a string on a code line fails the manifest with the line quoted
    - Tests: Unit · `tests/diff-dependencies-hardening.bats` — two gems on one line and a one-line group block each send the Gemfile to `unparsed`, none of their names in `new`
    - Validation: `bats tests/diff-dependencies-hardening.bats` passes
    - Requirements: R1.6
    - Quality: Q2, Q3

  - [x] 5.2 - The refusal branches that had no test
    - Objective: Every refusal of `diff-dependencies.sh` is pinned by a case
    - ToDo: Cases for an unknown argument, an empty `--head`, a `--root` that is not a directory, jq missing from PATH, and `--help`
    - Tests: Unit · `tests/diff-dependencies-hardening.bats` — the four refusals exit 2 with one JSON object naming the reason; `--help` exits 0 and prints the usage line
    - Validation: `bats tests/diff-dependencies-hardening.bats` passes
    - Requirements: R1.8
    - Quality: Q2, Q3

  - [x] 5.3 - Step 3 shows a refusal instead of reading it as nothing new
    - Objective: The checkpoint never reads an `epico-depdiff` refusal as an empty `uncovered` list
    - ToDo: In step 3 of `references/checkpoint-mode.md`, on exit 1 or 2 show the `error` to the user and ask about the stage's dependencies by hand
    - Tests: Unit · `tests/checkpoint-contract.bats` — step 3 names exit 1 or 2, shows the `error`, and never treats it as no new dependency
    - Validation: `bats tests/checkpoint-contract.bats` passes
    - Requirements: R3.1, R3.3
    - Quality: Q2
    - Commit: "fix(029): validation fixes — round 1"

## Quality Gates

- [x] All acceptance criteria validated
- [x] All task validations pass
- [x] All tests written and passing
- [x] Code integrated (no orphaned implementations)
- [x] Error handling implemented
- [x] Q1 — Lint: `shellcheck scripts/*.sh bin/*` exits 0
- [x] Q2 — Unit tests: `bats tests/` passes, as a normal user
- [x] Q3 — Error handling: `bats tests/diff-dependencies.bats` proves every refusal path of `diff-dependencies.sh`
- [x] Q4 — Dependency vulnerabilities: `trivy fs .` — no dependencies
- [x] Q5 — Secrets: `gitleaks git .` reports no leaks
- [x] Q6 — README: the install and check commands `README.md` names exist and run
- [x] Q7 — Supported and declared runtime: Claude Code 2.1.295+ declared in `README.md` and `CHANGELOG.md`
- [x] Q8 — Data integrity: no persisted data — the script reads git objects and prints JSON
- [x] Q9 — Plugin schema, from a clean clone of HEAD (the working tree's gitignored CLAUDE.md is not part of the plugin): `d=$(mktemp -d) && git clone -q . "$d/e" && cd "$d/e" && for t in .claude-plugin/plugin.json .claude-plugin/marketplace.json skills agents; do claude plugin validate --strict "$t" > /dev/null || exit 1; done`
- [x] Q10 — CI mirror, from a clean clone of HEAD: `d=$(mktemp -d) && git clone -q . "$d/e" && cd "$d/e" && for j in shellcheck validate-examples plugin-validate bats; do act -P ubuntu-26.04=epico-act:26.04 --pull=false -j "$j" > /dev/null || exit 1; done`

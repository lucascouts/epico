# Architecture

Design-level view of the Epico plugin for contributors and integrators. The [README](README.md) covers *what* Epico is and how to install it; this document covers *how the pieces fit together* and *why*.

- Last verified against: **v0.23.1** (`.claude-plugin/plugin.json`)
- If you only want to add a new story mode or tweak an agent prompt, jump to [Extension points](#extension-points).

---

## Reading guide

| If you want to… | Read |
|---|---|
| Understand the end-to-end flow | [Conceptual model](#conceptual-model) |
| Know which file does what | [Component map](#component-map) |
| Trace who calls whom | [Sub-agent pipeline](#sub-agent-pipeline) |
| Know what agents read/write | [Artifact contracts](#artifact-contracts) |
| Debug a hook firing | [Hook matrix](#hook-matrix) |
| Understand how implementation happens | [Executor 6-step protocol](#executor-6-step-protocol) |
| Understand the validation layers | [Validation layers](#validation-layers) |
| Know how E2E tooling is chosen | [Preferred-tooling policy](#preferred-tooling-policy) |
| Know why a choice was made | [Architectural decisions](#architectural-decisions) |

---

## Conceptual model

Epico turns an unstructured request into a tracked, validated implementation through three phases. Each phase has explicit artifacts, explicit gates, and specialized personas.

```
             ┌──────────────────────── Plan ────────────────────────┐
user request │  triage ─► analyst ─► clarify ─► phases (main agent)│
             │                    │           │                     │
             │                    │           ▼                     │
             │                    └──► story.md ─► design.md        │
             │                                         │            │
             │                                         ▼            │
             │                             test-advisor ─► tasks.md │
             │                                         │            │
             │                              reviewer ◄─┘ (full)     │
             └──────────────────────────────┬───────────────────────┘
                                            │
             ┌────────────────── Execute ───▼────────────────────┐
             │  per sub-task: executor (6 steps) ─► tech-reviewer│
             │                                        (boundary) │
             └────────────────────────┬──────────────────────────┘
                                      │
             ┌────────────────── Verify ─▼──────────────────────┐
             │  auditor: validation, then audit (one spawn)      │
             └───────────────────────────────────────────────────┘
```

Scale (Fast / Standard / Full) controls which artifacts exist and which personas activate. The triage step emits a single proposal covering mode, workflow variant, MCPs, and output path — see [`skills/epico/SKILL.md`](references/triage.md#triage-protocol).

---

## Component map

The plugin surface maps to Claude Code's extension points:

| Directory | Claude Code hook point | Role |
|---|---|---|
| `skills/epico/` | Skill | The `/epico:epico` entry point. Parses `$ARGUMENTS`, routes to modes, orchestrates agents, writes artifacts. |
| `agents/` | Sub-agents | 8 specialized personas with bounded tool access and dedicated context windows. |
| `hooks/hooks.json` | Hooks | 9 hook events, each `if:`-filtered to `.epico/**` paths or tool-arg patterns. |
| `output-styles/epic.md` | Output style | Optional structured presentation mode. |
| `bin/` | PATH executables | `epico-validate`, `epico-xref`, `epico-archive` — thin wrappers over `scripts/`. |
| `scripts/` | — | Bash implementations behind hooks, bin, and CI. |
| `references/` | — | Mode-specific operational guides loaded on-demand by the skill. |
| `.claude-plugin/plugin.json` | Manifest | Plugin metadata + `userConfig` schema. |
| `assets/examples/` | — | Reference artifacts for each scale, used as format anchors. |
| `evals/` | — | Native `claude plugin eval` suite (trigger and end-to-end cases), and `README.md` — how to run it and why a trigger score must not gate anything. |
| `tests/` | — | `bats` unit tests for scripts. |

---

## Sub-agent pipeline

Epico's sub-agents are activated by scale and phase. The main agent orchestrates, writes the artifacts, runs the Completeness Checklist itself, and implements a closed-spec sub-task inline.

### Who activates when

| Persona | Fast | Standard | Full |
|---|---|---|---|
| Analyst (codebase scan) | — | triage, when code exists | triage, when code exists |
| Test-advisor | — | Phase 3 | Phase 3 |
| Reviewer | — | — | after Phase 3 |
| Executor | a parallel group's members, and context-free sub-tasks (a test from the spec, a disposable file) — anything that needs the session's context runs inline | same | same |
| Tech-reviewer | technology boundary, or `High` complexity | same | same |
| Auditor | validate mode — validation, then audit on a pass | same | same |

### Context isolation

Each sub-agent runs in its own context window. The main agent selects inputs (file list, design excerpt, sub-task text) and the sub-agent returns a structured report. No persona has access to the full conversation by default — this is what allows Epico to keep long orchestrations within context limits.

### Tool scoping

Each `agents/*.md` declares its allowed tools. Narrower scopes catch drift early:

- `executor`: `Read, Write, Edit, Bash, Glob, Grep` (implements code)
- `auditor`: `Read, Glob, Grep, Bash, LSP, Write` — `LSP` reads symbols; `Write` reaches exactly two paths, `.draft/validation-report.yaml` (validation, Part 1) and `.draft/audit-report.yaml` (audit, Part 2)
- `test-advisor`: `Read, Write, Bash, Glob, Grep` — it authors the failing tests for test-first sub-tasks (`Write`) and runs them to capture Red evidence (`Bash`). Its scope covers `Unit`, `Integration` and `E2E` sub-tasks — an `E2E` test is authored against the story's selected E2E tool (see [Preferred-tooling policy](#preferred-tooling-policy)) with Red-phase verification **deferred to Run mode**, so for those sub-tasks the Test Advisor writes the file but does not run `Bash`.
- `analyst`, `reviewer`: read-only surfaces
- `tech-reviewer`: `Read, Glob, Grep, Bash, WebFetch, WebSearch` — `Bash` is measurement only (linters, compilers, greps, query plans), never a mutation of files or git state, so a finding that rests on a runnable check can carry the command and the output backing it

The Auditor's two report writes are **carve-outs, not licences**: each part names its one file, creates `.draft/` on demand, and treats any other write as a protocol violation. Nothing enforces that at runtime — the guard is the exact-set grant assertion in `tests/reports-by-artifact-policy.bats`, which reddens when a tool lands on an agent this list does not name.

### Effort tiers

Each `agents/*.md` also declares a reasoning `effort:`. The tier is a cost decision, and this table is the policy itself — not a summary of one kept elsewhere:

| Agent | Effort | Why |
| --- | --- | --- |
| `executor` | `high` | Writes the code. `max` wrote the same passing tests on a large closed-spec sub-task for several times the cost and wall clock. |
| `auditor` | `high` | Holds the semantic judgment the rest of the pipeline is priced against. Measured against `max` on fixtures with planted defects: every planted defect found in every arm, at about half the cost and wall clock. |
| `reviewer` | `high` | Cross-artifact gaps are found by reasoning over three documents at once. |
| `tech-reviewer` | `high` | Correctness at technology boundaries — the defect is precisely what a generalist would not think to look for. |
| `test-advisor` | `high` | Authoring a test that fails for the right reason is a design act, not a transcription. |
| `analyst` | `medium` | Discovery: scans structure, samples representative files, reports what it found. |

**The table is enforced, not descriptive.** `tests/agent-effort-policy.bats` derives the tiers from the frontmatters and compares them against these rows, so a change on either side reddens until both agree. It also pins the Executor and the Auditor at `high` or above by name: they carry the judgment the rest of the pipeline is priced against, and a silent drop below `high` would keep a saving while removing the safety net.

---

## Artifact contracts

Artifacts are the stable interface between phases and between agents. Agents pass *artifacts*, not conversation state.

### Story directory layout

```
.epico/stories/NNN-kebab-name/
├── story.md              # requirements (EARS), written phase 1
├── design.md             # design context, written phase 2 (Full only)
├── tasks.md              # hierarchical tasks + validation cmds, phase 3
├── deviation-register.md # appended by executor on INTENTIONAL deviations
└── .draft/               # persisted mid-flight state (gitignored)
    ├── story.md          # after Phase 1 approval
    ├── design.md         # after Phase 2 approval
    ├── meta.yaml         # phase + project-hash + analyst cache
    ├── authored-tests/   # failing test files authored in Phase 3 (test-first)
    ├── red-evidence.yaml # Red-phase verification record per pre-authored test
    └── *.md.wip          # section-progress markers inside long artifacts
```

### Frontmatter contract

Every artifact carries a shared frontmatter block. See [`references/output-rules.md`](references/output-rules.md):

```yaml
---
story: <story-name>
type: feature | bugfix
scale: fast | standard | full | spike
version: 1
created: <date>
# optional on refine:
last-refined: <date>
history: [...]
---
```

All files in a story share the same `version`. It's an integer, not semver; bumped only via Refine mode.

### Cross-reference rules

- Requirements in `story.md` use R-numbers (`R1`, `R1.1`, `R2`) and must be independently testable.
- `design.md` components reference R-numbers they satisfy.
- `tasks.md` sub-tasks reference the R-number(s) they realize and the design component(s) they implement.
- `scripts/cross-reference.sh` enforces traceability (required for `--strict`).
- `scripts/story-telemetry.sh` reports tokens and wall clock from a session transcript — read-only, no writes, no network, deduplicated by `message.id`.

### Archive immutability

`.epico/archive/**` is read-only at the tool level: `hook-archive-guard.sh` blocks `Write`/`Edit` via `PreToolUse`. Story numbers are never recycled — archive retains numbers permanently.

---

## Hook matrix

All hooks live in `hooks/hooks.json` at plugin scope, not skill frontmatter — so they fire on Claude's `.epico/**` writes even outside a `/epico:epico` session (another skill, a plain `Write`). A skill-frontmatter hook would start only once the skill is invoked, and then stay active for the rest of the session. Tool hooks never see edits made in an external editor. Each uses an `if:` filter or matcher to stay cheap when Epico is idle.

| Event | Matcher / if-filter | Script | Purpose |
|---|---|---|---|
| `PostToolUse` | `Write(**/.epico/**)` | `hook-validate.sh` | Auto-run `validate-story.sh` on every story-artifact write |
| `PreToolUse` | `Edit(**/.epico/archive/**)` · `Write(**/.epico/archive/**)` | `hook-archive-guard.sh` | Block mutations to archived stories |
| `PreToolUse` | `Bash` (no filter) · `Edit`/`Write` of `**/.epico/stories/**/tasks.md` | `hook-executor-guard.sh` | Inside the Executor (`agent_type`), deny `git commit` and edits to `tasks.md` |
| `PreToolUse` | `Bash` (no filter) | `hook-commit-identity-guard.sh` | Deny a commit that supplies its own identity, and any `git config user.*` write |
| `SubagentStop` | `epico:auditor` | `hook-report-guard.sh` | Keep the agent running until its report file is on disk |
| `Stop` | — | `hook-legend-guard.sh` | For a `layperson` requester, block the end of a turn once while a process word from any of its text has no legend, naming each word |
| `Stop` | — | `hook-commit-guard.sh` | Block the end of a turn once while a finished group's pre-authored commit is missing, naming the message |
| `SessionStart` | `compact` | `hook-session-restore.sh` | After a compaction, render the active story's state from disk into context |
| `SessionStart` | `clear` | `hook-orphan-drafts.sh` | After `/clear`, list drafts untouched for 30+ days, one removal line each; deletes nothing |
| `SessionStart` | `startup\|resume\|clear` | `doctor.sh --summary` | One line naming what is wrong with `.epico/`, nothing when healthy; read-only |

`if` patterns start with `**/` because a pattern is matched against the working directory: `Edit(.epico/**)` misses every call made from a subdirectory. The `PreToolUse` guards carry `"onFailure": "block"`, so a guard that cannot run blocks the call instead of letting it through. Minimum Claude Code: 2.1.295 for the whole plugin.

---

## Executor 6-step protocol

A sub-task passes through the executor as an ordered pipeline. Skipping any step is a protocol violation — the auditor catches this. Full definition in [`agents/executor.md`](agents/executor.md).

The protocol has **six steps**. Steps 2 and 5 are *conditional* — their wording depends on whether the sub-task carries a pre-authored failing test (a test-first sub-task) or not (a test-after sub-task):

1. **Context gathering** — read every file/doc listed in the sub-task's `Context:` field before writing code.
2. **Implementation** (**Green** for a test-first sub-task) — implement literally what `ToDo:` says; deviate only with a documented reason. For a test-first sub-task the goal is to make the pre-authored failing test pass; the test is a read-only input whose assertions are immutable.
3. **Design fidelity check** — diff the implementation's signatures, error paths, data structures, and contracts against `design.md`. Classify deviations as INTENTIONAL (with rationale, appended to deviation register) or ACCIDENTAL (fix before proceeding).
4. **Validation** — run the sub-task's `Validation:` command; report full output. On failure, STOP.
5. **Refactor** (test-first sub-task) **/ Tests** (test-after sub-task) — for a test-first sub-task, improve the implementation while the pre-authored test and the validation command stay green. For a test-after sub-task, create/run the tests listed in the sub-task's `Tests:` field. On failure, STOP.
6. **Report** — structured report back to the main agent, ending in a machine-liftable **closing block**: the sub-task id, the outcome (`done`, `close-tilde` with a qualifier and a reason, or `failed`), and the pre-authored commit message the executor validated against.

The closing block is where the protocol hands off, and it hands off a *report*, never a write. **The executor marks no box and runs no `git commit`** — marking is script-mediated: the main agent lifts the block into `scripts/close-subtask.sh`, which marks the box, takes the census, stamps `status:` and validates the story in one transaction, and it commits post-merge with the pre-authored message verbatim. A `failed` outcome makes no call at all: the box stays `[ ]`. A box left `[~] (deferred: …)` is discharged later by the same script's `--fulfill` flag — the one exit from a deferral — or has its reason replaced in place by `--restate`, both defined in [references/tasks.md](references/tasks.md#discharging-a-deferral).

The main agent does not implement code; the executor does not make scope decisions, and does not write the record of its own completion. This separation is load-bearing for the auditor's effectiveness.

---

## Validation layers

Epico has four distinct validation layers, each catching a different failure mode:

| Layer | When | What it catches | Script / agent |
|---|---|---|---|
| Artifact validation | On every write to `.epico/**` | Malformed frontmatter, missing sections, bad YAML | `scripts/validate-story.sh` (via `hook-validate.sh`) |
| Cross-reference | Manual or `--cross-ref` flag | Orphan R-numbers, design components unreferenced by tasks, tasks without R-numbers | `scripts/cross-reference.sh` |
| Task validation | After each sub-task | Implementation fails the sub-task's declared validation command | `validator` sub-agent + `scripts/validate-story.sh` |
| Story audit | After all tasks complete | Scope creep, deviations not in register, unmet quality gates, integration gaps, missing Red evidence | `auditor` sub-agent |

The story audit includes a **Red-evidence gate** (auditor check #10): every sub-task that carries a pre-authored test must have a corresponding entry in `.draft/red-evidence.yaml` showing the test failed before implementation. A missing entry fails the audit. This gate is **Standard/Full only** — those scales stage tests at plan time. Fast mode is **test-first at run time**: the main agent authors a `Tests`-bearing sub-task's test and confirms it fails (Red) before implementation, then proceeds Green-then-Refactor. Fast keeps its lightweight scale — no `.draft/`, no `red-evidence.yaml` — so its Red confirmation lives in the Run report only and is not gated by the auditor. A Fast sub-task with no testable logic pins behavior via an optional `Acceptance` field (1–3 observable-behavior statements) instead; the `Acceptance` field is the Fast intent anchor when no test exists, and every implementing (non-Commit) Fast sub-task carries either a `Tests` field or an `Acceptance` field.

`--strict` mode promotes warnings to errors (exit 1 on any warning) — use it in CI gates.

---

## Story lifecycle

```
(request) ─► triage ─► clarify ─► Phase 1 ─► .draft/story.md + meta.yaml
                                    │
                                    ▼
                                  Phase 2 (Full) ─► .draft/design.md
                                    │
                                    ▼
                                  Phase 3 ─► tasks.md + artifacts promoted from .draft/
                                    │
                                    ▼
                                  Run mode ─► executor per sub-task ─► close-subtask.sh
                                    │
                                    ▼
                                  Validate mode ─► auditor (validation, then audit)
                                    │
                                    ▼
                                  Archive ─► .epico/archive/NNN-name/  (read-only)
```

Numbers auto-increment across `stories/` + `archive/` and are never recycled. A `999` cap forces archival before further stories are created.

---

## Architectural decisions

Short rationale for choices a contributor might otherwise second-guess:

### Bash for scripts, not Node/Python

All hook scripts and validators are bash. The plugin has zero runtime dependencies beyond `bash`, `git`, `jq` — which are baseline for any development environment. Adding Node/Python would force users into a runtime install for a plugin that mostly shells out to CC itself.

### Single skill (`/epico:epico`), not multiple slash commands

Every mode (Create, List, Run, Validate, Refine, Archive, Init) lives under `/epico:epico` via `$ARGUMENTS` routing. This keeps discovery simple (one command to remember), concentrates triage/orchestration in one place, and lets reference files share context-loading rules. Modes that diverge heavily load dedicated `references/*-mode.md` files on entry.

### Scale-adaptive (Fast / Standard / Full)

Forcing full planning ceremony on a 1-file change is user-hostile; skipping planning on a 10-file cross-cutting change is risk-hostile. Scale is chosen per-story during triage with an explicit trade-off statement. Upgrade paths exist (Fast → Standard → Full) if scope grows during planning.

Test-first ordering is scale-adaptive too. Standard and Full author failing tests at **plan time** (Test Advisor, Phase 3) and stage them in `.draft/authored-tests/`. Fast is test-first at **run time**: there is no Test Advisor sub-agent, no `.draft/`, and no `red-evidence.yaml`. For a Fast sub-task carrying a `Tests` field the main agent authors the test and confirms it fails (Red) before implementation, then proceeds Green-then-Refactor — a Trivial sub-task runs this inline as a single author, while a Simple-or-higher sub-task has the main agent author and Red-verify, then pass the confirmed-failing test to the Executor as a read-only **Pre-Authored Test** input. The Executor (`agents/executor.md`) is the same at every scale: its conditional six-step protocol consumes a Pre-Authored Test section regardless of scale.

### English-only artifacts, user's language in chat

Artifacts (story/design/tasks) are always English because Claude performs best on English technical content and these artifacts are consumed by later sub-agents. User-facing chat follows the user's prompt language. No override — this is in [SKILL.md](skills/epico/SKILL.md#language).

### Hooks at plugin scope, not skill frontmatter

Plugin-scope hooks fire when the user edits `.epico/**` outside an active `/epico:epico` session (plain `Edit`, external editor, another skill). Skill-frontmatter hooks would only apply during skill execution — none of Epico's hooks fit that profile. Detailed rationale is embedded in [SKILL.md](skills/epico/SKILL.md#validation).

### Archive immutability via PreToolUse block, not convention

A `PreToolUse` hook on `.epico/archive/**` returns a blocking response. Convention-only (a note in the README) would fail when an agent writes without reading the convention. Enforcement at the tool layer is robust against both drift and unfamiliar users.

### Degrade gracefully on missing MCPs

Research MCPs (`brave-search`, `exa`, `tavily`, `firecrawl`, `perplexity`) are health-checked during triage. Library docs need no MCP: they come from the installed dependency, then the official docs for that version. A missing MCP never blocks the flow — the skill substitutes an alternative or skips that category. No user-visible errors for optional tooling.

---

## Preferred-tooling policy

Epico is opinionated about E2E test tooling so stories do not silently adopt whatever happens to be installed. The full policy lives in [`references/preferred-tooling.md`](references/preferred-tooling.md); the architectural shape is:

- **Favorites vs optional.** Favorite E2E tools are `playwright` and `chrome-devtools`. Optional E2E tools (`puppeteer`, `selenium`, `browser-use`, `stagehand`) are accepted but never auto-selected over a favorite.
- **Three-mechanism detection.** Triage detects installed tools via (1) MCP health-check, (2) dependency-manifest inspection, and (3) skill-list presence. Detection runs in **all modes, including Fast** — it is not gated by scale.
- **Recommend-and-pause fallback.** When no favorite is installed, triage surfaces a recommendation and pauses rather than silently choosing an optional tool.
- **Where it surfaces.** Triage (`skills/epico/SKILL.md`) carries step 7b "Detect preferred tooling", a `### Preferred Tooling` subsection, and a `> - Tooling:` proposal line. The resolved selection is persisted to `design.md`'s `## Tooling Decisions` block, which the Test Advisor reads when authoring `E2E` tests.
- **Frontend aid.** When the `frontend-design` skill is installed it is the preferred frontend implementation aid.

---

## Extension points

Common contributions and where they go:

| Change | Touch |
|---|---|
| New story mode (e.g., `review`, `rollback`) | Add routing line in [SKILL.md](skills/epico/SKILL.md#command-routing), create `references/<name>-mode.md`, add mode row to Mode Dispatch table |
| New sub-agent persona | Add `agents/<name>.md` with frontmatter (tools, effort, model), wire activation in SKILL.md's persona tables and relevant phase procedure |
| New hook event | Append to `hooks/hooks.json` with `if:` filter, add script under `scripts/hook-*.sh`, document in [Hook matrix](#hook-matrix) |
| New validation rule | Extend `scripts/validate-story.sh` (errors vs warnings), add a `bats` test under `tests/` |
| New user-config field | Add schema entry under `userConfig` in `.claude-plugin/plugin.json`, read via `${CLAUDE_PLUGIN_CONFIG_*}` env in scripts |
| New eval case | Add a case directory under `evals/` (`prompt.md` + `graders/`), run with `claude plugin eval . --no-publish` |

Before adding a new reference file under `references/`, check whether existing ones can absorb the content — reference fragmentation hurts skill-load discoverability.

---

## Non-goals

Epico deliberately does not do these things. Adding them would conflict with the design:

- **Idea exploration.** Epico formalizes work already decided. It does not brainstorm alternatives or write speculative code.
- **Generic code generation outside a story.** The `/epico:epico` command refuses to implement without an approved task.
- **Repo-wide refactors as a single story.** Breaking large refactors into multiple stories is the correct pattern (linked via "based on" / "extends").
- **Runtime dependencies beyond bash/git/jq.** MCPs are optional and health-checked; their absence degrades gracefully.
- **Version-controlled drafts.** `.epico/` (including `.draft/`) is `.gitignored` by default; the user decides when a story is ready to commit.

---

## See also

- [README.md](README.md) — installation, feature list, version-compatibility matrix
- [`skills/epico/SKILL.md`](skills/epico/SKILL.md) — the orchestrator, command routing, phase execution
- [`references/phase-gates.md`](references/phase-gates.md) — gate protocol, cascade rollback, section progress
- [`references/ci-mode.md`](references/ci-mode.md) — headless invocation, deferred commits
- [`references/mcp-integration.md`](references/mcp-integration.md) — MCP health-check procedure
- [`references/constitution.md`](references/constitution.md) — project-level constraints on stories
- [`CHANGELOG.md`](CHANGELOG.md) — release notes per version
- [`RELEASING.md`](RELEASING.md) — what a version cut involves, and the traps in it

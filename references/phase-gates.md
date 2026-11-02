# Phase Gates


## Contents

- [Gate Protocol](#gate-protocol)
- [Cascade Rollback](#cascade-rollback)
- [Section Progress](#section-progress)
- [Reference Files Loaded Per Phase](#reference-files-loaded-per-phase)
- [Integration points and gotchas (Full mode, before Phase 2)](#integration-points-and-gotchas-full-mode-before-phase-2)
- [Test Advisor Sub-agent (Standard + Full, during Phase 3)](#test-advisor-sub-agent-standard--full-during-phase-3)
- [Reviewer Sub-agent (Full mode only)](#reviewer-sub-agent-full-mode-only)
- [Traceability Check](#traceability-check)
## Gate Protocol

Each phase: generate artifact > **write to disk** > notify user > gate (approve / request changes / abort).

**Write-first, chat-minimal approach:** Artifacts are written directly to the story directory. **Never show full file contents in chat** — this wastes context and clutters the conversation. The user accesses files directly to review.

**Three-step notification pattern:**
1. **Before writing:** "Creating `story.md`..."
2. **After writing:** "Phase 1 written to `.epico/stories/NNN-name/story.md`. Review and approve to continue."
3. **User reviews the file directly** — they can edit it or request changes via chat.

- Do NOT paste artifact contents into the chat — the file IS the artifact
- If the user rejects a phase, offer cascade rollback (see below)
- If the user edits the file directly, read the updated version before proceeding to the next phase
- If the user aborts, delete the entire story directory
- In a headless run nobody reviews: the gate is taken as approved and the next phase starts ([triage.md](triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage))

**For a `layperson` requester the gate is one line, not a file review** — what will be built, in their words, and two answers: go on, or change something ([plain-register.md](plain-register.md#gates-are-one-line)). The artifact is written exactly as for anyone else; what changes is what they are asked to read. A layperson cannot evaluate a technical document, so their approval of one tells you nothing. Every gate counts against the story's question budget ([clarify.md](clarify.md#clarify-protocol)).

## Cascade Rollback

When a user rejects Phase N, determine the cause:

1. Ask: "What needs to change?"
   - **(a) This phase only** — rewrite the current phase artifact with different approach
   - **(b) Previous phase impact** — a requirement/decision in Phase N-1 needs to change
   - **(c) Abort** — cancel this story

2. If **(b)**, generate a **delta reverso** automatically:

```markdown
## Cascade Rollback: Phase N → Phase N-1

### Reason
[Why the current phase revealed a problem in the previous phase]

### Proposed Delta to [phase N-1 artifact]

#### MODIFIED
- [requirement/component]: [old] → [new]

#### IMPACTED
- [downstream items that may need re-evaluation]

### Action
1. Apply delta to [artifact]? [y/n]
2. If yes, re-approve [artifact]
3. Then regenerate current phase with updated constraints
```

3. Apply delta only after user approval, then regenerate the current phase.

## Section Progress

During phase generation, save incremental progress so a **new** session can tell which sections are done. An interruption inside the same conversation needs none of this: `claude --continue` (or `--resume`) reopens it with the partial artifact already on disk. This ledger is not Claude Code's checkpointing (`/rewind`).

### Progress File Format

Before generating each major section of an artifact, write a `.wip` file:

```yaml
# .epico/stories/NNN-name/.draft/story.md.wip
progress: 3
sections_completed:
  - frontmatter
  - introduction
  - R1-user-registration
sections_pending:
  - R2-user-login
  - R3-logout
  - remaining-sections
```

The partial artifact is written to disk incrementally. A progress marker is inserted:

```markdown
<!-- PROGRESS:3 — resume from here -->
```

### Resume Procedure

On detecting a `.wip` file:

1. Read the `.wip` to determine progress
2. Present: "Found incomplete Phase N (M/T sections written: [list]). Resume from [next section], or restart Phase N?"
3. If resume: read the partial artifact, continue generating from the progress marker
4. If restart: delete the `.wip` and partial artifact, regenerate from scratch

### Rules

- `.wip` files are deleted after the phase artifact is complete (before gate)
- `.wip` files are always gitignored
- Only one `.wip` file per artifact at a time

## Reference Files Loaded Per Phase

| Phase | Feature Req-First | Feature Design-First | Bugfix |
|---|---|---|---|
| Phase 1 | `ears-notation.md` + `requirements.md` | `design-guide.md` | `bugfix.md` + `ears-notation.md` |
| Phase 2 | `design-guide.md` | `ears-notation.md` + `requirements.md` | `bugfix-design.md` |
| Phase 3 | `tasks.md` | `tasks.md` | `tasks.md` |

[quality-catalog.md](quality-catalog.md) is loaded with `requirements.md` — the `## Quality Requirements` legend is written in Phase 1 — and again with `tasks.md`, where the gates are generated from it, in every mode.

For Fast mode, `tasks.md` and `quality-catalog.md` are loaded — the legend lives at the top of `tasks.md`.
For Standard mode, Phase 1 + Phase 3 references are loaded.
[engineering-level.md](engineering-level.md) is loaded with `tasks.md` in every mode: what the quality catalog activates and the shape of Phase 3 are read from it.

On format doubts, load the relevant example from `assets/examples/`.

Additionally, if `.epico/constitution.md` is present, its relevant sections are loaded as constraints (the project's `CLAUDE.md` is already in context).

## Integration points and gotchas (Full mode, before Phase 2)

Before writing design.md, the **main agent** adds what the Analyst's triage scan could not produce, because it ran before `story.md` existed. **No sub-agent**: every input — the Analyst's scan, `story.md`, the request — is already in the main agent's context, and a spawn would re-read all of it from empty, and a gotcha that has to cross a spawn boundary is the one that fails to reach `design.md`. Skipped for Fast and Standard.

1. **Integration points, against the written requirements.** Start from the Analyst's list — do not rescan patterns, conventions or dependencies it already reported. Name where *this story* connects: the files, functions, signatures and contracts it must meet, and which it must not break. Read only the files that settles. On `none: empty repository` there is nothing to integrate with — write `none — greenfield`.
2. **Implementation gotchas.** For each pattern or library this story needs, research known pitfalls, misconfiguration and non-obvious setup (a docs MCP, `WebFetch` or `WebSearch`). Write each as `GOTCHA: [pattern/library] — [what goes wrong] — [correct approach]`, specific enough to survive into a ToDo: not "use base layout pattern" but "parse each page template together with base.html into a separate template set — calling ExecuteTemplate on the page name alone will produce empty output". Nothing found → `none found`, never an empty section.

Both go into design.md, under `## Integration Points` and `## Implementation Gotchas` ([design-guide.md](design-guide.md#design-document-template)).

**Gotcha propagation rule:** The gotchas in design.md MUST be carried into the relevant task ToDo fields as concrete implementation notes — not as vague references to patterns. Example: instead of "use base layout pattern", write "parse each page template together with base.html into a separate template set — calling ExecuteTemplate on the page name alone will produce empty output". The gotcha must survive from research → design → task without losing specificity.

## Test Advisor Sub-agent (Standard + Full, during Phase 3)

**Only at engineering level `project` or `product`** ([engineering-level.md](engineering-level.md)). An `experiment` or `tool` story, whatever its scale, takes the Lite checklist below and writes its tests at run time — no Test Advisor is spawned, and no `.draft/authored-tests/` or `red-evidence.yaml` exists for it. Authoring every test before any code costs more wall clock than an `experiment` or `tool` story is worth.

After the main agent generates the task list structure (with Objective, ToDo, Validation, Requirements — but **without Tests fields**), spawn the **Test Advisor** sub-agent (`subagent_type: test-advisor`, defined in `agents/test-advisor.md`) — `run_in_background: false`, result awaited: Phase 3 cannot complete without its Red evidence, and a turn ended to wait for it is a turn the requester spends waiting ([personas.md](personas.md#personas)) — to define testing requirements per sub-task **and author one test file per Integration/E2E sub-task — and per Unit sub-task in a Full story** (Unit/Integration are Red-verified in Phase 3; E2E defers Red to Run mode). In a Standard story a Unit sub-task gets its Tests field only: the Executor writes that test first at run time and confirms its Red inline:

> "Analyze these tasks, define which sub-tasks need tests, and author the test files. Follow your agent definition — the determination, the authoring rules, the Red record and the report format live there.
>
> Story requirements: [path to story.md]
> Story scale: [Standard | Full]
> Design testing strategy: [testing strategy section from design.md, if exists]
> Design contract excerpts: [Full mode only — signatures/data shapes from design.md, per Unit/Integration sub-task]
> E2E tool: [the `E2E tool:` line of design.md's `## Tooling Decisions` — e.g. `playwright`, or `none`]
> Task list: [generated tasks WITHOUT Tests fields, and WITHOUT ToDo fields for authoring]
> Story directory: [.epico/stories/NNN-name]
> Project language/framework and test conventions: [detected from codebase analysis]"

The main agent merges the Test Advisor mapping into the task list before writing tasks.md to disk. The Test Advisor writes **only** inside the story's `.draft/` directory — the authored test files under `.draft/authored-tests/` and the Red evidence in `.draft/red-evidence.yaml` — and modifies no other project file. Every Unit/Integration test it authors must be confirmed Red before Phase 3 completes; an authored Unit/Integration test that passes blocks Phase 3 until revised (up to 2 attempts) or escalated to the user. An authored E2E test is not run in Phase 3 — its Red verification is deferred to Run mode and recorded as a `red_deferred: true` entry.

### Test Advisor Lite (Fast mode)

For Fast mode — and for a Standard or Full story at engineering level `experiment` or `tool` ([engineering-level.md](engineering-level.md)) — the main agent decides Tests inline (no sub-agent) using this 4-check checklist:

1. **State change?** Does this sub-task create/update/delete data?
   → YES: add at least 1 test that verifies resulting state (not just return code)
   → NO: skip

2. **Boundary?** Does this sub-task handle external input (HTTP, CLI, file)?
   → YES: add 1 happy path + 1 error path test
   → NO: skip

3. **Existing tests?** Does the modified code already have test coverage?
   → YES: verify existing tests still pass (add to Validation)
   → NO: apply rules 1-2 above

4. **Contract rule.** Every implementing sub-task carries either a `Tests` field or an `Acceptance` field — a sub-task with testable logic gets a `Tests` field, a structural sub-task with no testable logic gets an `Acceptance` field. A group-level `Commit:` field is exempt (it implements nothing).
   → checks 1-3 say a test is needed: add the `Tests` field
   → checks 1-3 say no test is needed: add an `Acceptance` field (1-3 observable-behavior statements)

Keep it lightweight — 1-2 test entries max per sub-task.

**For a Standard or Full story at `experiment` or `tool` level**, check 4 does not apply: a structural sub-task carries `Tests: None` with a one-line reason, as the Advisor would write, and anchors on its `Requirements` field; at `experiment` the `Tests` field is optional, as in a spike, and `Validation` is the proof.

**Plan time vs run time.** Unlike the full Phase 3, Fast — and an `experiment` or `tool` story at any scale — does **not** author tests at plan time — there is no Test Advisor sub-agent, no `.draft/authored-tests/`, and no `red-evidence.yaml`. This checklist only decides *whether* a test is needed and records that decision as the `Tests` or `Acceptance` field. The test-first ordering itself — authoring the test, confirming Red, then implementing — happens at run time (see `run-mode.md`).

## Reviewer Sub-agent (Full mode only)

After **all phases are written**, spawn the **Reviewer** sub-agent (`subagent_type: reviewer`, `run_in_background: false`, result awaited, defined in `agents/reviewer.md`) for cross-artifact validation:

> "Review these story artifacts as a set. Follow your agent definition.
>
> Files to read:
> - [path to story.md]
> - [path to design.md]
> - [path to tasks.md]"

The nine cross-artifact checks and the output format live in [reviewer.md](../agents/reviewer.md).

- If the Reviewer finds issues, present them to the user and offer to fix
- If clean, proceed to Traceability Check
- Reviewer does NOT modify files — only reports

## Handing Off to Run

**When a Standard or Full story is written and carries `run-model:`, the closing ends with how to run it on that model** — because the choice only takes effect in a session running it. Two ways, both named with the story's number:

- in this session: type `/model <run-model>`, then `/epico:epico stories run NNN` — `/model <name>` also makes it the default for new sessions; for this session only, open `/model`, pick it and press `s`
- in a new one: `claude --model <run-model>`, then `/epico:epico stories run NNN` — applies to that session alone, and is the cheaper of the two: it starts with an empty context, and the story's files already carry everything the run needs

Neither is run on the user's behalf: a plugin cannot switch the session's model, so the closing gives the commands and stops. **A `layperson` gets no command** — no `/model`, no `/epico:epico stories run NNN`: their story carries no `run-model:` ([clarify.md](clarify.md#the-run-model-standard-and-full)), and the closing's one-line gate offers to build it now, in this session. A command to type is a step a beginner may not know how to take.

## Traceability Check

After the final phase approval (standard and full scales only), generate a traceability table. **Build it from `cross-reference.sh`, never by hand-counting** — manual tallying is error-prone at scale. Run:

```bash
epico-xref .epico/stories/NNN-name
```

The JSON output carries everything the table needs: `mapping` is the requirement → sub-tasks relation, `orphan_requirements` lists requirements no task declares, `phantom_references` lists task references with no requirement. Render the table directly from those fields — task numbers come straight from `mapping`:

```markdown
| Requirement | Tasks | Status |
|---|---|---|
| R1.1 | 1.1 | Covered |
| R2.3 | — | No task |
| — | 5.1 | No requirement |
```

Rules:
- Built from the `cross-reference.sh` `mapping` field — never hand-counted
- Orphan requirements (`orphan_requirements`; empty `mapping` array) → warning shown to user
- Phantom references (`phantom_references`) → warning shown to user
- Warnings are informational — user decides whether to address them
- For bugfix stories, verify Unchanged Behavior items have regression test tasks
- If `status` is `clean`, show the table briefly and proceed to write
- Skipped for Fast mode (no requirements to trace)

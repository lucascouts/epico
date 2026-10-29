---
name: epico
description: >
  Structured story creation, management, and execution for features and
  bugfixes — requirements, design, task breakdown, and implementation
  with scale-adaptive intelligence. Trigger for "let's plan this before
  coding", "break this into tasks", or any request to formalize
  development work. Use when asked to: create, refine, or expand a
  story; list or manage existing stories; run/execute tasks from a
  story; validate implementation against plan. It also routes the
  management modes: init, instant for disposable work that nobody will
  maintain, migrate a story to the current format,
  create --batch to draft many stories from one document, archive,
  supersede, from-memory to draft a story from a memory proposal, and
  sync-docs to turn findings into a doc diff, checkpoint to close a ROADMAP stage. Also trigger when the user says "create an epic
  for X", "document this feature", "structure this sprint", "what
  needs to be done to implement X?", "list stories", "run story",
  "execute tasks", "validate implementation" — even without saying
  "epic" or "story" explicitly.
argument-hint: "[description] or [instant <description>] or [stories migrate NNN] or [stories create --batch <doc>] or [stories] or [stories full] or [stories run|validate|refine NNN] or [stories supersede NNN --by MMM] or [stories NNN run N|all] or [init]"
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Bash
  - TaskCreate
  - TaskGet
  - TaskList
  - TaskUpdate
  - TodoWrite
  - Agent
  - AskUserQuestion
  - mcp__ai-memory__memory_status
  - mcp__ai-memory__memory_recent
  - mcp__ai-memory__memory_query
  - mcp__ai-memory__memory_write_page
---

# Epico

Scale-adaptive story framework for features and bugfixes. Invoked as `/epico:epico`. Links to `../../references/` mean `${CLAUDE_PLUGIN_ROOT}/references/`.

## Scope

Epico exists solely to **create, structure, and manage epics and their stories** (`story.md` + `design.md` + `tasks.md`). Before running any mode, check that the request fits this purpose.

Decline these requests with one line and the suggested alternative:

| Request pattern | Refuse because | Tell the user |
|---|---|---|
| "Review this code / PR / branch" | No story artifact to anchor to | Use `/review`, `/security-review`, or `/code-review` |
| "Security review of …" | Same | `/security-review` |
| "Refactor X" (no existing story) | Skips design-fidelity contract | Create a Fast/Standard story first, then `run` it |
| "Analyze / explain this codebase" | Epico artifacts are the only valid analysis container here | Plain chat, or `/review` for a change |
| "Write this script / change this file" (no approved sub-task) | Implementation only happens inside Executor for an approved sub-task | Create a story (often Fast) then run its tasks |
| "Debug this incident / failing test" | Debug flow is out-of-scope | Plain chat |
| "Architecture advice for existing code" | No design.md to validate against | Plain chat, or `/code-review` for a change |

Do not start the out-of-scope work, and offer an Epico-wrapped version only when the user rephrases it as story or task work. See [`../../PURPOSE.md`](../../PURPOSE.md) for the full boundary.

## Language

**Everything the Epico writes under `.epico/` is written in English — stories, design, tasks, backlog, reports and every other document.** This is not an option and no setting changes it: these files are read later by sub-agents, and Claude models perform best on English technical content.

- **Spec artifacts** (story.md, design.md, tasks.md): always English
- **EARS keywords**: always English and CAPS (SHALL, WHEN, WHILE, IF, WHERE)
- **Communication with the user**: always in the user's language — the `language` setting when the user has set one, otherwise the language of their prompt — **every line they can see, including a note between two tool calls and the closing message**.
- **No whole passage in another language in the chat** — names and popular terms are fine, legended for a `layperson` ([plain-register.md](../../references/plain-register.md)); an English status line, sentence or option label in a Portuguese chat is not, the recommended marker included (`(Recomendado)`).
- **Code identifiers and comments the Epico writes**: English. A comment in the user's language only when they ask, on the line below the English one.
- **What the requester's own users read**: the program's interface — menu, prompts, error messages — and the documentation of how to use it (its README). **This is the one thing the English rule does not cover**, and it is not the Epico's to decide: it belongs to whoever will read it.

**The interface language is asked, not assumed.** A request written in a language other than English carries no instruction about the program's own text, and the English rule above is about artifacts. So:

- **Asked once, in the requester's own language**, as an ordinary clarify question: English · the language you wrote to me in · another one. It is a `what` question, not a `how` — the requester is the one who reads the result.
- **Not asked when the request is already in English** — the answer is not in doubt, and a question whose answer is known is a defect in either register ([Clarify Protocol](#clarify-protocol)).
- **When no round will run** — the lean route, or a budget already spent — the default is **the language the request was written in**, taken and stated on its line, never the artifacts' English inherited by mistake.

## Validation

Validation runs automatically via a PostToolUse hook when a story artifact under `.epico/stories/` is written with the Write tool; its errors come back to you as hook context. Manual validation is also available:

```bash
epico-validate <story-directory>
```

For cross-reference checks (requirements traceability):

```bash
epico-xref <story-directory>
```

Its JSON `mapping` field gives the requirement → sub-tasks relation directly — the Traceability Check builds its table from it, never by hand-counting.

- Output is JSON with `errors`, `warnings`, and `status` (pass/fail)
- Errors must be fixed before considering the story complete
- Warnings are informational — present them to the user

## Gotchas

- EARS: use `SHALL`, never `SHOULD` — one condition per requirement, each independently testable
- Requirements: number hierarchically (R1, R1.1, R1.2, R2...)
- Bugfix: Unchanged Behavior section is **mandatory**, minimum 2 items
- Fast mode is test-first at run time: a sub-task with a `Tests` field is authored Red, then Green-then-Refactor; a sub-task with no testable logic carries an `Acceptance` field (1-3 observable-behavior statements) instead — every implementing (non-Commit) sub-task carries one or the other
- **A run that finishes a story ends with an `AskUserQuestion`** when callable: one step (refine, run the rest or validate) plus *Stop here*; archive only after a passing validate. `--auto` takes the recommended step and logs it. See [End of Run](../../references/run-mode.md#end-of-run--next-step-index)
- Fast → Standard upgrade: recommend it at triage or task generation when scope grows, **or** when the change needs requirement traceability or design documentation — Fast has neither
- Constitution constraints are soft — warnings, not blocks
- A `layperson` build turn writes no text between tool calls — no status line in any language; notes go to `run-report.md`, the chat gets the closing message, checked with `epico-jargon` first
## Prerequisites

- `bash`, `git`, and `jq` available on `PATH`
- Claude Code **v2.1.295 or newer** — one floor for every feature.
- Optional MCP servers for research. See [mcp-integration.md](../../references/mcp-integration.md) for the full priority order and cost policy. Default search MCP is `brave-search`; `perplexity` is **never** the default (premium/high-cost).

## Before triage

**Before Standard or Full triage, run the constitution gate and the precheck in [triage.md](../../references/triage.md#constitution-gate).**

**Headless — `AskUserQuestion` is not callable:** take every gate and question inside the mode with its recommended option, record each as an assumption, and finish the mode; stop only on a failure. The step after the mode is never started: print its command.

## Project State

### Existing stories
!`ls -1d "${CLAUDE_PROJECT_DIR:-.}"/.epico/stories/*/ 2>/dev/null | sed 's|.*/\(.*\)/|\1|' | head -20 | grep . || echo "(none)"`

### Constitution
!`f="${CLAUDE_PROJECT_DIR:-.}/.epico/constitution.md"; if [ -f "$f" ]; then head -30 "$f"; else echo "(none)"; fi`

### Git state
!`cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null; if ! git rev-parse --git-dir >/dev/null 2>&1; then echo "(not a git repo)"; elif ! git rev-parse -q --verify HEAD >/dev/null; then echo "(no commits yet)"; else git rev-parse --short HEAD; git diff --stat HEAD | tail -1; fi`

## Plugin options

Substituted when this skill loads; a value still reading `${user_config.…}` was never saved — use the default in brackets.

- `aiMemory`: `${user_config.aiMemory}` [`auto`] — `off` skips every ai-memory call (mcp-integration.md, Memory MCP)
- `defaultScale`: `${user_config.defaultScale}` [`standard`] — the scale proposed when triage cannot settle one
- `executorModel`: `${user_config.executorModel}` [`inherit`], `reviewModel`: `${user_config.reviewModel}` [`inherit`] (run-mode.md)
- `staleThresholdDays`: `${user_config.staleThresholdDays}` [`7`] — the story list flags pending work untouched this long
- `spikeStaleThresholdDays`: `${user_config.spikeStaleThresholdDays}` [`14`] — the story list flags an open spike Verdict untouched this long

## Concepts

| Term | Meaning |
|---|---|
| **Epico** | This plugin / the `/epico:epico` command |
| **Story** | A unit of work: feature, bugfix, or initiative |
| **Task** | An implementation action inside tasks.md |

## Personas

**Before spawning any sub-agent, read [personas.md](../../references/personas.md)** — who each one is, when it is spawned, the MCP and tooling hand-off.

## Command Routing

When invoked via `/epico:epico`, parse `$ARGUMENTS` using this cascading routing table:

```
$ARGUMENTS parsing:

(empty) or (free text not starting with "stories", "init", "archive", "sync-docs" or "checkpoint")
  → CREATE mode

"init"
  → INIT mode (project configuration wizard)

"instant <description>"
  → LEAN ROUTE: `experiment`, no story.

"stories migrate NNN [--apply]"
  → MIGRATE mode (legacy story → canonical shapes; writes only with --apply)

"stories create --batch <doc>"
  → BATCH-CREATE mode (N stories from one document)
    Matched BEFORE the bare "stories" arm, or LIST would claim it.

"stories from-memory [<page>]"
  → FROM-MEMORY mode (a story drafted from a `proposal` memory page)

"sync-docs"
  → SYNC-DOCS mode (finding/decision pages → a doc diff, written only on yes)

"checkpoint <N>"
  → CHECKPOINT mode (close ROADMAP stage N)

"stories"
  → LIST mode (summary)

"stories full"
  → LIST mode (detailed, all stories with tasks)

"stories NNN"
  → LIST mode (detailed, single story NNN)

"stories run NNN [--auto|--batch=N|--gate=commit|--serial]"
  → RUN mode (all pending tasks of story NNN)

"stories validate NNN"
  → VALIDATE mode (one Auditor: validation, then audit)

"stories refine NNN"
  → REFINE mode (delta workflow on story NNN)

"stories archive NNN[-MMM]|--done"
  → ARCHIVE mode (epico-archive, one call per story; ranges expanded here)

"stories supersede NNN --by MMM"
  → SUPERSEDE mode (replace story NNN with MMM)

"stories NNN run all [--auto|--batch=N|--gate=commit|--serial]"
  → RUN mode (all pending tasks of story NNN)

"stories NNN run N"
  → RUN mode (specific task N of story NNN)

"stories NNN run N.N"
  → RUN mode (specific sub-task N.N of story NNN)

"archive"
  → ARCHIVE LIST mode (show archived stories)
```

**NNN** = story number (001, 002...) — matches directory prefix in `.epico/stories/`.
**N** = task number, **N.N** = sub-task number.

### Story Resolution

When a command references `NNN`:
1. Glob `.epico/stories/NNN-*/` to find the matching directory
2. If not found: "Story NNN not found. Available stories:" + list
3. If multiple matches (shouldn't happen with zero-padded numbers): show options

## Mode Dispatch

| Mode | Trigger | Reference to load |
|---|---|---|
| **Create** | `/epico:epico` or `/epico:epico <description>` | Read [triage.md](../../references/triage.md), then [clarify.md](../../references/clarify.md) when a round runs, then [phase-execution.md](../../references/phase-execution.md) for Standard/Full |
| **Lean** | Create, triage reads `experiment` | Read [lean-route.md](../../references/lean-route.md) — no story |
| **Instant** | `/epico:epico instant <description>` | Read [instant-mode.md](../../references/instant-mode.md) — it hands off to Lean |
| **Migrate** | `/epico:epico stories migrate NNN [--apply]` | Run `epico-migrate`; it writes only with `--apply` |
| **Batch Create** | `/epico:epico stories create --batch <doc>` | Load [batch-create.md](../../references/batch-create.md) — one interview, N stories; numbers come from `epico-next-number` |
| **Init** | `/epico:epico init` | Load [init-mode.md](../../references/init-mode.md) |
| **List** | `/epico:epico stories [full] [NNN]` | Load [list-mode.md](../../references/list-mode.md) |
| **Run** | `/epico:epico stories run NNN` or `NNN run N\|all` | Load [run-mode.md](../../references/run-mode.md) |
| **Validate** | `/epico:epico stories validate NNN` | Load [validate-mode.md](../../references/validate-mode.md) |
| **Refine** | `/epico:epico stories refine NNN` | Load [refine-mode.md](../../references/refine-mode.md) |
| **Archive** | `/epico:epico stories archive NNN[-MMM]\|--done` | Load [list-mode.md](../../references/list-mode.md) (Archive Command) — one `epico-archive` call per story, never a manual move |
| **From memory · Sync docs** | `/epico:epico stories from-memory [<page>]` · `/epico:epico sync-docs` | Load [memory-modes.md](../../references/memory-modes.md) |
| **Checkpoint** | `/epico:epico checkpoint <N>` | Load [checkpoint-mode.md](../../references/checkpoint-mode.md) |
| **Supersede** | `/epico:epico stories supersede NNN --by MMM` | Load [supersede-mode.md](../../references/supersede-mode.md) |
| **Expand** | User says "based on", "extends" existing story | Create new story referencing source |
| **CI/Headless** | Programmatic invocation via Agent SDK | Load [ci-mode.md](../../references/ci-mode.md) |

**Every mode loads its reference first.** Any mode that writes a story artifact also reads [output-rules.md](../../references/output-rules.md). Other references are loaded from these: [constitution.md](../../references/constitution.md) (the project constitution's format), [mcp-integration.md](../../references/mcp-integration.md) (research and memory servers).

## Instant — the disposable-work shortcut

`/epico:epico instant <description>`: **read [instant-mode.md](../../references/instant-mode.md) first** — it sets `experiment` and hands off to the [lean route](../../references/lean-route.md).

## Story Types

| Type | Artifacts | Detection signals |
|---|---|---|
| **Feature** | `story.md` + `design.md` + `tasks.md` | New functionality, sprint work, updates, pages, infrastructure |
| **Bugfix** | `story.md` + `design.md` + `tasks.md` | "fix", "bug", "correct", "broken", error descriptions |

## Triage Protocol

**Create: read [triage.md](../../references/triage.md) now, before anything is written** — the runtime precheck, the three scales, the workflow variants and the triage protocol with its proposal line. An `experiment` reading hands off to [lean-route.md](../../references/lean-route.md).

**Then load the requester's register, before the plan is written** — triage reads `requester.level`, and the register is where that level's defaults live: [plain-register.md](../../references/plain-register.md) for a `layperson`, [developer-register.md](../../references/developer-register.md) for a `developer`. Read the whole file; it is short. A layperson's defaults are not optional: tests are written and run in every scale, git is never a question, and nothing technical is asked — skipping the register is how a beginner's program ships with no test.

## Clarify Protocol

**When a question round runs, read [clarify.md](../../references/clarify.md) first** — Standard and Full always, Fast when the request is ambiguous. The lean route never loads it.

## Phase Execution

**Standard and Full: read [phase-execution.md](../../references/phase-execution.md) before writing the first phase** — completeness checklist, phase order, draft saving and resume.

## Output Rules

**Before creating or refining any story artifact, read [output-rules.md](../../references/output-rules.md)** — path, numbering, the shared frontmatter and the version history.


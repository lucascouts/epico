# Triage — Create and Instant

Loaded by Create and by Instant before anything is written. Instant reads it with its three pins already set. It lives outside [SKILL.md](../skills/epico/SKILL.md) so a run that does not need it does not carry it.

## Contents

- [Constitution gate](#constitution-gate)
- [Runtime dependency precheck (MANDATORY before Standard/Full triage)](#runtime-dependency-precheck-mandatory-before-standardfull-triage)
- [Adaptive Modes](#adaptive-modes)
- [Workflow Variants (Full mode, feature only)](#workflow-variants-full-mode-feature-only)
- [Triage Protocol](#triage-protocol)

## Constitution gate

**Standard and Full need `.epico/constitution.md`** — its `## Defaults` answer the questions the requester is never asked, and its `## Quality` and `## Security floor` are the story's starting legend. Without it, both scales would ask what the project already decided, or decide it differently each run. So, before the precheck below:

- **Missing, or without `## Defaults` and `## Quality`:** do not triage at Standard or Full. Interactively, say so in one line and offer `/epico:epico init --repair` now — one question, the run continues after it. **Headless:** run `init --repair` with every default, record it as an assumption, and continue.
- **Fast and spike** are untouched: they read the constitution when it exists and carry on without it.

## Runtime dependency precheck (MANDATORY before Standard/Full triage)

Standard and Full modes ask questions, so they need to know whether anyone can answer. The skill MUST settle that **before** entering the Triage Protocol and MUST tell the user when questions will fall back to prose — do not degrade silently.

| Tool | Required by | Fallback if missing |
|---|---|---|
| `AskUserQuestion` | Clarify Protocol (multi-choice rounds); the signal that someone can answer | Numbered-list confirmation prose; the run is treated as headless |
| Task tools (`TaskCreate` / `TaskList` / `TaskUpdate`, or `TodoWrite`) | Optional progress display during Clarify / Run | None needed — `tasks.md` is the progress record |

### Procedure

1. **Detect session kind — one signal, used everywhere:** `AskUserQuestion` is callable (listed among the tools, directly or as a deferred tool) → **interactive**: someone can answer. Otherwise → **headless** (`-p`, Agent SDK, or a run with no permission host). An explicit `--auto` or CI route counts as headless whatever the tools say. The Task tools are **not** a signal: Claude Code offers them only on some models, in interactive and headless sessions alike.

**A headless run answers its own gates.** When nobody can answer, the triage gate, every clarify round and every phase gate is taken with its recommended option — or the documented default where there is none — and the run continues to the end of the mode. Each answer taken this way is recorded where the artifact records assumptions (a story Constraint, or `.draft/meta.yaml`), and the closing message lists them. A headless run stops only where an interactive run would stop on a failure: a validation error, a failing test, a refusal.

2. **Task tools are optional.** When present, mirror the run in them; when absent, do nothing and report nothing — progress lives in `tasks.md`. A user who wants the checklist can start Claude Code with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`.

3. **Notify the user** before starting Triage, using this exact format:

   ```
   Runtime dependency check:
   - AskUserQuestion: [available | NOT LOADED — Clarify will use numbered-list fallback and the run is treated as headless]
   ```

4. **For Fast mode:** skip this precheck entirely. Fast mode does not use Clarify rounds or multi-phase task tracking.

5. Never omit the notification when `AskUserQuestion` is missing. Silent degradation is a bug — the user must know that UX is reduced so they can abort and restart in a richer environment if desired.

## Adaptive Modes

| Mode | When | Phases | Artifacts |
|---|---|---|---|
| **Fast** | Small and low-risk: a single concern, nothing worth tracing back to a requirement — typically 1-2 files | Tasks only | `tasks.md` |
| **Standard** | A clear scope worth traceable requirements, with no architectural signal — typically 3-10 files | Story + Tasks | `story.md` + `tasks.md` |
| **Full** | An architectural signal (below): a decision to record before the code exists | Story + Design + Tasks | `story.md` + `design.md` + `tasks.md` |
| **Spike** | The request's own goal is to find something out — "probe", "spike", "experiment", "harness", "find out whether" or its equivalent in the requester's language; the deliverable is a decision, not a shipped change | Tasks only | `tasks.md` (with a mandatory `## Verdict`) |

**The mode is read from risk and uncertainty, not from a file count.** The counts in the table are what each mode usually looks like, never the rule: a three-file change with a data migration is Full, a twelve-file rename is Standard. There is one scale — the four modes — and no complexity label in front of it.

Fast mode is **test-first at run time**: a sub-task carrying a `Tests` field has its test authored and confirmed failing (Red) before implementation, then Green-then-Refactor. A sub-task with no testable logic carries an optional Fast-only `Acceptance` field instead — 1-3 observable-behavior statements. Every implementing (non-Commit) Fast sub-task carries one or the other (the test-or-Acceptance contract rule). Fast stays single-author: no Test Advisor sub-agent, no `.draft/`, no `story.md`, no gate.

Spike mode is **exploration, not delivery**: the story exists to answer a question, and the answer is the mandatory `## Verdict` section of its `tasks.md`. A spike is tasks-only — no `story.md`, no `design.md`, no `.draft/` — and has **no requirements chain**: an R-reference such as `R1.1` inside a spike is a validation error, because no story.md exists for it to point at. It takes every Fast carve-out in this document (no runtime-dependency precheck, no MCP detection, no drafts, no phase gate) and stays single-author. What makes a spike terminal is the Verdict, not the checkboxes: `promote` (the orchestrator offers CREATE for the follow-up story, pre-filled with the conclusion, and records `promoted-to: NNN`) or `wont-do`. A Verdict left `open` is the failure mode this scale exists to prevent — LIST surfaces stale open spikes so they get promoted or closed. Template and grammar: [tasks.md](tasks.md#spike-scale-adaptations).

**The scale is one axis; the engineering level is the other.** The scale says which artifacts are written. The engineering level — `experiment`, `tool`, `project`, `product` — says how long the thing must last, and from that how much of the quality catalog, of Phase 3 and of the plan the story pays for. It is defined once in [engineering-level.md](engineering-level.md), read at triage (below), and it never changes the scale.

## Workflow Variants (Full mode, feature only)

| Variant | When to suggest | Phase order |
|---|---|---|
| **Requirements-First** | Business features, user-facing functionality | P1: story.md > P2: design.md > P3: tasks.md |
| **Design-First** | Infrastructure, tooling, technical constraints, NFRs | P1: design.md > P2: derived story.md > P3: tasks.md |

Bugfix always follows: P1: story.md (bug analysis) > P2: design.md (root cause) > P3: tasks.md

## Triage Protocol

Analyze the request (or `$ARGUMENTS` if invoked via `/epico:epico`) and present a **single proposal** for confirmation. Never ask each decision separately.

**Read who is asking first — from the request alone, never from a question.** The reading is recorded as a `requester` block with four fields, in the proposal and, where a `.draft/` exists, in `meta.yaml`; its `level` is also written to `tasks.md` as `requester: layperson | developer` at every scale, Fast included, because `tasks.md` is the one file every story has and the legend guard reads it ([tasks.md](tasks.md)):

```yaml
requester:
  level: layperson      # layperson | developer — developer when unsure
  persona: "beginner, informal, has never opened a terminal. Read from: describes an outcome and not a mechanism"
  always:               # seeded from the level's register, extended from the answers
    - explain by example, one per new concept
    - run and show the result; never ask them to run a command
  never:
    - ask about git, npm or versioning — the defaults decide
    - a word from the plain register's list in the chat
```

`level` is the switch the rules read. A **`developer`** names files, tools, patterns or a stack, and uses git / npm / test vocabulary. A **`layperson`** describes an outcome rather than a mechanism, self-describes as starting or learning, and shows no tool vocabulary — "the black window", "a program that stores things". When unsure, **`developer`**: a wrong `layperson` patronizes an expert, while a wrong `developer` costs one calibration question in Clarify. `persona` is one line and ends with the evidence the reading rests on, so a wrong reading can be challenged and re-read from the answers. `always` and `never` start as the level's register — [plain-register.md](plain-register.md) for a layperson, [developer-register.md](developer-register.md) for a developer — and grow from what the answers reveal about this person: "I don't know how to run a command" becomes a `never`.

**The level changes four things and nothing else — the register the chat is written in, the question budget, the defaults taken silently, and the shape of a gate — and it never changes the scale.** The scale follows the request and the mode table above, for every level. A layperson is never held at a lighter scale: what makes a heavier scale hard for a beginner — out-of-reach questions, document reviews, long turns — is handled by the register, the budget and the defaults, and a beginner who asks for something Full-shaped is owed Full, with its gates in one line. The files, the protocols and the sub-agents do not change.

**Read what it is for next — the engineering level — from the request, and propose it with its price.** Four levels, defined in [engineering-level.md](engineering-level.md): `experiment` (disposable, 1×), `tool` (kept and fixed when it breaks, 2–3×), `project` (maintained, others depend on it, 4–6×), `product` (may be published or sold, 8×+). Read it from the words the request carries — "for a class", "to see if it works", "my team", "customers" — record it in the proposal and, where a `.draft/` exists, in `meta.yaml` beside the `requester` block, and **ask when the request does not settle it** — round 0 of Clarify fishes for it, below. **Take `tool` only when nobody can answer** (`-p`, `--auto`, or a spent question budget) and say so on the proposal line: `experiment` and `product` are never assumed, since the first drops every check and the second buys every one. The proposal states the level in one line with its multiple, in the register's words, so the triage gate confirms it without spending a question; when triage was unsure, round 0 of Clarify fishes for it with the indirect questions that file lists — never "which level is this?" — and the line is restated once if the answer moves it. The level never changes the scale and never changes the requester level: the three are read and recorded independently.

1. Detect event from request context
2. Classify type (feature vs bugfix). **For a bugfix, split the report into four before anything else**: what was observed, what was expected, the reporter's diagnosis, and the fix they propose — the last two are hypotheses, recorded as given and never treated as findings ([bugfix.md](bugfix.md#template), *Report as Given*). A report that only names a cause ("the cache is stale") has no observation yet: ask for the symptom
3. **Assess overall story complexity** (see table below)
3a. **Read the engineering level** (above) — from the request; asked when unsettled, `tool` only when nobody can answer; proposed with its multiple in one line. **WHEN it reads `experiment`, stop here and follow [lean-route.md](lean-route.md)**: the steps below, the proposal and every story artifact are skipped — an `experiment` is done directly, with the security floor, and writes no story
4. **Recommend mode with trade-off explanation** — from the request and the table, for every level; the level never changes the mode (above). WHEN the request is too vague for the table and clarify leaves it unsettled, propose `defaultScale` (SKILL.md *Plugin options*)
5. Suggest workflow variant (full mode only)
6. Check for context files — load [context-discovery.md](context-discovery.md)
7. **Health-check candidate MCPs** — load [mcp-integration.md](mcp-integration.md)
7a. **Detect memory** — `ai-memory`, per the Memory MCP section of [mcp-integration.md](mcp-integration.md#memory-mcp). One local `memory_status` call, in **all modes including Fast**; skipped only when `aiMemory` is `off` (SKILL.md *Plugin options*). WHEN available, gather Prior Knowledge before the Analyst runs — [context-discovery.md](context-discovery.md#prior-knowledge). WHEN unavailable, say so in the proposal's `**Memory:**` line and change nothing else.
7b. **Detect preferred tooling** — load [preferred-tooling.md](preferred-tooling.md). Runs in **all modes, including Fast** (unlike step 7, which Fast skips). Detect every favorite and optional E2E tool plus the `frontend-design` aid, then resolve the selection:
   - WHEN a favorite is available, select it (`playwright` by default; `chrome-devtools` when the task is Chrome-specific). For a frontend story with `frontend-design` available, designate it the preferred implementation aid.
   - WHEN no favorite is available, recommend installing one and **pause** for the user's `[y/n]` decision. The pause reuses the Runtime dependency precheck's interactive/headless signal — `AskUserQuestion` available = interactive session, so pause; in a **headless** session do not pause, emit a logged note instead and proceed. WHEN the user proceeds without installing, select the best installed optional tool that fits the task context (per [preferred-tooling.md](preferred-tooling.md)).
   - WHEN no favorite and no fitting optional tool exist, record `none — no E2E tooling available` in design.md's `## Tooling Decisions` block AND as a story Constraint.

   The recommendation/pause happens at triage **only**. The resolved decision is written to design.md's `## Tooling Decisions` block and the relevant E2E/frontend sub-tasks are annotated in tasks.md — the Executor and Test Advisor consume that decision without re-detecting.
8. Allocate the story number with `epico-next-number` — the one tested allocator, used by single create and batch create alike
9. Propose output path in `NNN-kebab-case`
10. If no existing stories in `.epico/stories/`: append EARS primer

### Mode Recommendation

| Mode | What the user gives up | What it buys |
|---|---|---|
| **Fast** | formal traceability and design docs | the shortest path to a tested change |
| **Standard** | the design doc | traceable requirements and a task breakdown, with no design doc to write and keep current |
| **Full** | the most upfront time | the decision recorded before the code, which prevents scope drift and design mismatches |
| **Spike** | a shipped change | a time-boxed answer: no requirements chain, no design doc; a Verdict that promotes to a real story or closes the question |

**Full is opt-in on an architectural signal, not on file count.** A design doc earns its cost only when there is a decision to record *before* the code exists. Propose Full when the request carries at least one of:

- a **new contract between systems** — an API, an event, a schema that two components must agree on
- a **data migration**, or any change to the shape of something already persisted
- a **cross-cutting change with no established pattern** in the codebase to follow
- **2+ independent tracks** that have to be designed to fit together
- the user asking for Full explicitly

Absent every one of them, a story is **Standard** however many files it touches: file count measures typing, not design risk.

**Downgrading is as legitimate as upgrading.** Upgrading on a signal has a mirror. WHEN the clarify phase resolves the open questions and no architectural signal survives, **propose dropping to the lighter mode** — Full to Standard, or Standard to Fast — and name what the user gives up: Full to Standard loses the design doc, Standard to Fast loses the requirements chain and its traceability. The proposal is a one-line gate with two answers — drop, or keep the mode — and the mode changes only on the answer; announcing the drop and proceeding is the silent downgrade this rule forbids. A request for speed is answered with fewer words and no waiting, never with fewer steps ([developer-register.md](developer-register.md)). One downgrade is forbidden outright, and it is the subject of the next note.

**Exploratory is a shape, not a size.** Propose Spike only when the request's own goal is to find something out, or when the user asks for one explicitly. A small feature is **Fast**, never Spike — the skill **never auto-downgrades a feature to a spike**: doing so would trade a deliverable for a question the user never asked.

**The model is chosen where it is active: the session.** A plugin cannot switch the model a session runs on, and a skill's `model:` does not apply when the model itself invokes it — only when the user types the command. So Epico never tries to switch it: it **suggests**, before any work starts, continuing on the recommended model or starting a session already on it. For Fast and Spike, which create and run in this sitting, the suggestion is the proposal's `Model` line, shown only when the session is not on Sonnet, and the proposal's confirmation is where the user acts on it. Standard and Full ask at clarify which model runs the story and hand it off to a session on it ([clarify.md](clarify.md#the-run-model-standard-and-full)). Under `--auto` or headless nothing is suggested. The line names the model the session reports; when it cannot tell, the line is left out.

Always explain trade-offs in the triage proposal. Include EARS primer on first story only (see [ears-notation.md](ears-notation.md)):

> "This framework uses EARS notation for requirements:
> - SHALL = mandatory behavior
> - One condition per requirement, each independently testable
> - Example: WHEN user submits form THE SYSTEM SHALL validate and return confirmation
> - Reference: https://alistairmavin.com/ears/"

Present as:

> "Based on your request:
> - **Event:** Create / Refine / Expand
> - **Type:** Feature / Bugfix
> - **Requester:** level — persona (the evidence, in a few words)
> - **Engineering:** experiment / tool / project / product — what it means for this request, and the multiple, in one line
> - **Mode:** Fast / Standard / Full / Spike (the risk or signal that decided it + trade-offs)
> - **Model:** (Fast and Spike, only when this session is not on Sonnet) this session runs on `<model>`; Sonnet does this work at the same quality for about a third of the cost. Two ways: switch this session with `/model sonnet` — which also makes Sonnet the default for new sessions; for this session only, open `/model`, pick Sonnet and press `s` — or start a new session already on it with `claude --model sonnet`, which applies to that session alone
> - **Workflow:** Requirements-First / Design-First (full mode only)
> - **Context:** [files found and how they'll be used]
> - **MCPs:** [verified MCPs and any substitutions]
> - **Memory:** [ai-memory — N pages recalled | not detected]
> - **Tooling:** [detected E2E tools + `frontend-design`; resolved E2E/frontend selection; any favorite-absent install recommendation]
> - **Output:** `.epico/stories/NNN-<proposed-name>/`
>
> Confirm or adjust?"

For a `layperson`, the same decisions are presented in the [plain register](plain-register.md): three lines in their words, one question — go on, or change something. The table above is what gets recorded, not what they are shown.

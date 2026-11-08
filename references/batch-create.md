# Batch Create Mode

Triggered by `/epico:epico stories create --batch <doc>`. One interview, N stories.

## Contents

- [Procedure](#procedure)
- [1. Entry and the source document](#1-entry-and-the-source-document)
- [2. Derivation](#2-derivation)
- [3. One consolidated triage](#3-one-consolidated-triage)
- [4. Reservation — the allocator contract](#4-reservation--the-allocator-contract)
- [5. One interview](#5-one-interview)
- [6. Per-story pipeline, unabridged](#6-per-story-pipeline-unabridged)
- [7. One approval, per-story verdicts](#7-one-approval-per-story-verdicts)
- [8. Interruption and resume](#8-interruption-and-resume)
- [What batch does not change](#what-batch-does-not-change)

The interview is the expensive part of creating a story, and creating stories one at a time repeats it wholesale. This mode amortizes the **conversation**. It amortizes nothing else — every story still runs its scale's full pipeline, including Phase 3 with the Test Advisor at engineering level `project` or `product`, and every materialized story still has to pass validation clean.

`<doc>` is a path: an audit report, a proposal, an improvement plan. A batch with no document is out of scope — except a split's request: when a single create's one-goal check is answered **Split** ([atomic-stories.md](atomic-stories.md)), the request itself is the source, recorded verbatim, and the batch starts at its consolidated triage with one row per goal.

## Procedure

1. **Entry** — read the document; refuse early if it is unreadable or empty
2. **Shared context** — runtime precheck, MCP health-check and preferred-tooling detection, **once for the batch**
3. **Derivation** — propose N stories from the document
4. **One consolidated triage** — N rows, one "Confirm or adjust?"
5. **Reservation** — allocate and claim N numbers on confirmation
6. **One interview** — every clarification for every member, in one round-set
7. **Per-story pipeline** — each approved story runs its scale's normal phases
8. **One approval** — a verdict per story and a one-line tally
9. **Index refresh** — `scripts/epico-index.sh`

## 1. Entry and the source document

**An unreadable or empty document is refused before any number is reserved.** Name the path in the refusal. Nothing is created, nothing is claimed, and the user is not taken through an interview for a batch that was never going to exist.

The document is read once and stays the batch's single source: every story derived from it cross-links it in that story's `## Related Stories`, and when the document audits an existing story, that story is cross-linked too. A derived story that cannot say where it came from is a story nobody can re-derive.

## 2. Derivation

Read the document for **story-shaped items**: a stated problem with a stated remedy that a person could implement and check. Each proposal carries the same three fields a single create's triage produces — event, type and scale — from the triage table in [SKILL.md](../skills/epico/SKILL.md). A batch may mix scales freely; scale is decided per proposal, never per batch.

**Every proposal is atomic** by [atomic-stories.md](atomic-stories.md): one goal, no forward dependency — a row depends only on rows above it — and only what its own behaviour needs. Read the proposals together for file churn before the table: rows that keep editing the same core files are merged, unless the split buys risk isolation, an early feedback loop or a context that fits.

**Zero story-shaped items is a result, not a failure to try harder.** Report that the document yielded none and stop. A batch is never padded with invented stories: the cost of a fabricated story is paid later, by whoever tries to implement it.

## 3. One consolidated triage

One block, N rows, one confirmation:

| # | Proposed story | Type | Scale | Blocked by | Why this scale |
|---|---|---|---|---|---|
| 1 | `<slug>` | feature | full | — | new contract between services — the architectural signal Full asks for |
| 2 | `<slug>` | bugfix | fast | 1 | — |

**When the source is a ROADMAP or stage file with numbered tasks**, the table gains a `Roadmap` column naming the task IDs each proposed story works on (`2.4.1, 2.4.2`), and each story's `tasks.md` gets them as `roadmap: [2.4.1, 2.4.2]`, with the sections its tasks' `REF:` lines point at as `refs:` ([context-discovery.md](context-discovery.md#document-references)) ([clarify.md](clarify.md#the-roadmap-tasks-only-when-the-project-numbers-them)). Several tasks may form one story, and one large task may be split across stories; every numbered task of the source appears in at least one row or is named below the table as left out, with the reason.

**A row is `standard` unless it names an architectural signal.** Scale per row follows the same rule a single create follows ([triage.md](triage.md#mode-recommendation)): Full is opt-in on a signal, never on file count. Row 1 above earns its `full` in the last column — a row that cannot fill that column is a `standard`.

Below the rows, the batch-wide context gathered once in step 2 — the runtime dependency check, the MCP health-check results and the resolved preferred tooling — then a single "Confirm or adjust?".

**Detection runs once per batch, not once per story.** The precheck, the MCP health-check and the tooling detection describe the environment, and the environment does not change between rows.

## 4. Reservation — the allocator contract

On confirmation, and not before, numbers are claimed by [`scripts/next-story-number.sh`](../scripts/next-story-number.sh) — the one tested allocator, used by single create too, so both flows agree by construction instead of by two prose descriptions that drift.

```bash
epico-next-number --reserve N
```

It emits exactly one JSON object with three keys, and all three are the contract:

| Key | Meaning |
|---|---|
| `next` | the next free number after everything now claimed, zero-padded |
| `reserved` | the numbers this call claimed, zero-padded, ascending — one placeholder directory `NNN-reserved/` exists per entry |
| `collisions` | one entry per number that was contested, naming what claimed it and where this call went instead; empty when the run was uncontested |

**Directory existence is the reservation.** The allocator scans `.epico/stories/` **and** `.epico/archive/` — numbers are never recycled, so an archived story still owns its number — and the placeholders it creates are what make the numbers unavailable to the next scan. Rename each placeholder to its real `NNN-slug/` in the same confirmation step, so the window in which a directory says `reserved` is as short as the flow can make it.

**A collision is reported, never silently absorbed.** When the re-scan after creation finds another creator claimed one of the numbers, the allocator moves its own placeholder and records it. Surface the `collisions` entries in the confirmation output: the user asked for N stories at numbers they saw on screen, and two of them may now be somewhere else. A foreign directory is never removed, overwritten or renamed.

**At the 999 cap the allocator exits 1 and nothing is reserved.** Surface the existing maximum-story-count message — *"Maximum story count reached. Archive old stories with `/epico:epico stories archive` to free space."* — and stop **before** the interview. An interview whose output has nowhere to land is the one thing more wasteful than the repetition this mode exists to remove.

## 5. One interview

Every clarification for every Standard/Full member goes into **one round-set**.

- Each question is tagged `[story N/M — slug]`, so an answer is never ambiguous about which story it settles
- 1–4 questions per `AskUserQuestion` call (2–4 options each), as many calls as the round needs
- **At most 3 rounds for the entire batch** — the existing per-story cap, applied globally. It is a cap on the conversation, not on the stories
- Ambiguity still standing after round 3 becomes a **documented assumption** in the story it belongs to, exactly as in single create

**Fast members keep their clarify skip.** A Fast story that is unambiguous asks nothing, in a batch as anywhere else.

**Headless does not pause.** Present the assertion-style numbered list for the whole batch (`"I understand X will work as Y"`), log the assumptions, and proceed. A headless batch that blocks on a question nobody can answer is a batch that never finishes.

## 6. Per-story pipeline, unabridged

Each approved story runs the phases its scale prescribes. Batch collapses the conversation around the pipeline; it does not shorten the pipeline.

**Phase 3 runs the Test Advisor for every Standard/Full member at engineering level `project` or `product`** ([engineering-level.md](engineering-level.md)) — authored tests and `.draft/red-evidence.yaml` — before materialization; an `experiment` or `tool` member writes its tests at run time and has nothing to materialize. This is not a quality preference: Run mode's materialization guard refuses a story that arrives without it, so a batch that skipped Phase 3 would produce stories that cannot be run. Advisors for independent stories are parallel-safe and may run concurrently.

**Materialization requires a clean `validate-story.sh` pass** for that story. A story that does not validate is not materialized; it is reported `blocked` in the approval block with the validator's own error text.

**The authoring size ceiling fires per generated story, and its split offer is deferred.** The threshold has one home — [tasks.md](tasks.md) (Authoring Ceiling) — and is cited, never restated. When a generated `tasks.md` trips the ceiling, the warning surfaces in the approval block — the live interview is never re-entered for it. A split, if the user wants one, happens after the batch as an ordinary create. Re-opening the interview to renegotiate one story's shape would undo the amortization the whole mode is for.

## 7. One approval, per-story verdicts

The batch ends with **one** decision moment carrying **one verdict per story**:

| Verdict | Meaning |
|---|---|
| `created` | materialized, validated clean, `status: draft` written |
| `skipped` | not materialized by choice — the reserved directory persists as a draft seed |
| `blocked` | could not be materialized — validation failed, or a dependency was missing; the reason is stated |

**A batch never stops on one story.** Each story gets its verdict and the batch continues to the next. Close with a one-line tally — `created N, skipped M, blocked K` — so a partial batch reads as a partial batch. This is the same grammar the archive sweep uses; it is defined once, in [list-mode.md](list-mode.md#resolving-the-argument), and cited here rather than restated.

**A skipped proposal keeps its number as a draft seed.** Its reserved directory persists carrying `.draft/meta.yaml` with `phase: 0`, the proposal as triaged, and the `source-doc:` path it derived from. The number is not returned to the pool — releasing it would recycle a number, which this framework does not do — and the seed is recoverable later by resume detection.

**A materialized story gets `status: draft` frontmatter**, and the index is refreshed once at the end of the batch with `epico-index`.

## 8. Interruption and resume

An interrupted batch leaves **N ordinary per-story drafts**. There is no batch-level state file to reconcile, because there is no batch-level state: each story is complete or it is a draft, exactly as in single create.

Resume therefore stays per-story. What batch adds is one aggregated line: when several drafts share the same persisted `source-doc:`, group them and say so — *"3 drafts share `docs/audit-2026-07.md` (phases 0, 3, 3). Resume the batch?"* — rather than offering three unrelated-looking resumes.

**Leftover `NNN-reserved/` directories are an interrupted reservation, not junk.** A crash between the reservation and the rename leaves them on disk. Recognize them as such, name the numbers they hold, and offer to continue the batch or release them explicitly — never delete a placeholder silently, because a placeholder is indistinguishable from another session's live claim.

## What batch does not change

- Not the artifact contract — the same `story.md` / `design.md` / `tasks.md` per scale
- Not Phase 3, not the Test Advisor, not red-evidence
- Not validation — every story passes `validate-story.sh` clean or is reported `blocked`
- Not the EARS grammar, the checkbox grammar, or the numbering rules

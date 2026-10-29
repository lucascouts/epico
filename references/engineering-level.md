# Engineering Level

How long the thing must last decides how much the story pays for — in the quality catalog, in Phase 3, in the size of the plan. The scale ([triage.md](triage.md#adaptive-modes)) says which artifacts are written; the engineering level says how much engineering the work carries. They are independent axes: a Fast story can be a product's one-line fix, a Full story can be an experiment with three tracks.

**`experiment` writes no story.** Triage hands it to the [lean route](lean-route.md) — done directly, the security floor kept, the whole check run before done; the Phase 3 and catalog rows below apply to a story, so they apply from `tool` up. A story's plan, gates and questions buy upkeep, and an `experiment` has none to buy.

This file is the single home of the four levels, their multiples and what each activates. Every consumer cites it and restates nothing but the numbers `tasks.md` owns; recalibrating a multiple is one edit here.

## The four levels

| Level | What it means | The question that reveals it | Expected cost |
|---|---|---|---|
| `experiment` | Kept or thrown away as you like, but **not maintained** — no changes, no updates, no upkeep planned. You may well go on using it exactly as it is | "Do you intend to add features to this once it works, or are you just going to try it out with no intention of keeping it up?" — try it out | **1×** — the minimum that works, plus the security floor |
| `tool` | A minimum viable version, with the basics of good practice and its quality gates. Kept in use and fixed when it breaks, with no deadline and nobody else depending on it | "Besides you, is anyone else going to use it?" — no | **2–3×** |
| `project` | Maintained: updated with some regularity, and other people depend on it or contribute to it | "Besides you, is anyone else going to use it?" — yes | **4–6×** |
| `product` | May become a product. Market standards from the first commit | "Do you intend to offer it as a product or a service?" — yes | **8×+** |

The multiple is against the **control** — the same request answered by the model with no plan at all — in wall clock and in tokens, and it is what the level should cost, not what it is allowed to. **Up to 5× the control is justifiable; above it, something is wrong or unnecessary.** `project` and `product` may exceed 5× because they buy things the control never produces — a history, a CI, contract tests — and their multiples are read from measurements, never taken as a licence.

## How the level is read

**Proposed at triage, from the request, and confirmed by the triage gate.** Triage reads the level the way it reads the requester ([triage.md](triage.md#triage-protocol)): from the words — "for a class", "to see if it works", "we ship this to customers", "my team" — and records it with the evidence. When the request does not settle it, the cascade below is asked rather than a level assumed. `tool` is not a safe default either: assumed for a throwaway request, it pays for checks nobody needed and overshoots what its own level promises. It is taken only when nobody can answer — `-p`, `--auto`, or a spent question budget — and stated on the proposal line. `experiment` and `product` are never assumed: the first drops every check, the second buys every one.

**The proposal line carries the price, in one line — and the scale rides with it.** Whatever the level, the proposal states it in words the requester chooses by, **and names the scale beside it**: the scale decides which artifacts get written, and it can move the bill further than the level does. A price the requester never sees is a price they cannot refuse.

> Engineering: tool — you will keep using this and fix it when it breaks, so I test each part as I build it. About 2–3× the time of a throwaway version. Say so if it is only for today, or if others will depend on it.

For a `layperson` the same line is one of the three lines of the plain-register proposal ([plain-register.md](plain-register.md)), and the level's name never reaches them — what they hear is how long it needs to last and what that costs. For a `developer` the term is used. Either way the triage gate confirms it, so the level costs no question of the budget.

**When triage is unsure, the level is fished for inside the orientation round — Round 0 of Clarify ([clarify.md](clarify.md#clarify-protocol)), which already asks who uses the thing and what "done" looks like. The level's questions join that round as a cascade, and the cascade stops at the first answer that settles it.** The questions are asked as consequences, never as "which level is this?": a requester cannot grade their own engineering, but they know whether they intend to come back and change the thing.

1. *Do you intend to add features and capabilities to this project once it is finished, or are you just going to try it out with no intention of keeping it up?* → **try it out = `experiment`, and nothing further is asked**
2. *Besides you, is anyone else going to use it?* → no = `tool` · yes = continue
3. *Do you intend to offer it as a product or a service?* → no = `project` · yes = `product`
4. **Conditional, and only when an answer above opened it** — how the others receive it (a public repository, a private one, a file sent directly), and free or paid. These are separate questions that complete each other; one round cannot settle them all.

**No option in a level question is ever marked recommended, in any register.** A recommendation answers *what is the better engineering* — but this question asks *what do you intend to do with the thing*, and there is no better answer to that than the requester's own. Marking one is a category error, not a nudge. **Every register asks it as its own question, unmarked, with the price in plain words — never folded into the plan gate with an option pre-marked `(Recommended)`; the `developer` register changes only the vocabulary** — never the shape, never the marking, never the position. A technical question in the same round may carry a recommendation, and should; this one may not.

**These are intent rounds, and intent rounds do not count against the question budget** ([clarify.md](clarify.md#clarify-protocol)). Technical rounds do. The cascade stops when a round changes neither the level nor the range of technology still open; where real ambiguity remains after that, ask for a free-text answer rather than offering a further set of options.

**The floor is `fast`, and it rises only when an answer pushes it — and it may come back down.** Going down is cheap; going up after the work has been paid for is not. When the answers move the level, the proposal line is restated once, with the new price, before Phase 1.

**A spike is an experiment by definition** and carries `experiment` or nothing.

## Where it is recorded

- **The frontmatter** of every artifact, beside `scale:` — `engineering: experiment | tool | project | product`. `tasks.md` is authoritative, as it is for the scale; a value outside the four is a validation error naming the set; absence is legal and silent.
- **`meta.yaml`**, beside the `requester` block, from the moment the level is proposed.
- **The run** — the execution plan and the end-of-run report both open with **the recorded line**: scale, requester level, engineering level with the multiple the level *expects*, and the plan size in Task List boxes — `standard · developer · tool (2–3×) · 11 boxes`; the report adds the wall clock and the boxes closed. That line is what lets a run be compared against its control; a run without it is a run nobody can measure ([run-mode.md](run-mode.md#run-mode-rules)).

  **The report never states the multiple this run achieved.** It cannot: the multiple is against a control — the same request answered with no plan at all — and nobody ran one. `(2–3×)` in the recorded line is the level's *promise*, never a measurement, and the report must not restate it as an outcome. An estimate stated as a result errs in the direction that flatters the run. Report the wall clock and the tokens, which are measured; leave the ratio to whoever holds a control.

## What each level pays for

The level ties three things together. Each row is the whole difference between levels; everything not named here is the same at every level.

| | `experiment` | `tool` | `project` | `product` |
|---|---|---|---|---|
| **Quality catalog** ([quality-catalog.md](quality-catalog.md)) | the **security floor** and nothing else — supported runtime, secrets, dependency CVEs, a README, data integrity ([quality-catalog.md](quality-catalog.md#the-security-floor--five-items-no-level-drops)); beyond those five the proof is that it runs | the **always** tier, **paid with defaults**: one command per item, its options on the command line, no configuration file for a checker ([quality-catalog.md](quality-catalog.md#always)) | always, plus every **context** item whose signal the tree or the request carries | always, every context item that applies, and the **CI-shaped** ones without waiting for a signal — hardened workflows, the CI mirror, minimum dependency age, licence and SBOM, security policy and branch protection — plus the **on-request** tier when a requirement names it |
| **Phase 3** ([phase-gates.md](phase-gates.md#test-advisor-sub-agent-standard--full-during-phase-3)) | tests optional, as in a spike: `Validation` is the proof | tests decided inline by the Lite checklist and **written at run time**, as Fast does — no Test Advisor, no `.draft/authored-tests/`, no `red-evidence.yaml` | the full Phase 3: the Test Advisor authors one failing test per Unit/Integration/E2E sub-task and records its Red | the same |

**Why Phase 3 is proportional.** Authoring the test at plan time buys an independent contract for the implementer, and that independence is worth its price when someone else will maintain the code; for a thing one person keeps for themselves, the test written at run time — Red before Green, the same cycle, no sub-agent — buys the same regression guard for a fraction of the clock. `experiment` and `tool` therefore land in the run-time test-first ordering that Fast and spike already use ([run-mode.md](run-mode.md#run-time-test-first-ordering)), whatever their scale; `project` and `product` pay the full Phase 3. Everything downstream that reads "Standard/Full" as "has a pre-authored test" reads it through this table: materialization, its converse guard, Refine's Red evidence for added sub-tasks and the Auditor's Red-precedence check all apply at `project` and `product` and are exempt below.

**Why there is no task-count ceiling.** **How many tasks a story has follows from the work, not from its level** — which is also how a work breakdown structure is built, bounding each package's size (the 8/80 heuristic) and never the count, and how agile story splitting works, which prescribes no number at all. A checkbox is not a unit of work: `.gitignore` and a whole module are each one. The level still decides the plan's *cost* — through what the quality catalog activates and through Phase 3 — and the plan keeps its one threshold on size in bytes ([tasks.md](tasks.md#authoring-ceiling)). The bound is on the unit: a sub-task is one Executor pass, with a `Validation:` command that proves it alone.

## What the level never changes

- The scale, the artifacts and the gates — a `product` Fast story is still `tasks.md` alone, an `experiment` Full story still has its design doc
- The requester level and the register — the two levels are read and recorded independently
- The Executor's six steps, the closing of a box, the commit — the level decides how much is planned, never how a planned box is done

## Runtime provisioning

**Only `project` and `product` provision a runtime** — install an interpreter, create a venv, build a container — and only as the constitution's `## Runtime` line says, with the user's yes for anything installed on the host. `experiment` and `tool` run on what the host already has: when the runtime the plan needs is missing or end-of-life, stop before the first sub-task and say exactly what to install and the command, rather than provisioning a whole environment for work nobody will maintain.


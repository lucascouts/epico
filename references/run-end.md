# End of Run — RUN

Loaded from [run-mode.md](run-mode.md#end-of-run--next-step-index) when a run reaches its closing message. It lives outside run-mode.md so that file stays under the project's 500-line limit.

## End of Run — next step, index

A run that ends without a failure finishes with these steps, in this order:

1. **Converge** — one pass over the request and the floor, [below](#converge); it adds work only on an executed reproduction
2. **Next-step question** — one `AskUserQuestion`, below. It is the step most easily lost: a story that ran and was never validated or refined is left for someone to remember. Asking in this session, while the run is still in context, is what keeps it from being forgotten
3. **Index refresh** — last, for the same reason it is last at the pass point: it renders what the steps before it changed. A zero-diff no-op when VALIDATE already refreshed it

A run that stops on a failure makes none of them: its FAIL path already asks how to proceed.

**Every closing names what was not verified — the loss annotation.** Success or failure, the closing message carries one `Not verified:` line: what this run did not check and why (no E2E tool, a sub-task closed `[~]`, a test that could not run here, a platform not exercised, a claim nobody re-ran). `Not verified: nothing — every validation, test and gate ran` is a valid line; an absent one is not. For a `layperson` requester it is one plain sentence after the closing lines, in their words — "I did not try it on a phone." A closing that reports only what passed reads as a claim that everything did.

### Converge

**One pass after the last box, before the question.** Closing every box proves the plan ran, not that the request and the floor hold: a run can pass every planned test and still write its data file without the atomic rename, because no box asked for it. So the pass re-reads three things against what was built: the request, the story's requirements where it has them, and **the floor** — the [security floor](quality-catalog.md#the-security-floor--five-items-no-level-drops), the runtime line, the README and the commit.

- **Each gap is reproduced before anything changes** — a command whose output shows it, recorded in `run-report.md`. **No reproduction, no change**: a gap that cannot be shown is a note in the `Not verified:` line, never a fix.
- **It adds, never re-plans.** A reproduced gap becomes one new sub-task appended to `tasks.md` under a `Converge` task group, run like any other box; a gap that changes the plan's intent is a deviation with `follow_up: true`, and the next step becomes Refine.
- **A web page is checked at the URL the server itself printed** — started on a free port or port 0 — with `curl`, before the run calls it working; a page answered by another program's server is a false pass.
- **It stops at the first pass that finds nothing**, and at most two passes run: a third is the open-ended loop the [fix loop bound](validate-mode.md#fix-loop-bound) exists to prevent.

### Measure the context window first

Validate and refine are whole modes — they re-read the story, spawn agents and write reports — so whether they fit in **this** session depends on how full its context window already is. Measure it, never estimate it:

```
epico-telemetry | jq '.context'
```

Read `band`. The script derives the window and the thresholds from the model the transcript records — never pass `--window` from a guess. When the call fails or `band` is `null`, the fill is **unknown**: offer every option as in the `high` band, and say the context was not measured.

| `band` | Haiku (200k) | Sonnet, Opus, Fable (1M) | The next step |
|---|---|---|---|
| `high` | ≤ 100k | ≤ 200k | offered in this session — **strongly recommended here** |
| `efficient` | ≤ 150k | ≤ 400k | offered in this session, its description stating the fill (`used_pct`) |
| `degraded` | above | above | **not run in this session** — offered as *New session*, which prints the command to type after `/clear`: `/epico:epico stories validate NNN` or `refine NNN`, whichever the step is |

**In the `degraded` band the answers get worse before the window runs out**, and an auto-compaction in the middle of a validation drops what it was checking. The limit holds even when the user asks: explain the fill and give the command instead.

### Which step — one, decided by the story's state

The question offers **one** next step, never a menu of modes: a menu hands the user a decision the run already has the facts for, and recommending validate beside a pending fix recommends checking work that is known to be unfinished. The first match wins:

1. **Refine** — the plan no longer describes the work: an entry in `.draft/deviations.yaml` carries `follow_up: true` ([Deviation Register](run-mode.md#deviation-register)), or this run closed `Validation fixes — round 1` ([Fix loop bound](validate-mode.md#fix-loop-bound)). The option's description names what is owed, in one line
2. **Run the rest** — the plan still holds and part of it is unrun: the last close's `census.open > 0`. The step is `/epico:epico stories NNN run all`, and the description names the open tasks. A partial run (`run N`) lands here: its open boxes are planned work, not a plan to change, and refining them would re-plan what is already planned
3. **Validate** — otherwise: the story is finished and nothing is owed. Its pass point makes the archive offer ([validate-mode.md](validate-mode.md#archive-offer))

**Archive is never this question's step.** A finished run is `done`, and `done` is not `validated`: the archive is offered after a passing validate, and a story absorbed by another reaches it through [supersede](supersede-mode.md#the-archive-offer). `archive-story.sh` enforces the same rule — without `--force <reason>` it refuses anything not `validated`.

### The question

Two options — three for a `layperson` requester — the step first, its label ending with the recommended marker **in the user's language** (e.g. `(Recomendado)` in a Portuguese conversation — never a literal English `(Recommended)` in another language):

- **The step** — Refine, Run the rest or Validate, run here in the `high` and `efficient` bands; *New session* with its command in the `degraded` band. **A fix round is asked, never chained.** A fix round's Validate names the round and its cost in the description, and nothing revalidates until the user answers ([Fix loop bound](validate-mode.md#fix-loop-bound))
- **Stop here** — end the run; the closing line prints the step's command so it can be run later
- **See it running** — `layperson` requester only, and only when the program has a way to run it that the run has not shown yet: run it with sample input and **show the output as text** — a few lines of what the program printed or the page returned, written in the chat — and only after that text ask the question again, without this option: **never a question right after a question**, since a second `AskUserQuestion` with no text before it hides the result the requester asked to see. For someone who does not program, seeing it work is the natural next step, and without the option they answer in free text and the question is lost

**A `layperson` requester is asked too** — the question comes after the closing three lines, never instead of them, and the three-line form rule does not remove it. Every label and description says what the option does for them, never the mode's name alone ([plain-register.md](plain-register.md)).

**Ask whenever `AskUserQuestion` is callable** — listed among the tools, directly or as a deferred tool to load ([triage.md](triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage)). That is the only test: a Fast default and a missing Task tool do not make the run's end headless. **`--auto` is the one exception, and it is explicit**: the user asked not to be asked, so the recommended step is taken — started, when it is *Validate* or *Run the rest*; printed as a command, when it is *New session*, a fix round's revalidation or anything after a validation — and logged as an assumption. **Never write the step as prose while the tool is callable** — a recommendation in the closing text is the question lost.

**Only when `AskUserQuestion` is not callable:** do not start the step. End the closing message with the recommendation and its command — the same rule the archive offer applies ([validate-mode.md](validate-mode.md#headless)); a run's end is not a gate to take on the user's behalf.

**One memory write precedes the question, when memory is available and the register is not empty.** Write the deviation register as one page at `epico/deviation/NNN-<slug>.md`: an H1 `# Deviations of story NNN — <title>` and then the register's entries — deviations and discoveries — as they stand in `.draft/deviations.yaml`, with no secret carried over. One page per story at a stable path, so a re-run of the story rewrites it instead of adding a second. An empty register writes nothing; unavailable memory calls nothing ([mcp-integration.md](mcp-integration.md#memory-mcp)).

## Assumptions under `--auto`

Every point where `--auto` answered for the user is an assumption, and every assumption is written down — the user who said "do not ask me" still reads what was decided.

- **What is logged:** each group gate passed, each doubt resolved (from the constitution, or from the recommended option when it covers nothing), and the end-of-run step taken. One line each: the point, the option taken, the alternatives, and why — `constitution: ## Defaults` or `recommended`.
- **Where:** `.draft/run-report.md` under `## Assumptions`, in the order they were made; and, when memory is available, the same list as the page `epico/decision/<NNN>-auto-assumptions.md` (H1 `# --auto assumptions of story NNN`), rewritten at that stable path by a later `--auto` run of the story.
- **What it is not:** a question. Nothing in this list waits for an answer; the closing message names how many assumptions were made and where they are.
- **What still stops the run:** a validation or test failure, the three-failure breaker, a refused close (`epico-test-diff`), and a step that would leave the machine (push, merge, publish).


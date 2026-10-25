# Checkpoint mode — closing a stage

`/epico:epico checkpoint <N>` closes stage N of the project's ROADMAP: it reconciles the plan with what the stories delivered, records the gate, decides what the stage changed in the documents, and details the next stage. It writes documents only through the doc writer ([memory-modes.md](memory-modes.md#sync-docs)), never code, never a story.

It needs a ROADMAP — `ROADMAP.md`, `docs/ROADMAP.md` or `docs/stages/*.md` — that numbers stage N's tasks. Without one, say so in one line and stop.

## The user leads

- **Mechanical items** (step 1) come prefilled: show what the script found, and the user confirms or corrects.
- **Judgment items** (steps 2, 3, 4 and 6) show the evidence first, ask for the user's verdict, and only then give Epico's own reading and where the two differ. Their `AskUserQuestion` options carry **no `(Recommended)` marker** — an exception to [clarify.md](clarify.md#question-shape): a recommendation in the options is the conclusion handed over before the user has judged.
- **`--auto` does not answer judgment items.** Under `--auto` the checkpoint runs step 1, prints it, and stops before step 2, saying why. Headless: print every step's evidence and proposed answers, write nothing.
- Every answer is recorded (§The record); "the user overrode Epico" is counted from it.

## Procedure

1. **Reconcile.** Run `epico-checkpoint --stage <N>`. Each task arrives with a state:
   - `closed` — an archived story names it; confirm in one block.
   - `in-work` — an open story names it; the stage is not done while it lasts.
   - `unmapped` — checked, but no story names it: a story from before `roadmap:` existed, or work done outside a story. Propose the story by title from `stories_without_roadmap`, or ask whether it was done outside a story.
   - `mismatch` — unchecked, but an archived story closed it: ask whether the task is done or the story covered it only in part.
   - `open` — nothing names it: done, handed forward, or dropped — ask.

   An ID in `unknown_ids` is a story pointing at a task the ROADMAP does not hold: name it. A delegated sub-agent may gather the artifact each done task points at (file, commit, measurement), so this step does not fill the orchestrator's context.
2. **Gate.** When stage N carries a gate, show the evidence for each criterion (command runs, measurements, records), then ask the user's verdict — `go`, `no-go` or `proceed-with-changes` — then give Epico's. The record goes to `docs/gates/gate-<n>.md` through the doc writer, in the form an earlier gate record of the project uses. A verdict with changes required names, for each change, the stage that does it.
3. **Decisions and rules.** For each deviation the stage's stories recorded that changed a decision, and each ADR the stage contradicted: the user chooses to supersede, amend or accept ([memory-modes.md](memory-modes.md#sync-docs), step 3). A finding becomes a constitution invariant only when it reproduces and affects future work, with the evidence attached; the same question retires an invariant or an Enforcement check that no longer applies.
4. **Findings.** First offer to run the sensors when `epic-supervise` is on PATH — `epic-supervise sense --root <project> --stage <N>` runs the project's own checks on a fresh clone and records what fails; wait for it. Then gather the open findings about the stage — `epic-finding list --root <project> --status open` when the project has a findings store, memory `epico/finding/` pages (and their [legacy `epic/`](mcp-integration.md#typed-pages)) when memory is available, deviations and open boxes — grouped, each with its evidence. For each, the user decides: a story now, handed forward to a named stage, or rejected; record a store finding's decision with `epic-finding decide`. A finding becomes a story only here, and only through CREATE or `stories from-memory`.
5. **Documents.** Everything accepted in steps 1–4 goes through the doc writer, one document at a time: the ROADMAP (checkboxes of confirmed tasks, blockers with dated outcomes, a handed-forward section for stage N with each item's reason, cost and address, notes that no longer hold), the gate record, PRD and ADR changes.
6. **Next stage.** Detail the next stage — or several, when the user asks — in the form the ROADMAP already uses for a detailed stage. After the draft, ask two questions: "what does this stage miss for this kind of system?" and "what can go wrong?". A risky task gets a short research note — prior art and the riskiest assumption — before its stories exist. Print the `stories create --batch` command for the stage; do not run it in this session.

The checkpoint's closing records **"done (workaround)"** apart from a root-cause fix, so a workaround is never read as a closed problem.

## The record

`.epico/checkpoints/<N>.yaml`, written at the end:

```yaml
stage: <N>
date: <YYYY-MM-DD>
gate: go | no-go | proceed-with-changes | none
items:
  - step: 2
    item: "<what was judged>"
    user: "<the user's verdict>"
    epico: "<Epico's reading>"
    final: "<what was recorded>"
documents: [<each file the doc writer wrote>]
next_stage: <N+1>
```

Mechanical items from step 1 are summarised by count, not listed. It follows the project's `.epico/.gitpolicy`: versioned under `tracked-md`, local under `local-only`.

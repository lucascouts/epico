# Refine Mode

Triggered by `/epico:epico stories refine NNN`.

## Procedure

1. Read existing story from `.epico/stories/<name>/`
2. Identify what changed
3. Produce delta document for affected phases:

```markdown
## Delta: story.md

### ADDED
- R2.4: WHEN user enables 2FA THE SYSTEM SHALL require TOTP verification

### MODIFIED
- R1.3: Changed timeout from 120s to 180s (reason: portal latency)

### REMOVED
- R2.3: Remember Me (deferred to next sprint)

### UNCHANGED
- All other requirements remain as-is
```

4. Delta shown for approval before merging into original
5. Propagation: story change > update design > update tasks. Design change > update tasks. Tasks change > no propagation.
6. Original files untouched until all gates pass
7. If the merged `tasks.md` gained a sub-task whose `Tests:` field is not `None` and the story is at engineering level `project` or `product`, author its test and record its Red **before** the census — see [Red Evidence for Added Sub-tasks](#red-evidence-for-added-sub-tasks)
8. After the merged tasks.md is written, take the checkbox census and apply the status transition — see [Status Census](#status-census)

## Red Evidence for Added Sub-tasks

**Standard and Full at engineering level `project` or `product` only** ([engineering-level.md](engineering-level.md)). At `experiment` or `tool` a refine-added sub-task's test is written at run time like every other test of that story, and this section does not apply. Refine is the one mode that can add a sub-task to a story whose Phase 3 has already run. Phase 3 is where the Test Advisor authors a test per `Unit`/`Integration`/`E2E` sub-task, confirms it Red, and records that in `.draft/red-evidence.yaml` ([phase-gates.md](phase-gates.md#test-advisor-sub-agent-standard--full-during-phase-3)). A refinement that adds a task and stops at propagation produces a sub-task that **carries a `Tests:` field and has no authored test and no Red entry** — and nothing downstream notices, because every consumer assumes Phase 3 ran for the whole task list.

The checks that read Red evidence state that assumption as an absolute: [validate-mode.md](validate-mode.md) and [auditor.md](../agents/auditor.md) both say *"every sub-task with a pre-authored test has an entry in `.draft/red-evidence.yaml` with `failed: true`; a missing entry is reported as a finding."* The finding is only ever reported for a sub-task that **has** a pre-authored test. A refine-added sub-task has none, so it is not missing evidence — it is invisible to the check, which is a different and quieter failure.

So, for **each** sub-task the merge adds whose `Tests:` field is not `None`:

1. Spawn the Test Advisor for that sub-task alone, with the same contract Phase 3 uses — it writes **only** inside `.draft/` (the authored test under `.draft/authored-tests/` at its mirrored path, and its `.draft/red-evidence.yaml` entry) and touches no project file.
2. `Unit` and `Integration` tests are confirmed Red now, exactly as in Phase 3. An `E2E` test records `red_deferred: true` and has its Red confirmed at run time, exactly as in Phase 3 — refine changes *when the authoring happens*, never *what the evidence means*.
3. **Append** to `.draft/red-evidence.yaml`; never rewrite it. The existing entries are dated records of runs that happened, and a refinement is not entitled to restate them.

**If the Test Advisor cannot establish Red** — the behaviour already exists, the test cannot be run, the sub-task turns out not to be testable — do not invent an entry and do not silently drop the `Tests:` field. Record the reason with `epico-deviation add deviation` (`.draft/deviations.yaml`) and surface it with the delta, so the gap is a decision someone made rather than an absence nobody saw.

**Why this is a step and not a gotcha.** A one-time sweep for sub-tasks carrying a non-`None` `Tests:` field closes the gaps it finds and has nothing to re-run it: every later refinement that adds a sub-task would reopen the class in silence. Only a step that runs on every refinement keeps it closed.

## Releasing a Test Blocked by `epico-test-diff`

`close-subtask.sh` refuses to close a sub-task whose materialized pre-authored test no longer asserts what `.draft/authored-tests/` holds — an assertion line changed, removed or added, or the test missing (`epico-test-diff --story <dir> --file <target_path>` shows which line). Restoring the assertion releases it; so does this mode, when the plan itself was wrong:

1. Show the user the assertion delta from `epico-test-diff` and say what the test now pins instead.
2. On a yes, MODIFY the requirement or acceptance criterion the test pins, in the same delta as everything else.
3. Copy the materialized test over its authored copy in `.draft/authored-tests/`, and run it: it must pass now, since the code was written against it.
4. Append an entry to `.draft/red-evidence.yaml` for that sub-task with `restated: <date>` and the reason; never rewrite the original entry.

Without the yes, the box stays open and the run reports why.

## Status Census

Refine is the one mode that can **add** open work to a story that already reads `done` or `validated`: a new requirement becomes a new task, and a new task is a new `- [ ]`. Nothing else in the engine does that — Run mode only ever closes boxes. So once the merged `tasks.md` is on disk (and only then: the boxes are what the census reads), census the task list and the Quality Gates, then apply the transition table in [run-status.md](run-status.md#status-transitions).

Exactly one rule may fire here:

- **Rule 2, the reopen edge** — the story reads `done` or `validated` and the merge left at least one `[ ]`: write `in-progress` to every artifact that carries frontmatter. Without this write the story would keep claiming it is finished while owing open work — the lie `validate-story.sh` reports as "status is ahead of the checkboxes".
- **Every other outcome leaves the field exactly as it was.** Refine is a writer of this one transition and of no other value: it never writes `draft`, `done`, `validated`, `superseded` or `archived`. A refinement observes that work was *added*, never that work was *finished* or that execution *started* — those are things only a run can see, and a story with no `status:` at all keeps having none.

The write mechanism is defined once, in [run-status.md](run-status.md#status-transitions): `Edit` on the frontmatter line and never `Write`, the same value in every artifact, a failed write reported while the refinement continues. Do not restate it here.

**REFINE performs that `Edit` itself — and only that one.** Run mode performs none of its own: `close-subtask.sh` carries the census and the stamp inside the invocation that closes the box, so the marking and its status can never be left apart. A refinement has no close to carry it — it **adds** boxes and closes none — which is why the orchestrator-side `Edit` survives here, for the `status:` frontmatter line and nothing else. **REFINE never writes a checkbox**: it appends new `- [ ]` boxes as part of the merged tasks.md, and never turns one into `[x]` or `[~]`. Closing a box stays the script's, in every mode.

## Gotchas

- Always propagate changes downstream via delta documents (story → design → tasks)
- Original files untouched until all gates pass — abort leaves originals intact
- A refinement that adds an open box to a `done` or `validated` story reopens it — census after writing tasks.md ([Status Census](#status-census))

## Expand Mode

1. Read the referenced existing story
2. Create new story in new directory (next sequential number)
3. Add "Related Stories" section in Introduction
4. Follow standard create flow

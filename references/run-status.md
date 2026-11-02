# Status Transitions — RUN

Loaded from [run-mode.md](run-mode.md#status-transitions) before the first box of a run is closed, and read by REFINE and VALIDATE, which apply the same table. It lives outside run-mode.md so that file stays under the project's 500-line limit.

## Status Transitions

The story's `status:` frontmatter field is **engine-written, never hand-edited**. Run mode owns two of the six values — `in-progress` and `done` — and writes them right after a box in tasks.md is marked. The other four belong elsewhere and Run mode never writes them: `draft` to CREATE, `validated` to VALIDATE, `superseded` to the supersede operation, `archived` to the archive operation. `in-progress` has one further writer, and only for one edge: REFINE mode, when a refinement reopens a story — the table below is the single definition both modes apply. See [lifecycle-status.md](lifecycle-status.md#lifecycle-status-status) for the full field spec.

**When the check runs:** after **every** marking in tasks.md — each sub-task marking, whichever route executed the sub-task (inline or Executor — [Closing a Box](run-mode.md#closing-a-box)), and the end-of-Run quality-gate settlement, which is usually the marking that closes the last box.

**In Run mode, `close-subtask.sh` runs it** — census and table both, inside the same invocation that closed the box (see Closing a Box), so a marking and its status can never be left apart. The orchestrator reads the outcome from the JSON's `status_written` and takes no census of its own. **Refine mode takes the same census by hand**, at its own point (see [refine-mode.md](refine-mode.md#status-census)): a refinement does not mark boxes, it **adds** them — which is the one way a story that already reads `done` gains open work, and there is no close call to carry the write, so REFINE performs the `Edit` itself. The table below is one definition with two performers, never two tables.

Census the boxes **as they now stand** — `open`, `closed` and `deferred` are defined once, in [tasks.md](tasks.md#completion), and the census spans the task list **and** the Quality Gates — then apply the first rule that matches:

| # | After the census | Then |
|---|---|---|
| 1 | no `[ ]` remains **and** no `[~] (deferred: …)` remains | write `done` (nothing to do if the field already reads `done`) |
| 2 | rule 1 did not fire, at least one `[ ]` remains, and `status:` reads **`done` or `validated`** | write `in-progress` — the story was **reopened** |
| 3 | rules 1–2 did not fire, and `status:` is **absent or `draft`** | write `in-progress` |
| 4 | none fired | write nothing |

Rule 1 is the canonical **`done`**: "every box is `[x]` or terminal `[~]`" and "no `[ ]` and no deferred `[~]`" are the same condition read from its two ends (see [tasks.md](tasks.md#completion) — do not restate it as a third variant). Rule 2 is the **reopen** edge, and it sits *below* rule 1 on purpose: a marking that re-completes the story still writes `done`, so reopening is only ever recorded when work is genuinely open again. Rule 3 is the first marking of a story that has not been executed before: absence and `draft` are the two states a run can start from. Rule 4 keeps a story already `in-progress` where it is — the transition is written once, not re-affirmed on every sub-task. A marking that satisfies rule 1 on a story that had reached `validated` writes `done`: work done after a validation is work that validation did not cover, and VALIDATE earns `validated` back on its next pass.

**Reopening is defined by `[ ]`, and only by `[ ]`.** Rule 2 fires on an open box, never on a deferred one — a `done` story that gains a `[~] (deferred: …)` box is not reopened by it, because nobody here owes that work. This is the same reading `validate-story.sh` applies to its ahead-of-checkboxes warning, and it is why the two agree: rule 2 exists precisely so the engine never leaves behind the `done`-with-an-open-box state that warning exists to expose.

**A deferred box blocks `done` — deliberately.** A story whose only remaining non-`[x]` boxes are `[~] (deferred: …)` does **not** get `status: done` from Run mode. Its status stays `in-progress`. Its completeness is visible as the computed condition **`done-except-external`**, which is derived from the boxes at read time and never persisted — LIST renders it `in-progress · done-except-external (N deferred)`. The persisted enum has no value for that condition, and that is deliberate, not an omission: the work is settled in the plan and still owed in the world, so the lifecycle state must not claim the story is finished.

**Writing the transition.** The five rules below are what the write must satisfy, **whoever performs it**. Run mode performs none of them by hand — `close-subtask.sh` does, inside the close — while REFINE and VALIDATE cite this list as the single definition and perform the `Edit` themselves:

1. **`Edit` the frontmatter line — never `Write` the file.** The PostToolUse hook in `hooks/hooks.json` matches **`Write` only**: a `Write` under `.epico/**` re-runs `validate-story.sh`. Transitions written with `Write` would fire a full validation pass after every marking — a validation storm on an advisory metadata update. An `Edit` of the single `status:` line does not trigger the hook. `close-subtask.sh` satisfies the same requirement from the other side: it replaces that one line through a temp file renamed into place, and a Bash write fires **no** PostToolUse hook at all — which is why the script runs `validate-story.sh` once itself, after the marking and the stamp, and reports the verdict in the JSON's `validate` field.
2. **The same value in every artifact of the story that carries frontmatter** — `story.md`, `design.md`, `tasks.md`, whichever exist (a Fast story has only tasks.md). One story, one lifecycle state: artifacts declaring different values raise a validation warning naming them. An artifact with no frontmatter is skipped — there is no line to edit, and its silence is never counted as divergence.
3. **Legacy story with no `status:` field — the `Edit` adds it.** Most existing stories predate the field; absence is legal, silent, and never an error. Insert `status: <value>` as a new line inside the frontmatter block, before the closing `---`, in each artifact that has one.
4. **Add only the state this run observed.** The value added is what the engine just saw: a marking that leaves work open is `in-progress`; a marking that satisfies rule 1 is `done`; a census that finds open work on a story reading `done` or `validated` is `in-progress` again. Never back-date `draft` onto a story the engine never saw created, and never write an intermediate value the run did not observe — a legacy story whose first marking also completes it goes straight from no field to `done`, in one write. The field is worth having only because it is evidence; a fabricated prior state is exactly the lie it exists to prevent.
5. **A failed write is reported, and the run continues.** If an `Edit` cannot be applied — no frontmatter block, the line is not where expected, a concurrent edit conflicts — report it in the Run output and carry on. `status:` is advisory metadata and must never block the run that is producing the actual work.

**Dry run.** `042-legacy-import`: three artifacts (`story.md`, `design.md`, `tasks.md`), none carrying `status:` — a legacy story.

```
tasks.md at the start                       status: in all three artifacts

- [ ] 1 - Import pipeline                   (absent)
  - [ ] 1.1 - Parse the vendor CSV
  - [ ] 1.2 - Load into staging
- [ ] 2 - Cutover
  - [ ] 2.1 - Switch the production reader
## Quality Gates
- [ ] Schema diff reviewed by the data owner
- [ ] Load test at 1k rps

1. Run starts. Nothing closed yet -> no call, no census, no write.
   status: still absent. CREATE never ran on this story, so there is no `draft`
   to back-date: the run has observed nothing, so it records nothing.

2. 1.1 passes its reviews -> close-subtask.sh 042 1.1
   {"box":"x","census":{"total":7,"open":6,"closed":1,"deferred":0},
    "status_written":{"from":null,"to":"in-progress"},
    "validate":{"errors":0,"warnings":0,"status":"pass"}}
   6 open, 0 deferred -> rule 1 no. status: absent -> rule 2 no
   (nothing to reopen) -> RULE 3. The script stamps `status: in-progress` into
   story.md, design.md and tasks.md; `from` is null because there was no field
   to move, not because the write was skipped.

3. 1.2 passes -> close-subtask.sh 042 1.2
   {"box":"x","census":{"total":7,"open":4,"closed":3,"deferred":0},
    "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
   closed went 1 -> 3 in ONE call: `- [x] 1` closed in the same write as its
   last open child, so no second call names the header.
   4 open -> rule 1 no. status: in-progress -> rules 2 and 3 no. RULE 4:
   nothing written, which is what status_written null reports.

4. 2.1 passes -> close-subtask.sh 042 2.1
   {"box":"x","census":{"total":7,"open":2,"closed":5,"deferred":0},
    "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
   `- [x] 2` closed with it. 2 open (both Quality Gates). RULE 4.

5. End-of-Run quality gates settled, one call per gate:
   epico-close 042 "gate:Schema diff reviewed by the data owner"
   {"box":"x","census":{"total":7,"open":1,"closed":6,"deferred":0},
    "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
   epico-close 042 "gate:Load test at 1k rps" \
     --tilde "waived: no load-test rig on this host — user decision"
   {"box":"~","qualifier":"waived",
    "census":{"total":7,"open":0,"closed":7,"deferred":0},
    "status_written":{"from":"in-progress","to":"done"},
    "validate":{"errors":0,"warnings":0,"status":"pass"}}
   0 open, 0 deferred (the waived gate is terminal, so it counts closed)
   -> RULE 1. status: in-progress -> done in all three artifacts, and
   status_written.to == "done" is what makes the next step Validate.
```

The same run, with one box deferred instead:

```
4'. 2.1 cannot be executed here — the vendor's production account does not exist
    yet. The Executor reports outcome close-tilde, and the orchestrator lifts it:
    epico-close 042 2.1 \
      --tilde "deferred: needs the vendor's production account"
    {"box":"~","qualifier":"deferred",
     "census":{"total":7,"open":2,"closed":4,"deferred":1},
     "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
    `- [x] 2` still closes with it: a deferred child is not an OPEN child.

5'. Quality gates settled exactly as in step 5. The last call returns
    {"census":{"total":7,"open":0,"closed":6,"deferred":1},
     "status_written":null,"validate":{"errors":0,"warnings":0,"status":"pass"}}
    0 open, 1 deferred -> rule 1 does NOT fire.
    status: in-progress -> rules 2 and 3 no. RULE 4: nothing written.
    The story stays `in-progress`. LIST renders it
    `in-progress · done-except-external (1 deferred)`.
    status_written is null on every call of this run; the next step is still
    Validate, which can take the in-progress -> validated edge.
```

And the reopen edge, on the story left at `done` by step 5:

```
6. A Refine adds a task the story did not have:
   `- [ ] 3 - Backfill the rows the first import dropped`.

   Census (refine-mode, after the merged tasks.md is written — taken BY HAND:
   a refinement adds boxes and closes none, so there is no call to carry it):
   1 open, 0 deferred -> rule 1 no. status: done + an open [ ] -> RULE 2.
   Edit all three artifacts: status: done -> in-progress.
   validate-story.sh -> 0 errors, 0 warnings — without this write it would
   report "status is ahead of the checkboxes".
```

Metadata lines and the `Objective`, `Validation`, `Requirements` and `Commit` fields are elided from all three listings: they carry no checkbox and never enter the census. The JSON objects are elided too, to their load-bearing fields — every call also returns `story`, `task` and `reason`.


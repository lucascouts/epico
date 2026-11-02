# Lifecycle status — the `status:` field

Loaded by the modes that write or read `status:` — Run, Validate, Supersede, Archive and the index. Kept outside [SKILL.md](../skills/epico/SKILL.md) so a run that does not need it does not carry it.

### Lifecycle Status (`status:`)

`status:` is the story's lifecycle state, carried in the frontmatter of every artifact that has frontmatter. Six values, no others:

| Value | Written by |
|---|---|
| `draft` | CREATE — when the artifacts are first written |
| `in-progress` | RUN — when execution of the story starts, written by `scripts/close-subtask.sh` inside the close; RUN **or** REFINE when a census finds open work on a story reading `done` or `validated` (the reopen edge) — REFINE performs that one `Edit` itself, since a refinement adds boxes and closes none |
| `done` | RUN — written by `scripts/close-subtask.sh` when a marking satisfies rule 1 of the [status transition table](run-status.md#status-transitions); a deferred `[~]` blocks it |
| `validated` | VALIDATE — after the validation and the audit pass |
| `superseded` | the supersede operation |
| `archived` | the archive operation |

- **Engine-written, never hand-edited.** The writer list above is exhaustive — no other mode touches the field. A human editing it is tolerated, not blocked: validation only flags the result. A value outside the six is an **error**; `done` or `validated` while a `[ ]` box is still open is a **warning** (the status is ahead of the checkboxes).
- **In RUN the write is script-mediated — the orchestrator does not perform it.** `scripts/close-subtask.sh` marks the box, takes the census, applies the transition table and stamps every artifact that carries frontmatter, all inside the invocation that closed the box; the orchestrator supplies the Executor's closing block and reads back `status_written` from the returned JSON. Neither the orchestrator nor the Executor edits the field — or the box — by hand. The other writers in the table above perform their own `Edit`, because no close call is passing through to carry it.
- **Same value in every artifact** of the story, exactly like `version`. Artifacts declaring **different** values raise a warning naming them. An artifact with no `status:` carries no opinion and is never counted as divergent.
- **Absence is legal and silent.** A story with no `status:` anywhere is neither an error nor a warning — stories written before the field validate byte-identically. The field is never required by validation.
- **Persisted values only.** `done-except-external` is not a `status:` value: it is a condition computed from the checkboxes at read time (see [tasks.md](tasks.md#completion)), never written to a file.
- **Written with `Edit`, not `Write`** — deliberately. The `hook-validate` PostToolUse matcher in `hooks/hooks.json` is `Write` only, so engine status transitions must not re-trigger a validation pass on every write.
- **Companion field `superseded-by: MMM`** — optional, written **only** by the supersede operation, next to `status: superseded`. It names the story that took over the scope and is the machine-readable source the story index renders. Nothing else writes it.

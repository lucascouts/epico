# Multi-Tech Review — RUN

Loaded from [run-mode.md](run-mode.md) when a sub-task's `tech_profile` carries
two or more technologies that interact at a boundary, or when its Complexity is
`High` — which reviews even a single-technology sub-task.

When a sub-task's tech_profile includes 2+ distinct technologies that interact at a boundary, the orchestrator spawns Tech Reviewer sub-agents — `model` set by the `reviewModel` option, as run-mode.md's Execution Threshold says — AFTER the sub-task's implementation passes validation — whether an Executor or the main agent inline did the work.

### When to Trigger

Detect technology boundaries from the tech_profile:

| Boundary | Examples |
|----------|---------|
| Server code → template engine | Rust handler + Tera, Python view + Jinja2, Express + EJS, Spring + Thymeleaf, Phoenix + HEEx, Laravel + Blade |
| Application code → raw SQL | Any language with sqlx, raw queries, query builders |
| Backend → frontend contract | API response consumed by React/Vue/Angular client, SSR hydration |
| Application → external API | HTTP client calling third-party services |
| Application → message queue | Producer/consumer message format contracts |

If only one technology with no boundary interaction: skip review — unless the sub-task's Complexity is `High`, which reviews always, even single-tech.

### Tech Reviewer Prompt Template

The Tech Reviewer's focus areas, its measurement rule and its report format live in its agent definition ([tech-reviewer.md](../agents/tech-reviewer.md)), which Claude Code loads as its system prompt. The spawn prompt carries only the inputs:

> "Review the [technology] boundary of this sub-task. Follow your agent definition.
>
> ## Technology and boundary
>
> [technology] — [the boundary, e.g. handler → template, app → SQL — or `none: single-tech review (Complexity High)`]
>
> Story directory: [absolute path to .epico/stories/NNN-slug in the main tree] · Sub-task: [number]
>
> ## Language rules
>
> [`references/language-rules.md#<language>` for each technology under review — or `no language-rules.md section for <language>`, never rules invented for it]
>
> ## Files to Review
>
> [Files the sub-task created or modified — from the Executor's report, or from the inline route's own closing block]
>
> ## Design Contract
>
> [Relevant interface from design.md for this boundary]"

### Orchestrator Handling of Tech Review

- If all Tech Reviewers report PASS: proceed to next sub-task. Never ask a Tech Reviewer for more findings after a `PASS` — zero findings is a valid review, and a second ask turns the edge-case questions into a quota the reviewer fills by inventing issues
- If any reports INCOMPLETE: tell the user what was not reviewed and why, and ask whether to proceed — an unfinished review is not a pass
- If any report ISSUES:
  1. Present issues to user (in `--auto` mode: attempt fix first)
  2. Fix them on the route the sub-task took: inline, the main agent fixes them itself; delegated, spawn a new Executor with the original task + the issues
  3. Re-run only the affected Tech Reviewers
  4. Maximum 2 fix cycles. If still failing after 2 cycles, stop and escalate to user
- Tech Reviews are skipped for a group's `Commit:` field — there is no implementation to review

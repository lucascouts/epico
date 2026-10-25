# Context Discovery

## File Discovery (all scales)

1. Glob for `spec.md`, `roadmap.md`, `*.spec.md` in project root
2. Check for `.epico/stories/` directory (existing stories)
3. Check for `.epico/constitution.md`
4. Check for `docs/` with relevant documentation

`CLAUDE.md` (and `AGENTS.md` where the project has no `CLAUDE.md`) are not read here: Claude Code already loads them into this session and into every sub-agent, and reading them again pays for the same text twice.

Include findings assertively in triage. If user mentions files directly, use them without asking.

## Prior Knowledge

Runs in **all scales**, and only when triage step 7a found memory available ([mcp-integration.md](mcp-integration.md#memory-mcp)). Two calls, before the Analyst is spawned and before any inline question is asked:

1. `memory_recent` with `limit: 5` — what the last sessions on this project left behind
2. one `memory_query` whose query is the request's own nouns joined by `OR` — the entities, actions and files the user named — with `limit: 10`
3. one `memory_query` with `global: true` for the techs the request or the scan names, restricted to `gotcha` and `research` pages (`epico/gotcha/` or `epico/research/` in the path, or their [legacy `epic/`](mcp-integration.md#typed-pages)), `limit: 5` — what other projects learned about the same stack. Each hit is a pointer: verify it against this codebase and this version before it changes anything

The hits are injected as a **Prior Knowledge** block in the triage proposal and in the Analyst prompt below, one line per hit: path, title, snippet. Rules:

- **A hit is a lead, not a fact.** The Analyst verifies it against the code before it reaches the story; a stale page loses to the file every time, and a hit no file supports is dropped without comment
- Prior knowledge never replaces the Codebase Analysis — it points the Analyst at what past stories found surprising, so the scan starts there instead of from zero
- Nothing here asks the user anything; a user who mentioned files directly still has them used without asking
- Absent memory, this section is skipped in silence and the flow below is unchanged

## Codebase Analysis (standard + full scales)

If existing code is detected, spawn the **Analyst** sub-agent — `run_in_background: false`, and wait for its result: the proposal needs its output ([personas.md](personas.md#personas)):

> "Run the Codebase Analysis of your agent definition for this request.
>
> User request: [original request]
> Context files found: [list]
> Prior knowledge (from memory — verify against the code before using any of it): [Prior Knowledge hits, or "none"]"

The steps, the 20-line summary and its contents (the quality-catalog signals included) live in [analyst.md](../agents/analyst.md).

Results are saved to `.draft/meta.yaml` under `analyst_output` key and passed as context to Phase 2 (design) and the Completeness Checklist. **On an empty repository nothing is spawned**: `analyst_output` is written as `none: empty repository`, so the Completeness Checklist still receives an analysis and knows the work is greenfield.

## Context File Usage

| File | Applied At |
|---|---|
| `.epico/constitution.md` | Before Phase 1 (all scales); its `## Defaults` block again at Clarify and Run, as decisions taken silently |
| Analyst output | Triage + Completeness Checklist + Phase 2 (design) |
| Prior knowledge (memory, when detected) | Triage + Codebase Analysis — as leads to verify, never as facts |

- Files are read if they exist, silently skipped if absent
- Content is injected as context, not modified
- Conflicts between context files and user input → user input wins
- Constitution constraints appear as `[CONSTITUTION]` tags in story requirements
- Constitution `## Defaults` are applied, never re-asked — [plain-register.md](plain-register.md#decisions-the-requester-is-not-asked)

## Completeness Checklist

For **standard and full scales**, the **main agent writes the checklist itself**, inline — no sub-agent. It reads no file for it: its only inputs are the codebase analysis already in hand (`.draft/meta.yaml`, `analyst_output` — `none: empty repository` on a greenfield story), the request and the constitution. A spawn would re-read all three from an empty context to produce the same questions. For **fast and spike scales**, ask 1-2 inline questions only — both are single-author scales, and a probe whose whole point is to be time-boxed is not improved by a 10-question intake.

1. Identify every entity, action, input, and collection in the request
2. For each, determine what implicit decisions the user hasn't stated
3. For each state-changing action (create, login, enable, open, start), verify the inverse (delete, logout, disable, close, stop) is addressed or explicitly excluded
4. Check for common pitfalls and edge cases in this domain — with a research MCP or `WebSearch`, only when the domain is not evident from the request and the analysis
5. Write **5-10 assertive items**, each "I understand X will work as Y. Confirm?", with X and Y phrased as a **consequence the requester can observe**, never as the mechanism that produces it ("a stolen session stops working when the password changes", not "tokens are invalidated"). **Rank them by impact** — the story's question budget keeps the top of the list, and the rest become stated defaults
6. For each proposed approach, check that it fully satisfies the requirement's intent — `<approach> — satisfies | partial: <what is missing>`

On a greenfield story (`none: empty repository`) there are no patterns to confirm: ask about the stack only when the request leaves it open, and spend the questions on behaviour. Never ask what the request already answers.

**Rules:**
- Present the questions in **rounds**, per the [Clarify Protocol](clarify.md#clarify-protocol) — orientation first, then precision, each round built from the last, every item reshaped into the consequence the requester can observe; the single numbered list is the headless fallback
- If the user answers "out of scope", add to Out of Scope in story.md
- For fast and spike scales: ask 1-2 inline questions only if needed

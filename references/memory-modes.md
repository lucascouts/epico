# Memory modes — stories from memory, docs from memory

Two modes turn what the project learned into something it keeps, and neither touches code: **memory → story → run** is the only way a finding becomes a change, and **doc diff → the user's yes** is the only way it becomes a document. Stories from memory needs memory available ([mcp-integration.md](mcp-integration.md#memory-mcp)); without it, say so in one line and stop. Sync docs reads memory when it is there and works without it.

## Stories from memory

`/epico:epico stories from-memory [<page>]` drafts a story from a `proposal` page ([Typed pages](mcp-integration.md#typed-pages)) — a change an outside classifier or a supervisor thinks the project needs.

1. **Pick the proposal.** With `<page>`, read it (`memory_read_page`). Without, list this project's `epico/proposal/` pages (and their [legacy `epic/`](mcp-integration.md#typed-pages)) not yet drafted (no `drafted:` line), newest `as_of` first, at most ten, and ask which one with `AskUserQuestion`. Headless: print the list and stop — choosing a story to open is the user's decision, never an assumption. A proposal marked `priority: urgent` is listed first and drafted only after the user acknowledges it in its own question — it came from a supervisor's urgent lane, not from a checkpoint's triage — and headless never drafts it.
2. **Verify it against the code** ([lookup-order.md](lookup-order.md)). Every file, line, behaviour or number the page states is checked; what no longer holds is said beside the proposal, and a proposal whose premise the code contradicts is reported and not drafted.
3. **Draft it through CREATE**, with the verified proposal as the request — triage, the constitution gate, clarify and the phase gates exactly as for any request. The story's `story.md` frontmatter carries `source: memory:<page path>`.
4. **Mark the proposal drafted**: rewrite its page with a `drafted: <NNN-slug>` line under the header, so it is never drafted twice.

The story then runs like any other. Nothing in the proposal is executed, and nothing it says skips a gate.

## Sync docs

`/epico:epico sync-docs` turns what the project learned into a diff for its own documents, and writes only what the user accepts. Two parts: a **collector** that gathers the items, and the **doc writer** — the only thing in Epico that writes a project's root documents.

1. **Collect** the items since the last sync — the date in `.epico/.sync-docs` (absent: everything):
   - **From memory, when it is available:** this project's `epico/finding/` and `epico/decision/` pages (and their [legacy `epic/`](mcp-integration.md#typed-pages)) with a later `as_of`. Without memory, say so in one line and use the other sources.
   - **From the archive:** the deviations of the stories archived since that date (their `archived_at` in `.epico/archive/manifest.yaml`) that changed a decision, a requirement or a rule.
   - **From the user:** a decision named in the request itself.

   Verify each item against the code; one the code contradicts is listed as stale and synced nowhere. Nothing collected: say so in one line and stop.
2. **Map each item to its document**, the ones the project has — each looked for at the root and under `docs/`:
   - `ROADMAP.md` — a decision that adds, drops or reorders planned work
   - the PRD (`PRD.md`) — a decision that changes a requirement or its scope
   - `.epico/constitution.md` `## Invariants` — a finding that became a rule, as `- Never <X> — <the incident>`; `epico-claude-md write` then carries it into `CLAUDE.md`
   - `adr/` — an architectural decision
3. **An ADR's text is never rewritten.** What changes decides the form:
   - **The decision changes** → a **new** ADR with the next number, `Supersedes: ADR-<n>` and the reason; the old file is left exactly as it is. A decision with no ADR yet is a new ADR too.
   - **Same decision, new detail** (a check that enforces it, a measured value, a clarification) → an **amendment**: a dated entry appended at the end, never an edit of the text above it. Follow the form the project's ADRs already use for amendments; with none, use `## Amendments` holding one `### Amendment <YYYY-MM-DD> — <title>` per entry, so links to an entry stay stable.
   - **Every new or superseding ADR carries `## Enforcement`**, typed bullets only: `- check: \`<command>\`` — the command that fails when the decision is broken (a lint rule, a test, a make target), optionally followed by `(warn-only: <switch>)` — or `- judgment-only: <reason>` when nothing can check it. An existing ADR gets the section as an amendment the next time a sync touches it.
4. **Show the diff, one document at a time, and ask** with `AskUserQuestion` — each document is accepted or declined on its own, and the question says what a yes does: "Write **and commit** `<file>` on `<branch>`?" (outside git: "Write `<file>`?"). Headless writes nothing and prints the diff.
5. **The doc writer writes and commits what was accepted**, one commit per document:
   - only that file is committed (`git commit --only -- <file>`), so nothing else staged rides along; a document with uncommitted edits of its own is refused — say so, and write nothing over the user's work;
   - the message carries trailers for what the change came from — `Story: <NNN> <title>`, `Finding: <page>`, `ADR: <NNNN>`, `Why: <one line>`, each only when it applies — the record a document's change log is built from;
   - no git identity, or a commit hook that refuses: the file stays written and uncommitted; say so, and name it in the closing;
   - never a push.
6. **Record the sync**: today's date in `.epico/.sync-docs`, and the items each written document took, in the closing.

Sync docs writes documents, never code, never `.epico/stories/`, and never a page back into memory except the `drafted:`-style markers this file names.

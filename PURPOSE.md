# Purpose & Scope

Epico has a single, narrow purpose: **create, structure, and manage the epics of a project** — the epic being the container that groups stories (`story.md` / `design.md` / `tasks.md`) and drives their planned execution.

Every feature of this plugin exists to serve that purpose. Anything outside it is out of scope by design and must be refused.

---

## Foundation pillars

Three pillars weigh every change to this plugin, in this order: **Security, Stability, Performance.** When two of them pull apart, the earlier one wins.

- **Security** — the plugin never leaks a secret, never runs input as code, and never acts outside the machine — a push, a publish, a deletion — without the user's explicit yes. A guard that cannot decide refuses; it never passes.
- **Stability** — the same input gives the same result. Scripts speak one JSON contract, write through a temporary file and a rename, and can be run again safely; every behaviour has a test written before it. When a proof is missing, the plugin takes the slower path that is known to be correct.
- **Performance** — the user's tokens and minutes are spent only where they buy something: deterministic work goes to scripts, each check runs once per state of the code, and nothing is done again that a proof shows unchanged.

The order is the rule for every trade-off. A shortcut that saves time is taken only when the result provably stays the same — re-running only what a change can reach needs the diff to prove that reach, and a diff that cannot be read re-runs everything — and a cache or a shortcut never skips a security check. Every pull request states its effect on each pillar ([template](.github/pull_request_template.md)); the mechanisms that enforce them are mapped in [ARCHITECTURE.md](ARCHITECTURE.md#foundation-pillars).

The pillars govern the plugin itself. What the plugin asks of the projects it builds is the quality catalog's business, bounded by the engineering level.

---

## In scope

Epico is responsible for:

- **Epico/story creation** — turn a request into EARS-notation requirements, an optional design document, and a hierarchical task breakdown (`tasks.md`).
- **Story management** — list, refine, archive, and version stories under `.epico/stories/`.
- **Task orchestration** — drive the Executor sub-agent through the 6-step protocol (context → implementation → design fidelity → validation → refactor-or-tests → report; step 5 is conditional) for each sub-task in `tasks.md`.
- **Planned validation & audit** — run the Auditor's validation and audit *against the story artifacts the plugin produced*, to verify implementation matches the planned scope.
- **Traceability** — enforce the R-number → design-component → sub-task chain via `scripts/cross-reference.sh` and the archive immutability guard.

---

## Out of scope (explicitly refused)

Epico must refuse the following, even when asked directly. The skill responds with a short message pointing the user to the correct Claude Code command or plugin.

| Request | Out-of-scope because… | Suggested alternative |
|---|---|---|
| **Code review** of arbitrary code, a PR, or a branch | Reviews not tied to an Epico story have no artifacts to anchor to | `/review`, `/security-review`, or `/code-review` (bundled) |
| **Security review** of arbitrary code | Same reason | `/security-review` |
| **Refactor** outside the scope of an existing story's `tasks.md` | Refactors without a planned story skip the design-fidelity contract | Create a new story first, then `run` its tasks |
| **Analysis / architecture advice** without an attached story | Epico artifacts (`story.md`, `design.md`) are the only valid containers for analysis under this plugin | A regular chat turn |
| **Exploratory code generation** outside a story | Implementation only happens inside Executor, driven by an approved sub-task | Create a Fast-mode story if the change is small |
| **Repo-wide refactor as a single story** | Violates the story-is-a-unit-of-work contract | Split into multiple linked stories (`based on` / `extends`) |
| **Execution of ad-hoc scripts / commands / investigations** | Epico only executes what is declared in a sub-task's `Validation:` or `Tests:` field | Run manually outside `/epico:epico` |
| **Debugging** a production incident | Debug flows live elsewhere and require different artifacts | A regular chat turn |

The refusal is not soft-fail; the skill surfaces a one-line rejection explaining *why* and pointing to the alternative.

---

## Why this boundary exists

- **Artifacts are the contract.** The Executor and the Auditor only work because they compare code against `story.md`, `design.md`, and `tasks.md`. Without those artifacts, the sub-agent pipeline has no anchor — the 6-step protocol degenerates into ad-hoc prompting.
- **Scope discipline prevents drift.** Every Epico run is traceable R-number → design-component → sub-task → commit. Accepting "just analyze this" or "just refactor this" breaks the chain and erodes the value proposition.
- **Claude Code has better tools for the rest.** `/review`, `/security-review`, `/code-review` and plain chat cover analysis, review, debugging and exploration. Epico's job is to formalize *decided* work, not to explore or audit *existing* work.

---

## How this is enforced

- The skill body (`skills/epico/SKILL.md`) opens with a scope check. Out-of-scope requests short-circuit to the refusal table.
- The skill refuses to write to paths outside `.epico/`, source files not listed in an approved sub-task's `Context:`, or archived stories (`.epico/archive/**`, blocked by `hook-archive-guard.sh`).
- `references/` files are only loaded when the relevant mode is active — there is no "free-form" mode.

---

## If you need to extend

Adding a new mode (`/epico:epico <verb>`) is allowed only if the verb still serves *creating, structuring, or managing an epic or its stories*. Modes that would widen the purpose (e.g., `review`, `refactor`, `debug`) are rejected at contribution time — see `ARCHITECTURE.md` → Extension points.

---

## Non-goals (reiteration for contributors)

- No idea exploration.
- No generic code generation outside a story.
- No code review of existing code.
- No refactor suggestions outside a story's tasks.
- No runtime dependencies beyond `bash`, `git`, `jq`.
- No version-controlled drafts (`.epico/` is `.gitignored`).

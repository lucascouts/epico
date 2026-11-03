# Personas — the sub-agents and when they are spawned

Loaded before a phase, a run or a validation spawns a sub-agent. Kept out of [SKILL.md](../skills/epico/SKILL.md) so a run that does not need it does not carry it.

## Personas

Sub-agents with specialized roles. Scale determines which personas are activated.

### Planning Personas (story creation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Analyst** | Codebase scan at triage — patterns, conventions, quality-catalog signals; the completeness checklist is the main agent's | standard + full, when code exists | `agents/analyst.md` |
| **Test Advisor** | Authors one test per Unit/Integration/E2E sub-task during Phase 3 — Red-verified for Unit/Integration, Red deferred to Run for E2E — and records red-evidence | standard + full at engineering level `project` or `product` (Phase 3, and per added sub-task in Refine); an `experiment` or `tool` story writes its tests at run time, as Fast does ([engineering-level.md](engineering-level.md)) | `agents/test-advisor.md` |
| **Reviewer** | Cross-artifact review, gap detection, consistency check | full only | `agents/reviewer.md` |

### Execution Personas (task implementation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Executor** | Implements a sub-task following the strict 6-step protocol; step 5 is conditional (Refactor for test-first sub-tasks, Tests for test-after). Ends its report with a machine-liftable **closing block** — sub-task id, outcome (`done` / `close-tilde` + qualifier + reason / `failed`) and the pre-authored commit message it validated against. **Marks no box and runs no `git commit`**: the orchestrator lifts that block into `scripts/close-subtask.sh`, the one writer of the checkbox grammar | all scales (delegated route) | `agents/executor.md` |
| **Final Reviewer** | Reviews finished lean-route work for a `layperson` with fresh eyes — the request, the floor and code it did not write; reports each gap with the command that reproduces it; never edits | lean route, `layperson` requester, once before the closing ([lean-route.md](lean-route.md#done-means-the-check-passed)) | `agents/final-reviewer.md` |
| **Tech Reviewer** | Reviews implementation at technology boundaries; holds `Bash` for measurement only (never mutating files or git state), so a finding resting on a runnable check carries the command and its output | all scales — a technology boundary, or `High` complexity even single-tech | `agents/tech-reviewer.md` |

### Post-Implementation Personas (validation)

| Persona | Role | Scale | Agent file |
|---|---|---|---|
| **Auditor** | One spawn, two parts: runs the validation commands, tests and gates ([validation-protocol.md](validation-protocol.md)) and writes `.draft/validation-report.yaml`; on a pass, compares implemented code against story + design and writes `.draft/audit-report.yaml` — each before any prose summary | all scales | `agents/auditor.md` |

The **main agent** (this skill) orchestrates: generates artifacts (story.md, design.md, tasks.md) during planning, delegates to Executors during run-mode, and spawns the Auditor during validation. The main agent retains conversation context with the user and handles git operations (commits) — post-merge, with the pre-authored message verbatim. It closes boxes too, but never by editing one: it invokes `scripts/close-subtask.sh` with the Executor's closing block, and the script performs the marking, the census and the `status:` stamp in a single transaction (a `failed` outcome makes no call at all).

**The orchestrator waits for every sub-agent's result before its next step, in the foreground wherever it can.** Pass `run_in_background: false` on the Agent call where that parameter exists. Where it does not, or the spawn comes back backgrounded anyway — sub-agents run in the background by default, interactive and `-p` alike, unless the user started Claude Code with `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`, which a plugin cannot set — wait for the sub-agent's completion notification: do not end the turn and do not ask the requester anything while it runs. The next step is the sub-agent's result: the Analyst's scan feeds the proposal, the Test Advisor's tests gate Phase 3, the Executor's closing block closes the box, the Auditor's verdicts end the mode. A turn ended to wait for a sub-agent is a turn the requester spends saying "still waiting". A backgrounded sub-agent can consume every turn of a run on "is it done yet?" while no code gets written. Both registers assume the assistant is working, not waiting. A parallel Executor group is not an exception: it is several Agent calls in one message, every one awaited before the next step. **Never pass `name` on the Agent call**: a named spawn can come back as a message instead of a result.

**Every spawn leaves progress notes on disk** — one `epico-progress` line per protocol step in the story's `.draft/progress.log`, so a stalled run is visible to `epico-doctor`. Pass the main tree's story directory in the spawn prompt as `Story directory:`. The Analyst and the Reviewer have no Bash: the orchestrator writes their `start` and `report` notes. See [mcp-integration.md](mcp-integration.md#progress-notes).

### MCP Integration

During triage, detect and health-check available MCPs. Load [mcp-integration.md](mcp-integration.md) for the full health-check procedure and category mapping.

Key rule: Never suggest an MCP the health check did not find connected — a check of the tool list, never a probe call. For Fast mode: skip MCP detection.

### Preferred Tooling

During triage, detect available E2E testing tools and the `frontend-design` aid, then resolve which to use. Load [preferred-tooling.md](preferred-tooling.md) for the favorite/optional tiers, the detection procedure, and the no-favorite recommendation.

Key rule: prefer a favorite (`playwright`, `chrome-devtools`); an optional tool is selected only when already installed AND the task context calls for it. Unlike MCP detection, preferred-tooling detection runs in **all modes, including Fast**.

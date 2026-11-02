# Clarify — the question rounds

Loaded when a Create run asks questions (Standard and Full always; Fast when the request is ambiguous). Instant never loads it: it asks nothing. It lives outside [SKILL.md](../skills/epico/SKILL.md) so a run that does not need it does not carry it.

## Clarify Protocol

**Mandatory for standard and full modes.** After triage confirmation, gather
clarifications using the `AskUserQuestion` tool. Multiple-choice prompts are
faster for the user than free-text confirmations and yield structured answers
the orchestrator can route on without re-parsing prose.

**The Epico asks the way an architect asks a client.** The requester came to
have something built, not to give instructions; whatever their level, they
know what it is and what it must do, and the how — the stack, the storage,
the pattern, the tooling — is not settled in their head. So every question
is about **what and what for**, and the **how is proposed, never asked**: it
arrives between the questions as a recommended option with its reason, in
words the requester can choose by. The level sets directness, not the amount
of context: a `developer` is asked in the stack's own terms, a `layperson` in
the plain register, and both get the context and the example.

- **Round 0 is orientation.** At most three context questions — who uses
  it, what exists today, what "done" looks like — or one open question in
  the requester's own words: "describe it as you would to a friend".
  Skipped when the request already answers them; a question the request
  answered is a defect in either register. The engineering level is never
  among them: triage infers it and the proposal line lets the requester
  move it ([engineering-level.md](engineering-level.md#how-the-level-is-read)).
- **Ask the consequence, never the mechanism.** "What happens to the data
  when the program closes?" decides persistence; "JSON or SQLite?" asks the
  requester to be the architect. The consequence is what they can observe
  and choose by; the mechanism is what their answer decides for them.
- **Every option carries its context and one example** — what choosing it
  implies, shown on this project. A bare label is a quiz. When the choice is
  technical and `requester.level` is `layperson`, add the analogy that lets
  them choose by logic ([plain-register.md](plain-register.md#explain-by-example));
  a `developer` gets the term instead, with the same context and example
  ([developer-register.md](developer-register.md)).
- **The how is a recommendation, never a question.** When a technical
  decision is due — stack, storage, pattern, tooling — offer it as options
  with the recommended one first and labelled with the recommended marker
  in the user's language — `(Recommended)` in English, `(Recomendado)` in
  Portuguese; never the English marker in another language — its reason
  in one line, and each alternative's trade-off in one line. Never an open
  "how do you want this built?".
- **Rounds are free in size, and built from what the last one left open.**
  Bundle only questions whose answers cannot change each other; a question
  whose answer can prune another goes alone, and first. Before composing
  round N+1, apply round N's answers: an `out-of-scope` answer removes its
  whole branch; a default taken removes the follow-ups that default implies;
  an answer given in tool vocabulary re-reads `requester.level` as
  `developer` for the rest of the story, and one given in outcome words
  keeps `layperson`; an answer that reveals how to work with this person —
  "I don't know how to run a command" — is appended to `requester.never`
  or `requester.always` and applied from then on. A question whose answer
  no longer changes the plan is not asked. When triage was unsure of the
  requester, round 0 opens with **one calibration question** — "How do you want me to work with you?" with two
  options in plain words: *explain in plain words and decide the technical
  details for me* / *ask me the technical questions* — and every round after
  it follows that answer.
- **One question budget per story, counted in questions from triage to the
  last box.** Every question in an `AskUserQuestion` call (or its
  numbered-list fallback) counts one; the orientation round counts one
  whatever its size; every phase gate and every question asked during Run
  counts one, against the same budget: **`layperson` — Fast 3, Standard 9,
  Full 12; `developer` — Fast 4, Standard 10, Full 14.** When the budget is spent, decide by the constitution's
  `## Defaults` and the
  [plain register](plain-register.md#decisions-the-requester-is-not-asked)
  table, write each decision as an assumption in story.md (Fast: in the run
  report) and proceed. Infinite clarification defeats the purpose — and so
  does a question the requester cannot answer.
- **The interface language is inferred, never asked** — its menu, prompts,
  messages and README speak the language the request was written in, stated
  on the proposal line. Asked only when it is in doubt: the request mixes languages
  or names readers who speak another one — in the requester's own language,
  one question, three options: English, the language they wrote in, another.
  Not asked when the request is already in English. The artifacts stay
  English either way ([Language](../skills/epico/SKILL.md#language)).
- For each ambiguity, build a question with **2–4 mutually-exclusive options**.
  When the answer is binary, prefer `[yes / no / out-of-scope]` over open
  phrasings.
- Focus on: ambiguities, scope boundaries, edge cases, dependencies.
- **Stack recommendation must consider story complexity.**
- **Implicit capability detection:** For each requirement, identify whether
  it implicitly depends on an architectural capability not yet established in
  the design. Add it as a multi-choice question (`include now / defer to
  follow-up story / explicitly out of scope`).
- For Fast mode: skip clarify only if request is unambiguous.
- **Never skip clarify for Standard/Full.**

### Question shape

The example below is in English; in any other conversation every label, description and marker is written in the user's language. One `AskUserQuestion` call takes 1–4 questions, each with a short `header` (up to 12 characters) and 2–4 options with a `label` and a `description`. Context goes into the question text or an option's description — the tool has no separate field for it:

```
header:   "Sessions"
question: "What happens to the other signed-in devices when a user changes their password? (affects R2.3, token lifetime)"
          ← the consequence; "invalidate the other tokens?" would ask the mechanism
options:
  - label: "Signed out (Recommended)"
    description: "The password change is the moment they wanted the others out; one extra query"
  - label: "Keep working"
    description: "Nothing to build; a stolen session survives the change until it expires"
  - label: "Out of scope"
    description: "Leave sessions as they are for this story"
```

### The run model (Standard and Full)

**The last question of the last round asks which model runs the story.** The session's model does most of a run's work — the orchestrator reads, plans, writes and coordinates — so it decides most of the cost; the Executor's model decides only its share. A plugin cannot change the session's model, so the answer is recorded and acted on at run time, in a session opened with it ([phase-gates.md](phase-gates.md#handing-off-to-run)):

```
header:   "Run model"
question: "Which model should run this story? It takes effect in the session that runs it"
options:
  - label: "Sonnet (Recommended)"
    description: "The quality of Opus on this kind of work at about a third of the cost"
  - label: "Opus"
    description: "The deepest reasoning, for a story whose design is the hard part; about three times the cost"
  - label: "Haiku"
    description: "The cheapest; writes fewer tests and skips more of the delivery details"
```

The answer is written to `tasks.md` as `run-model: sonnet | opus | haiku` ([tasks.md](tasks.md)). **Fast and spike do not ask**: they create and run in one sitting, with no session in between to open on another model. Under `--auto` or headless the question is not asked and no `run-model:` is written — the run uses whatever session runs it. **A `layperson` is never asked it**: a model is a choice they cannot weigh, so no `run-model:` is written and the story runs in the session that created it ([phase-gates.md](phase-gates.md#handing-off-to-run)).

### The ROADMAP tasks (only when the project numbers them)

**Asked only when a ROADMAP or stage file holds numbered tasks** — a task line `- [ ] **2.4.1 …` or a table row `| 2.4.1 |` in `ROADMAP.md`, `docs/ROADMAP.md` or `docs/stages/*.md`. A project without one never sees the question. Ask which tasks the story works on, offering the open tasks whose titles match the request:

```
header:   "Roadmap"
question: "Which ROADMAP tasks does this story work on?"
multiSelect: true
options:  the matching open tasks, as "2.4.1 — <title>", at most four
```

The answer is written to `tasks.md` as `roadmap: [2.4.1, 2.4.2]` ([tasks.md](tasks.md)); a task the story covers only in part is still listed — the stage checkpoint asks whether it is fully covered. **Not asked at Fast scale, in instant mode, under `--auto` or headless**: no question, no `roadmap:` written, and the checkpoint maps the story from its title instead. An answer of none writes nothing.

### Fallback (headless or AskUserQuestion unavailable)

When the tool is not callable (some `-p` modes, restricted permission scopes),
fall back to the assertion style — present a single message with a numbered
list of `"I understand X will work as Y. Confirm?"` items. In a headless run
nobody will confirm: state the items as the assumptions taken and continue
([triage.md](triage.md#runtime-dependency-precheck-mandatory-before-standardfull-triage)).

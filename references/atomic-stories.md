# Atomic stories

Read at triage on every route that creates a story — a single create and a batch create — before the proposal is written.

**The definition is BMAD's** (bmad-method 6.12.4: `bmad-build/workflow.md`, *Scope standard*; `bmad-create-epics-and-stories`, steps 2–4), adopted on 2026-11-08. A story is atomic when it holds all six:

1. **One goal.** One cohesive, user-facing goal, even when it spans layers and files. Two or more goals means two or more deliverables of which each could be reviewed, tested and merged as its own pull request without breaking the others. Never count verbs, "and" or nouns: "add validation and show the errors" is one goal; "a dark-mode toggle, JWT login and an admin dashboard" is three. And never split one goal's layers — the table, the endpoint and the screen of one behaviour are one story.
2. **Fits one agent.** The whole story is completable by one agent in one fresh context. The plan's own size warning is the measure ([tasks.md](tasks.md#authoring-ceiling)): past it, propose a split by goal — a proposal the user may override, never a gate.
3. **No forward dependency.** A story builds only on stories that come before it, and never waits for a later one. Goals that depend on each other are ordered so that each needs only those before it.
4. **Only what it needs.** No story that only prepares — "create the database", "write all the models". Each story creates the tables, types and files its own behaviour uses, when it uses them.
5. **Testable acceptance.** Every requirement is independently testable, its edge and error cases included — EARS already asks this ([ears-notation.md](ears-notation.md)).
6. **File churn.** Stories that keep editing the same core files are one story in disguise: consolidate them, unless the split buys risk isolation, an early feedback loop or a context that fits.

## The one-goal check

After the type is classified, read the request for its goals. With one goal nothing changes, and the proposal says nothing about it. With more than one, the single proposal ([triage.md](triage.md#triage-protocol)) carries them in a few lines, so that its confirmation settles them without a question of their own:

- each goal in one line, with why it ships alone;
- the coupling risk if they are split — a shared file, a shared data shape;
- the order, with no forward dependency, and the goal recommended first;
- two answers: **Split** (recommended) — one story per goal, in that order — or **Keep together** — one story for all of them, with the risk said once.

**Split** is a batch whose source is the request: [batch-create.md](batch-create.md) from its consolidated triage on, with one row per goal, one interview and one approval for all of them, and the request, verbatim, as the source every story cross-links. Each story then runs and is validated on its own — the first now, the others in their order.

**Keep together** creates the one story the request asked for and keeps the goals in the proposal line, so a later refine can still split it.

**Under `--auto`, keep the goals together** and log `multiple goals: <the goals>` as an assumption — BMAD's own unattended flow does the same: a run nobody watches delivers what was asked and never narrows it on its own. A layperson is offered the split in the register's words — "do it in three parts, one after the other" — never with the word "story" ([plain-register.md](plain-register.md)).

**The lean route and instant create no story**, and never run this check.

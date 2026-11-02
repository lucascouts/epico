# Plain Register

The seed of `requester.always` and `requester.never` for `level: layperson` — someone who described an outcome, not a mechanism, and showed no tool vocabulary ([triage.md](triage.md#triage-protocol)); the developer's seed is [developer-register.md](developer-register.md). It changes how the Epico **speaks and asks**. It never changes what it builds, what it writes to the story files, or the protocols the sub-agents run: the files keep every internal name, the chat drops them.

## Words that stay in the files

Process words — executor, framework, box, commit, story, checklist, Quality Gates — mean nothing to a beginner, who skims past them; none of them serves the requester.

| Never in the chat | Say instead |
|---|---|
| executor, sub-agent, validator, auditor, tech reviewer, analyst, orchestrator | "I" — the requester is talking to one assistant |
| story, tasks.md, design.md, artifact, requirements, EARS, SHALL, `R1.2` | "the plan", "what we agreed" |
| box, checkbox, `[x]`, close, closing block, census | "done" |
| Red, Green, test-first, refactor, validation command | "I checked that it works" — and show the check |
| commit, branch, worktree, merge, git, snapshot | nothing while it happens; once, at the end: "I saved a copy" |
| Quality Gate, phase, gate, triage, clarify, scale, Fast / Standard / Full, spike | "next step", "before I start" |
| Q1…Qn, quality requirement, legend, catalog ([quality-catalog.md](quality-catalog.md)) | "the checks I ran" — each named by what it checked, never by number |
| engineering level, experiment / tool / project / product, multiple ([engineering-level.md](engineering-level.md)) | how long it needs to last, and what that costs in time — the one price line of the proposal |
| npm, lockfile, package manager, dependency, MCP, tool, hook, headless | name what it does, never what it is |
| the Epico's own words in any language — triage, "the Epico's references", "instant mode", the plan's boxes, run report, gate, stub, assertion, a bare `/epico:epico` (the translated forms live in `assets/jargon-terms.txt`) | nothing — the requester never needs the machinery's own words; say what was done ("I wrote the check first and saw it fail") |

**A word from the left column in visible text is a defect unless the same message carries its legend** — the same class as a typo in an identifier, and reported the same way. The plain words on the right come first; when a term has to stay — the requester will meet it again, in a command, an error or a tutorial — the message carries its legend: a line below it, `*term* — what it means here`, in the requester's language and about this request. A term with no meaning attached is what loses a beginner, not the term itself.

**The closing is checked, not trusted.** Before sending a `layperson` closing, pipe its text to `epico-jargon --max-chars 600` (the term list is `assets/jargon-terms.txt`, drawn from the table above). Exit 1 names each word it found with no legend: rewrite those sentences with the right-column phrasing, or add the term's legend line, and run it again until it exits 0 — then send. A command the requester is told to type goes in backticks, which the check skips. The status lines written between tool calls are checked too, by `hook-legend-guard.sh` when the turn ends: a word they carried with no legend anywhere in the turn blocks the stop once, and the closing adds its legend. One tool call per rewrite is the price; a closing that leaks the process into the chat costs the requester the whole message. A whole English sentence is a different defect, and a legend does not fix it: `hook-language-guard.sh` quotes each one when the turn ends, and the closing says the same things again in the requester's language.

## Decisions the requester is not asked

A layperson is asked none of these: how to commit on `master`, whether to version a data file, which libraries to use, whether to write tests. Each has an answer — in the constitution's `## Defaults` block ([init-mode.md](init-mode.md) writes it) or in this table — and the answer is **taken, and mentioned in one clause**. It is never asked.

| Decision | Default | Mention it as |
|---|---|---|
| git, branch, commit | the current branch; one commit per group, with the plan's own message | "saved" — once, at the end |
| tests | written and run, silently, in every scale | "I checked that it works" |
| data files the program creates | ignored by git | — |
| free-text fields | validated as text | — |
| libraries, package manager | none unless the request needs one; the lockfile decides the manager, else npm | — |
| E2E tool or implementation aid ([preferred-tooling.md](preferred-tooling.md)) | never pause: take the best installed tool and record it in the file | — |

A constitution `## Defaults` block wins over this table; this table wins over a question.

## Gates are one line

A phase gate asks a developer to review a file. A beginner cannot evaluate a requirements document, and approving it without reading it is not a review. For a layperson the gate is **one line in their words** — what will be built, in the order it will appear — with two answers: *go on*, or *change something*. The file is still written, exactly as for anyone else; what changes is what they are asked to read. Every gate counts against the story's question budget ([clarify.md](clarify.md#clarify-protocol)).

## Run and show

Never "run `npm test` yourself" — a layperson may not know how, and the Epico can run it. Run it first, show the result in two or three lines, and only then offer: "want to try it? type `npm start`".

## Explain by example

A new concept gets one example or one analogy, never a definition: "a file you can copy to another computer" beats "persistence", and "a single file that runs anywhere, like a pocket knife" beats "static binary". One per concept, inside the ceiling below — an analogy in every sentence is a lecture. The analogy is what lets someone choose by logic rather than by expertise.

## Keep the promise

"I'll stop after each group" means **one group per turn**. A promise about cadence is kept literally or not made — announcing a stop after each group and then delivering several groups and a question in one message breaks it.

## Ceiling per turn

Visible text per turn stays under **~1,500 characters** — about one phone screen. Anything longer goes to a file and gets one line of pointer. Reports, lists of what was checked and explanations of how something works are files, not messages.

**The closing message stays under ~600 characters** — what to type, what it does, at most two decisions taken alone, and the `Not verified:` sentence; everything else goes to the README. A long closing is the first thing a beginner complains about, whatever else went right. The check is the same call as the jargon check: `epico-jargon --max-chars 600` exits 1 on a closing that is too long, and the closing is cut until it exits 0.

**The ceiling is met by form, not by trimming.** A turn that runs tools writes nothing to the chat between them — the step notes are collected and written to the run report once, at the end, in a single write — and speaks once, at the end. **The report write is not announced either**: "Now the run report, in one write" is a status line like any other, and in a Portuguese chat it is also an English one. Narration between tool calls is what pushes a turn to the ceiling and leaks process words into it; the closing message alone does not.

## What does not change

- Every artifact is still written, in English, with every internal name — [SKILL.md](../skills/epico/SKILL.md#language)
- Everything they read in the chat is in their language — every line, option label and recommended marker; a name or a popular term may stay as it is — with its legend below when the requester may not know it — a whole English sentence may not. The code and its comments stay English; a comment in their language is added on the line below the English one only when they ask ([SKILL.md](../skills/epico/SKILL.md#language))
- Every sub-agent still runs its whole protocol. The register is the orchestrator's voice, never a protocol switch
- A layperson who asks for more — "show me the plan", "I want to pick the library" — gets it, and the register stays plain around it
- **The level never changes the scale.** A layperson who asks for something Full-shaped gets Full: the same files, with every gate in one line
- The profile is re-read from the answers ([clarify.md](clarify.md#clarify-protocol)): someone who answers in tool vocabulary is a `developer` from that point on

# Lean Route — `experiment` work, done directly

Loaded when triage reads the engineering level as `experiment` ([triage.md](triage.md#triage-protocol), step 3a), and by `/epico:epico instant`, which enters here without reading the level ([instant-mode.md](instant-mode.md)). **From here this file replaces the rest of triage, Clarify, the phases and Run mode.**

**Why it exists.** An `experiment` buys the security floor and nothing a plan keeps: nobody maintains it, so nobody reads its story. The same model, given only the floor and the check below, delivers what a Fast `experiment` story delivers — the atomic save, the corrupted file, the README and the commit are what it would otherwise miss, not the plan or the questions — at a fraction of the clock, the tokens and the questions.

## What it does not write

**No story.** Nothing under `.epico/stories/`, no `epico-next-number`, no `tasks.md`, no proposal to confirm, no sub-agent, no `epico-close` or `epico-progress`. The work is the deliverable and the closing message is its record. A thing nobody will maintain has no plan for anyone to read later.

**Never inside an existing story.** A run of story NNN follows [run-mode.md](run-mode.md) whatever its level; this route is an entrance for new work only.

## Before the work

- **Who is asking** is still read from the request ([triage.md](triage.md#triage-protocol)), and it still sets the register the chat is written in: for a `layperson`, plain words and a term explained the first time it appears ([plain-register.md](plain-register.md) — read it only when the reading is `layperson`).
- **The model is suggested once, never asked.** When this session is not on Sonnet, the first line — before any work — says so: Sonnet does this work at the same quality for about a third of the cost; `/model sonnet` switches this session and also makes Sonnet the default (for this session only: open `/model`, pick Sonnet, press `s`); `claude --model sonnet` starts a new session already on it, for that session alone. Then the work starts. Under `--auto` or headless the line is left out.
- **One line names the level and how to leave it** — never a gate: *"I'll treat this as something to try out and throw away; if you will keep using it, say so and I'll build it to last."* In the requester's language and register.
- **Ask only when the answer changes what is built** — an operation the request leaves out, a field it does not name. Any other open choice is taken as the sensible default and named in the closing. The interface — menu, prompts, messages, README — speaks the language the request was written in, stated on its line; the English rule is about artifacts ([SKILL.md](../skills/epico/SKILL.md#language)).

## The floor — every program, however small

The [security floor](quality-catalog.md#the-security-floor--five-items-no-level-drops), plus the commit:

- **Runtime** — a supported version declared where a tool reads it (`engines` in package.json, the `go` line of go.mod, `requires-python`, `rust-version`, or `.tool-versions`).
- **Secrets** — none in the tree.
- **README** — how to run it and how to check it, two lines at least.
- **Dependencies** — prefer none; any added has no known vulnerability. No dependencies is a verdict, not a failure.
- **Data integrity**, when the program writes a file it reads back — written through a temporary file renamed over the target; a missing file and a corrupted file each start the program without a crash and without overwriting the original. A file that parses but has the wrong shape counts as corrupted; a corrupted file is set aside under a timestamped name, never over an earlier one; a save that fails says so. Tests prove these cases.
- **Commit** — when the folder is a git repository with an identity, commit the work, staging files by name. With no repository or no identity, say so in the closing instead; git is never a question for a `layperson`.

## Done means the check passed

Before the work is called done: **automated tests for what was built — one for every rule the request states about bad input, end of input or the data file, and for each floor case** (they are the cases a run that skips the plan forgets first), then **the project's whole check** — tests, plus lint or type check where the stack has one — **run and fixed until it passes**. Run the program once the way the requester will.

## The closing

- How to run the program and how to run the check, in a line or two.
- **Every decision taken alone that reduces protection or documentation**, one line each with what keeping it would have cost — the requester finds out by reading, never by being bitten. A choice between equivalent means is not listed.
- **When the request is plainly bigger than an experiment** — several integrated surfaces, or something others will depend on — one line says so, and the work proceeds anyway: *"This looks bigger than a throwaway; say the word and I'll redo it as something to keep."* The line is a note, never a gate.

#!/usr/bin/env bats
# Policy test for the reports-by-artifact contract.
#
# WHAT THIS SUITE PINS. Reports-by-artifact turns the Validator's and Auditor's
# verdicts into files (.draft/validation-report.yaml, .draft/audit-report.yaml)
# written BEFORE the textual summary, makes validate-mode conclude from those
# files rather than from the agent's final message, and gives the Tech Reviewer
# Bash restricted to measurement. All of that is prose in agent definitions and
# mode references — nothing executable — so the contract survives future edits
# only if a test names it. This file is that test.
#
# FIXTURES ARE THE REPO FILES THEMSELVES. Every case is a pure content
# assertion on agents/*.md, references/validate-mode.md and
# references/run-mode.md — no temp dirs, no mutation, so no mktemp/teardown.
#
# ASSERTIONS ARE BEHAVIOR-LEVEL, NOT SENTENCE-PINNED. Cases assert that a
# fact is stated (a filename, a grant, an ordering, a prohibition), matched
# case-insensitively on flattened text where a sentence may wrap — never an
# exact sentence, which would make every future rewording a false Red.
#
# ...BUT THEY PIN POLARITY, NOT CO-OCCURRENCE. Behavior-level is not
# direction-blind. A bare window pattern like `the run[^.]{0,40}fail` is
# satisfied by "the run is **not** failed" exactly as by the real row, so it
# stays green through an inversion of the rule it exists to guard. A
# directional claim therefore carries its polarity token INSIDE the match
# (`is failed`, `is a protocol violation`, `is your own store`,
# `never … respawn`), leaving no gap for a negation to slip between the anchors.
# Tighten only what is measured first: scope the section, count the candidate
# spans, and confirm the phrase is the one the rule's own name already uses —
# otherwise the pin becomes the sentence-pinning this header forbids above.
#
# Each such pattern is written out, never routed through a shared polarity
# helper. A helper that rejected a negation in the window before the match would
# false-Red on correct prose right here: auditor.md's memory clause reads "is
# not a second path in the code under audit — it is your own store", so a
# negation sits one clause ahead of the match by design.
#
# WHEN THE NEGATION PREFIXES A QUANTIFIER there is no polarity token to move
# inside. `is failed` works because the negation splits two anchors; `one`
# offers no such gap — it is a substring of every phrase that reverses it
# (`more than one`, `not just one`, `one or more`), so a pattern pinning `one`
# is satisfied by its own negation. No pattern repairs that, so the repair is
# not a pattern. It is three assertions and a prose rule: the rule carries a
# token a reversal BREAKS rather than contains (`never a second`), the case
# counts the sites that state it, and a third assertion pins the rule's
# CONSEQUENCE — one request, then the run is failed — because a document
# licensing repeats cannot also say that. An inline negated grep naming the
# claim's own modifiers stands BESIDE them, for the one vector only it catches
# rather than as the sanctioned form, and never as a generic negation guard,
# for the reason the paragraph above gives. All four stand in `an absent or
# unparseable report is re-requested once via SendMessage, then the run is
# failed`, which argues each where it stands.
#
# A NEGATED ASSERTION MUST NOT REST ON BEING LAST. Bash exempts a `!`-inverted
# command from errexit, so anywhere but the final statement of an @test its
# non-zero status is discarded and the assertion is inert — green whatever the
# file under test says: `! true` followed by one more assertion passes, while
# `if true; then return 1; fi` in that same slot fails. The sanctioned shape is
# therefore `if …; then return 1; fi`, which is what every negated assertion in
# this file uses. The subshell `( ! … )` also survives being moved and is not
# used for diagnostics alone — bats names the `return 1` line for the `if` and
# only the `@test` line for the subshell, pointing at the case instead of the
# assertion.
#
# THAT RULE IS ENFORCED, NOT ADVISED, and it is one of the few sentences in
# this header that may say so. The negated-assertion lint in
# tests/assertion-hygiene.bats scans every tests/*.bats and names each offender
# as file:line; it admits no position exemption, so sitting last is not a
# defence either. The sites are not listed here: a list has to be remembered,
# and the lint is re-derived on every run.
#
# WHERE THE POLARITY RULE DOES NOT HOLD, named rather than quietly excepted: a
# convention the file contradicts gets read as an invariant, which is worse
# than no convention. THIS HEADER IS NOT WHERE THOSE SITES ARE NAMED. A
# hand-kept list of exceptions is the same instrument as the hand-kept list of
# negations above, with the same failure: its entries go on reading as open
# after the sites are closed.
#
# THE ALLOWLIST TABLE IN tests/assertion-hygiene.bats IS THE LIST. One row per
# `file:pattern`, each stating the inversion applied, the colour observed and
# every residual left open; and two census cases there keep the table and the
# suite in step in both directions, so a pattern cannot exist unreviewed and a
# row cannot outlive its pattern: every window pattern in tests/ carries an
# allowlist row, and no row names a pattern tests/ no longer contains. Read it
# by verdict rather than from a sentence here — BOUNDED TO THE TABLE, because
# that file's planted fixtures write rows of their own and a whole-file grep is
# answered by them:
#
#   sed -n '/^allowlist_table() {/,/^ROWS$/p' tests/assertion-hygiene.bats \
#     | command grep '^VERDICT' | sort | uniq -c
#
# PINNED and ALLOWED are the two verdicts that say a site is sound;
# DIRECTION-BLIND says the site was checked and failed, and names the repair
# still owed. The command is written here rather than a row count, because the
# count changes as rows are added.
#
# WHAT THE CENSUS CANNOT SEE, so that a green one is not read for more than it
# says. It recognises the window shape `A[^.]{0,N}B` and nothing else. Tighten
# a pattern out of that shape — as several pins in this file did, trading the
# window for an adjacency bound — and it leaves the census with it, so no row
# can hold its measurement; that evidence lives in the case's own comment and
# nowhere else. And the census checks that a row EXISTS, never that its
# sentence is TRUE: whether a pattern really survives an inversion depends on
# the prose it reads, which no machine here judges.
#
# A pattern naming only a file or a field (`audit-report.yaml`, `verdict`)
# makes no directional claim and so has no polarity to pin — the first
# paragraph governs those. `measurement` IS NOT IN THAT LIST: the rule states
# its own direction in words the pattern can hold (`for measurement only`),
# pinning them Reds on `Bash is not limited to measurement`, and the bare topic
# word stays green through the same inversion. That pin and its negation guard
# stand in `tech-reviewer's Bash is measurement-only and never mutates`. A word
# is a topic only until somebody checks it, so that class is a finding and
# never a guess.
#
# WHAT IN THIS HEADER IS UNDER TEST, AND WHAT IS NOT — the distinction matters
# more than either half, because a partial guard described as none misleads
# exactly as much as none described as a guard.
#
#   ENFORCED, each by a named case in tests/assertion-hygiene.bats: the
#   negated-assertion rule; the window-pattern rule, in both directions (every
#   window pattern carries an allowlist row, and no row names a pattern tests/
#   no longer contains); the shape of a row (file, pattern, verdict and a
#   justifying sentence); and a guard over those four against silent removal,
#   which reds on a `skip` anywhere in that file and on any rostered case being
#   renamed away. Its limits are written into its own comment rather than left
#   here — a commented-out or gutted case is caught for the census case alone,
#   and no guard inside a file can outlive that file.
#
#   GUIDANCE, held by nothing but the next author reading it: behavior-level
#   over sentence-pinned, fixtures being the repo files themselves, a polarity
#   token inside the match rather than a shared negation helper, and every
#   verdict the allowlist records. Dropping one of these turns nothing Red.
#
# The grant-set cases are least-privilege pins: Write and Bash land on exactly
# the named agents, and Edit moves nowhere. The Edit case is a GREEN PIN —
# correct today, present so a grant that "comes along for the ride" reddens
# deliberately.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VALIDATOR="$PLUGIN_ROOT/references/validation-protocol.md"
  AUDITOR="$PLUGIN_ROOT/agents/auditor.md"
  TECH_REVIEWER="$PLUGIN_ROOT/agents/tech-reviewer.md"
  VALIDATE_MODE="$PLUGIN_ROOT/references/validate-mode.md"
  RUN_MODE="$PLUGIN_ROOT/references/run-mode.md"
  # The Tech Reviewer prompt template lives in its own appendix, loaded only
  # when a sub-task carries a technology boundary. run-mode.md keeps a pointer.
  TECH_REVIEW="$PLUGIN_ROOT/references/run-tech-review.md"
}

# The tools: line inside the frontmatter block only — a tool named in prose
# ("do not use Write") must never satisfy a grant assertion.
frontmatter_tools() {
  awk 'NR==1 && $0=="---" {inb=1; next}
       inb && $0=="---" {exit}
       inb && $0 ~ /^tools:/ {print; exit}' "$1"
}

# Word-boundary match without \b (a GNU-ism): Write must not match WebSearch,
# Bash must not match a hypothetical BashOutput.
grants() { # $1 = agent file, $2 = tool name
  frontmatter_tools "$1" | command grep -qE "(^|[^A-Za-z])$2([^A-Za-z]|$)"
}

# Flatten to one line so a fact split across a soft wrap still matches.
flat() { tr '\n' ' ' < "$1"; }

# Lines of one markdown section: from the first heading matching $2 to the
# next heading matching $3 (exclusive).
md_section() { # $1 = file, $2 = start regex, $3 = end regex
  awk -v start="$2" -v end="$3" '
    !inb && $0 ~ start {inb=1; next}
    inb && $0 ~ end {exit}
    inb {print}' "$1"
}

# The sorted list of agents whose frontmatter grants a tool — the shape the
# grant-set pins compare against, so an agent ADDED to the grant is as loud as
# one removed.
agents_granting() { # $1 = tool name
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    if grants "$f" "$1"; then
      basename "$f" .md
    fi
  done | sort
}

# --- Validator report contract -----------------------------------------------

@test "the Auditor runs the validation protocol as Part 1, and holds the Write it needs" {
  # One spawn validates, then audits: the protocol is a reference the Auditor
  # reads, and its report is the Auditor's first writable path.
  grants "$AUDITOR" "Write"
  command grep -q 'validation-protocol.md' "$AUDITOR"
  flat "$AUDITOR" | command grep -qiE 'on a validation `fail`, stop there'
}

@test "validator names .draft/validation-report.yaml, its verdict, and the write-before-summary ordering" {
  command grep -q 'validation-report\.yaml' "$VALIDATOR"
  # The file carries the overall verdict, not only per-task lines.
  flat "$VALIDATOR" | command grep -qi 'verdict'
  # The write precedes the textual summary — the ordering is the whole
  # point, because a summary-first agent can still end on an intermediate line
  # with no file written.
  #
  # THE PROSE CARRIES A TOKEN TO PIN. A rule worded `, before composing any
  # textual summary,` and pinned by `before[^.]{0,160}summar` makes `before`
  # the anchor AND the polarity at once, so a negation has nowhere to go but in
  # FRONT of it, where the window never looks: `never before composing any
  # textual summary` stays GREEN under a rule that says the opposite. No scope
  # and no count reaches that; only different prose does, so the rule reads
  # `never composing … first`.
  #
  # WHAT IS PINNED IS `never composing … first`, not the sentence. The negation
  # is ADJACENT to the verb it governs, so that mutation has no slot:
  # `never before composing` puts a word between the two and Reds, as does
  # dropping `never`, as does `first` -> `last`, as does deleting the clause
  # outright.
  #
  # THE ANCHORS ARE UNIQUE IN THE FILE: `compos` occurs exactly once here and
  # `first` exactly once, both inside this clause, so no neighbouring span can
  # answer for it. Named by content rather than by line, because line numbers
  # drift.
  #
  # `summar` IS DELIBERATELY NOT AN ANCHOR, and the leash is 60 characters. A
  # faithful rewording that renames the object (`never composing the prose
  # reply for the human first`) drops the word `summary` entirely and must stay
  # GREEN. What the leash proves is that the prohibition governs the composing,
  # and `composing` is this document's verb for the summary alone.
  # The `(^|[^A-Za-z])` guard is not decoration: `whenever composing` ends in
  # `never composing`. Nor is the ` +`: `flat` turns a newline into a space and
  # leaves any trailing one alone, so a reflow breaking between the two words
  # of the token hands the pattern TWO spaces and a single-space literal
  # false-Reds. Only whitespace can sit in that slot, so widening it admits no
  # reversal.
  #
  # THE RESIDUAL, named rather than left to be found: the rule restated in the
  # positive form — `before composing any textual summary` — false-Reds here.
  # That trade is taken knowingly: a claim whose polarity cannot be matched
  # without matching most of a sentence is stated in prose that carries a
  # polarity token, and the token is then required. A reader who wants the
  # positive form back has to keep the prohibition with it.
  flat "$VALIDATOR" | command grep -qiE '(^|[^A-Za-z])never +composing[^.]{0,60}first'
}

@test "validator carve-out — any other write is a protocol violation, .draft/ created on demand" {
  # The no-modify rule narrows to a carve-out, it does not disappear.
  # The assertive frame `is a` is part of the match: the definition writes "Any
  # other write is a protocol violation" verbatim, and the inversion breaks it.
  flat "$VALIDATOR" | command grep -qiE 'is a protocol violation'

  # Fast/spike stories have no .draft/ until someone makes one, and THIS FILE
  # SAYS SO TWICE — the protocol step and the Rules bullet. `flat … | grep -q`
  # is answered by either span alone, so dropping the allowance from one site
  # would leave a bare `-q` GREEN. Counting the spans Reds every one-site
  # removal. The count SUBSUMES a `-q` — 2 spans implies at least one — so
  # keeping both would be a second assertion that cannot fail while the first
  # passes.
  #
  # COUNTED OVER FLATTENED TEXT, because the obvious `grep -c` is wrong twice
  # over: it counts matching LINES, so over `flat`'s single line it answers 1
  # however many spans exist, and over the raw file it answers 2 only while
  # both spans keep to a line of their own — a reflow that puts a newline
  # inside a span changes the raw count with not a word changed. Spans over
  # flattened text is the tolerance every other assertion in this file is
  # flattened for.
  #
  # EXACTLY TWO, AT A REAL COST: a legitimate THIRD statement of the allowance
  # false-Reds here. `-ge 2` Reds every removal just as well and buys that
  # third span silence; the exactness is taken deliberately, because
  # DUPLICATION is half of what makes a site like this blind, so a third span
  # belongs in front of a reader rather than under a green. It is the trade the
  # grant-set pins below take too — an addition as loud as a removal.
  #
  # WHAT THE COUNT DOES NOT GUARD: the DIRECTION. The permission reversed at
  # BOTH spans — `never creating .draft/ on demand` — keeps the count at two,
  # because the negation PREFIXES the anchor `creat`: no count and no scope
  # reaches it, only different prose does, and that prose is pinned in the
  # assertion below. The count stays because the two answer different
  # questions — this one whether the allowance is STATED at both sites, that
  # one in which DIRECTION — and neither subsumes the other: the both-spans
  # reversal keeps this count at 2 while Redding the pin, and either span
  # deleted outright Reds both.
  #
  # The count is captured before it is compared, not inlined into `[ "$(…)" ]`,
  # and that is the census talking rather than taste: the window-pattern walker
  # keys a row on the WHOLE quoted span, and inlining puts the pattern inside a
  # `"…"` that runs from `|` to `)`, keying a row nobody would recognise and
  # orphaning the one this pattern already has.
  spans=$(flat "$VALIDATOR" | command grep -oiE 'creat[a-zA-Z]*[^.]{0,80}\.draft' | wc -l)
  [ "$spans" -eq 2 ]

  # ...AND IN WHICH DIRECTION. A participle like `, creating `.draft/` on
  # demand.**` is reversed by `, never creating `.draft/` on demand.**` — a
  # negation in FRONT of the anchor, where no window looks. So the Rules bullet
  # uses the frame the protocol step uses, the shape `the run is failed` uses:
  # `is part of this step` SPLITS under `is NOT part of this step`. The bullet
  # reads `, and creating `.draft/` on demand is part of it.**`, and both agent
  # files carry the identical wording.
  #
  # ANCHORED AFTER `.draft`, NEVER BEFORE IT, which is arithmetic rather than
  # taste: `[^.]` cannot cross the full stop inside `` `.draft/` ``, so a
  # `creat…is part of` window could never reach the verb it needs. `is part of`
  # occurs exactly twice in this file, both inside the carve-out, so no
  # neighbouring sentence can answer for either span.
  #
  # COUNTED, for the reason the span count above is: a `-q` is answered by
  # whichever span survives. Reversed at both spans the count is 0, at either
  # span alone it is 1 — RED every time. Residual, named and accepted: a
  # rewording that drops the frame (`so this step creates `.draft/` itself
  # whenever it finds none`) false-Reds — the prose carries the token or the
  # direction goes unpinned.
  allowed=$(flat "$VALIDATOR" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 2 ]
}

@test "validate-mode Validator prompt template mirrors the report file" {
  # The duplicated template drifts unless it changes together with the agent
  # definition.
  #
  # A FILENAME IS NOT A RULE. Every inversion of every rule stated around
  # `.draft/validation-report.yaml` keeps the filename, so a mirror case that
  # asks only for the path mirrors nothing: the carve-out reversed to `any other
  # write is **not** a protocol violation`, the ordering reversed to `as the
  # FIRST step after composing any textual summary`, and the `.draft/` allowance
  # reversed to `never creating `.draft/` on demand` all keep it. Those are the
  # three rules the agent-definition cases above pin, so the three pins land
  # HERE rather than in cases of their own.
  #
  # SCOPED TO THIS TEMPLATE, and the scope is load-bearing rather than tidy:
  # each phrase below occurs once per template in references/validate-mode.md,
  # so a whole-file grep is answered by the Auditor's copy while the
  # Validator's says the opposite.
  #
  # THE TRAILING SPACE IN `^## ` IS NOT LOAD-BEARING HERE: this section holds
  # no heading of any depth and no line beginning `#` — the YAML comments
  # inside it all sit behind a `>` — so `^## `, `^##` and `^#` capture the same
  # lines. The form is kept for consistency with the neighbouring cases.
  sec="$(md_section "$VALIDATE_MODE" '^## Validation — Part 1' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  printf '%s\n' "$flatsec" | command grep -q 'validation-report\.yaml'

  # THE CARVE-OUT, IN THE DEFINITION'S OWN FRAME, which is the whole of what
  # "mirrors" is supposed to mean: `is a protocol violation` is the phrase
  # agents/validator.md writes verbatim and the validator carve-out case above
  # already pins there. No negation guard rides beside it and none is needed —
  # the assertive frame SPLITS under every reversal English writes for it
  # (`is not a protocol violation`, `is never a protocol violation`), so
  # reversing it in this template alone, in both templates, or deleting the
  # clause all Red, while rewording the surrounding sentence with the frame
  # standing stays GREEN.
  printf '%s\n' "$flatsec" | command grep -qiE 'is a protocol violation'

  # THE ORDERING, PINNED IN THE TOKEN THIS COPY CARRIES rather than by
  # rewriting it to match the definitions. The agent files write `never
  # composing any textual summary first`; this copy reads `as the LAST step
  # before composing any textual summary` — not a contradiction, the same
  # ordering stated with its own token, and that token can be pinned: `last`
  # and `before` are BOTH polarity, and every reversal loses at least one of
  # them — `FIRST step after`, `LAST step after`, and the clause dropped for a
  # bare `after composing any textual summary` Red, as does the clause deleted
  # outright.
  #
  # ONE SPAN IN THE SCOPE, which is what lets a `-q` reach a single-site
  # inversion. The leashes are 40 and 40: the real gaps are 6 characters here
  # (` step `) and 27 at the procedure-section copy this same pattern reads two
  # cases below (`** step of their protocol, `), so 40 is rewording slack, not
  # reach. The `(^|[^A-Za-z])` boundary keeps `ballast` and `lastly` out.
  # `compos` rather than `summary` because a faithful rewording renames the
  # object, and the procedure-section copy already writes `prose` where these
  # two write `textual summary`.
  printf '%s\n' "$flatsec" \
    | command grep -qiE '(^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos'

  # ...AND A WINDOW CANNOT CARRY A NEGATION PARKED IN FRONT OF IT:
  # `never as the LAST step before composing any textual summary` keeps both
  # anchors, reverses the rule, and leaves the match above GREEN — so the
  # negation is refused where it can reach the ordering, and REFUSED RATHER
  # THAN REPAIRED IN THE PROSE, which keeps three sites from being rewritten to
  # match a fourth.
  #
  # The hop `((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3})
  # {0,3}` is the file's own hedge vocabulary plus the two articles this
  # sentence puts between a negation and `last`. It Reds on all four reversals
  # that keep the anchors — `never as the LAST step`, `not as the LAST step`,
  # `not the LAST step`, `no longer the LAST step` — and stays SILENT on every
  # scope it runs in: this template, the Auditor's, and `## Validate Mode
  # Procedure`, whose `last` tokens include `reads last week's `pass`` and
  # `writes that file as its last step`. Silent too on the rewordings the pin
  # above admits (`as the LAST step of the protocol, before composing ...`,
  # `as the **last** thing they do, before composing any prose`).
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3}){0,3}last'
  then
    echo "the write-before-summary ordering is stated with a negation on it — the template reverses the rule its definition states"
    return 1
  fi

  # THE `.draft/` ALLOWANCE, the third copy. Fast and spike stories have no
  # `.draft/`, so the agent makes one rather than reporting its absence, and
  # this template states that rule in the same sentence as the write.
  #
  # SAME PATTERN AS THE AGENT-DEFINITION TWIN, one key, and `-q` rather than
  # the count that case takes: the definitions state the allowance TWICE per
  # file and any survivor answers a `-q` there, while this scope holds exactly
  # one `creat`, so a count of 1 would assert nothing the `-q` does not.
  printf '%s\n' "$flatsec" | command grep -qiE 'creat[a-zA-Z]*[^.]{0,80}\.draft'

  # ...AND THE DIRECTION, WITHOUT TOUCHING THE PROSE. The negation PREFIXES the
  # anchor `creat` — `never creating `.draft/` on demand` keeps the span and
  # reverses the permission, which a count cannot reach. The definitions'
  # scope is a whole file; this one is a single template with a single `creat`
  # in it, so an adjacency guard reaches what a count cannot. It Reds on `never
  # creating `.draft/` on demand` and on `do not create `.draft/` yourself`, and
  # stays SILENT on the unmutated section and on the rewording `you create
  # `.draft/` yourself when the story has none`.
  #
  # A reversal that parks the negation AFTER the anchor (`though creating
  # `.draft/` on demand is forbidden`) passes both assertions above; it is
  # caught below, by the same prose frame the definitions use — no new
  # mechanism and no wider guard. What remains is a rewording that renames the
  # verb (`making `.draft/` yourself`), which false-Reds — a trade taken to keep
  # one key with the twin rather than widening the anchor on this copy alone.
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?creat'
  then
    echo "the template's .draft/ allowance is stated with a negation on the verb — the permission is reversed"
    return 1
  fi

  # ...AND THE AFTER-THE-ANCHOR REVERSAL. `though creating `.draft/` on demand
  # is forbidden` keeps the `creat` span and satisfies the guard above, because
  # that guard reaches a negation only immediately IN FRONT of the verb.
  #
  # CLOSED THE WAY THE DEFINITIONS CLOSE IT, by prose rather than by
  # enumeration: the permission carries a frame a negation must SPLIT instead
  # of prefix — `in the story directory — creating `.draft/` on demand is part
  # of that step, since fast and spike stories have none.` — the same `is part
  # of` frame agents/validator.md writes, in both templates identically.
  # Widening the negation guard is the alternative and is refused: enumerating
  # the ways English says "no" is not the mechanism.
  #
  # SAME KEY AS THE DEFINITION TWIN — one row, `\.draft[^.]{0,40}is +part of` —
  # and ANCHORED AFTER `.draft` for that case's arithmetic: `[^.]` cannot cross
  # the full stop inside `` `.draft/` ``, so a `creat...is part of` window could
  # never reach the verb it needs. COUNTED rather than `-q`, at 1 per template
  # section, because the count is what makes the SCOPE assert something: the
  # file holds two spans, one per template, and the defect guarded against is a
  # copy that says the opposite of its twin.
  #
  # It Reds on `though creating `.draft/` on demand is forbidden`, on the frame
  # negated in place (`is NOT part of that step`), on `never creating` (RED here
  # and at the guard above) and on the clause deleted outright; it stays GREEN
  # on `creating `.draft/` when you find none is part of that step` and on the
  # sentence reflowed across lines without a word changed.
  #
  # The count is captured before it is compared for the census's reason, the
  # same one the twin states: inlining the pattern into `[ "$(...)" ]` keys a
  # row on a span running from `|` to `)` and orphans the row this pattern has.
  allowed=$(printf '%s\n' "$flatsec" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 1 ]
}

# --- Auditor report contract -------------------------------------------------

@test "auditor frontmatter grants Write" {
  grants "$AUDITOR" "Write"
}

@test "auditor names .draft/audit-report.yaml, its verdict, and the write-before-summary ordering" {
  command grep -q 'audit-report\.yaml' "$AUDITOR"
  flat "$AUDITOR" | command grep -qi 'verdict'
  # Same rule and the same pin as the Validator's — the two files state this
  # step in one another's words, so a divergence cannot open here unnoticed.
  # Pinned on THIS file rather than inherited from the twin: `never` dropped,
  # `never before composing`, `first` -> `last` and the clause deleted each Red
  # on agents/auditor.md with agents/validator.md untouched, and the object
  # reworded stays GREEN. Why the negation sits adjacent, why `summar` is not
  # an anchor and what that costs are argued once, on the validator twin above.
  flat "$AUDITOR" | command grep -qiE '(^|[^A-Za-z])never +composing[^.]{0,60}first'
}

@test "auditor carve-out — any other write is a protocol violation, .draft/ created on demand" {
  # Same assertive frame as the Validator's, and for the same reason.
  flat "$AUDITOR" | command grep -qiE 'is a protocol violation'

  # Same count and the same two sites — the protocol step and the Rules
  # bullet, in the Validator's own words — pinned on THIS file rather than
  # inherited from the twin: the bullet-only removal and the step-only removal
  # each Red here, as does either span deleted outright, and the both-sites
  # rewording stays GREEN. The both-sites REVERSAL stays green here too, and
  # always will: it keeps both spans and only turns them round, which is the
  # DIRECTION — pinned in the assertion below. Why the count is taken over
  # flattened text, why `-eq` rather than `-ge`, and why it is captured before
  # it is compared are all on the validator twin above — one decision, not
  # two, so it is argued once.
  spans=$(flat "$AUDITOR" | command grep -oiE 'creat[a-zA-Z]*[^.]{0,80}\.draft' | wc -l)
  [ "$spans" -eq 2 ]

  # ...AND IN WHICH DIRECTION, the same token, the same count and the same two
  # sites as the Validator's — the two files state this rule in one another's
  # words. Pinned on THIS file rather than inherited: the carve-out reversed at
  # BOTH spans counts 0 and Reds, at either span alone counts 1 and Reds, and
  # the rewording that keeps the frame at both spans stays GREEN. Why the
  # pattern anchors AFTER `.draft`, why `is part of` carries the direction
  # where the participle could not, and what the token costs are argued once
  # on the validator twin above.
  allowed=$(flat "$AUDITOR" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 2 ]
}

@test "validate-mode Auditor prompt template mirrors the report file" {
  # The Validator's twin, phrase for phrase, and every decision behind the four
  # pins below is argued once on that case rather than twice here: why the
  # scope is load-bearing, why the carve-out frame needs no guard, why the
  # ordering is pinned in the token this copy already carries instead of being
  # rewritten to match the definitions, and what the two `.draft/` residuals
  # cost. PINNED ON THIS SECTION rather than inherited from the twin, because
  # this scope is longer than the Validator's and holds prose the Validator's
  # does not, so a divergence could open here and nowhere else.
  #
  # Per scope: `is a protocol violation` 1 span, the ordering window 1 span,
  # `creat` 1 occurrence, and no hits for either negation guard on unmutated
  # prose. Section boundary: `^## `, `^##` and `^#` capture the same lines, so
  # the trailing space decides nothing here either. Each rule reversed or
  # deleted alone Reds; the surrounding template text reworded with all three
  # rules standing stays GREEN.
  sec="$(md_section "$VALIDATE_MODE" '^## Audit — Part 2' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  printf '%s\n' "$flatsec" | command grep -q 'audit-report\.yaml'
  printf '%s\n' "$flatsec" | command grep -qiE 'is a protocol violation'
  printf '%s\n' "$flatsec" \
    | command grep -qiE '(^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos'
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3}){0,3}last'
  then
    echo "the write-before-summary ordering is stated with a negation on it — the template reverses the rule its definition states"
    return 1
  fi
  printf '%s\n' "$flatsec" | command grep -qiE 'creat[a-zA-Z]*[^.]{0,80}\.draft'
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?creat'
  then
    echo "the template's .draft/ allowance is stated with a negation on the verb — the permission is reversed"
    return 1
  fi

  # ...AND THE AFTER-THE-ANCHOR REVERSAL, the Auditor's copy of it. The
  # argument is the Validator case's, one screen up, and so is the prose
  # frame: `is part of that step` is a frame a negation must SPLIT, where the
  # guard above reaches only a negation parked in FRONT of `creat`. Both
  # templates carry the identical wording, which is what keeps one key across
  # the four sites this pattern reads.
  #
  # Pinned on this section too: `though creating `.draft/` on demand is
  # forbidden`, `is NOT part of that step`, `never creating` and the clause
  # deleted each count 0 and Red; the rule-preserving rewording stays GREEN.
  allowed=$(printf '%s\n' "$flatsec" | command grep -oiE '\.draft[^.]{0,40}is +part of' | wc -l)
  [ "$allowed" -eq 1 ]
}

@test "neither report template names an agent memory directory" {
  # 0.12.0 dropped `memory: project` from the Analyst and the Auditor: it
  # silently granted Write/Edit, wrote `.claude/agent-memory/` into the user's
  # repository and duplicated ai-memory. A carve-out naming a memory directory
  # would now point at a store no agent has.
  aud="$(md_section "$VALIDATE_MODE" '^## Audit — Part 2' '^## ')"
  val="$(md_section "$VALIDATE_MODE" '^## Validation — Part 1' '^## ')"
  run command grep -qi 'memory director' <<< "$aud$val"
  [ "$status" -eq 1 ]
}

# --- The orchestrator consumes the files ------------------------------------

@test "validate-mode removes the stale report file before spawning" {
  # A leftover from a prior run must never read as a fresh verdict.
  #
  # A LINE MENTIONING `stale` AND A REPORT FILE PINS NEITHER HALF OF THE RULE.
  # Line-based co-location keeps out `## Index Refresh`, which calls a stale
  # INDEX "a stale rendering", but the deletion verb reversed at all three sites
  # (`Delete`/`delete`/`delete that agent's` -> `Keep`/`keep`/`never delete
  # that agent's`) together with `Before each spawn` -> `After each spawn`
  # keeps both words, on prose that then states the opposite rule twice over.
  #
  # SCOPED RATHER THAN WIDENED. Both sites sit inside `## Validate Mode
  # Procedure` — step 3 and the `### Before the spawn, delete both stale
  # report files` heading — and the decoy sits in `## Index
  # Refresh`, so the section boundary excludes it by construction. The decoy
  # reworded with the rule untouched stays GREEN.
  #
  # THE TRAILING SPACE IN `^## ` IS LOAD-BEARING HERE: `^## ` runs past the
  # `###` subsections to `## Status Transition`, the stale-report heading among
  # them, while `^##` stops at the first `###` — dropping the heading site
  # entirely and Redding on unmutated prose.
  sec="$(md_section "$VALIDATE_MODE" '^## Validate Mode Procedure' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  # HALF ONE, THE VERB, AND IT IS COUNTED. The rule stands at two sites, so
  # asking whether it is stated ANYWHERE is answered by either survivor — a
  # partial removal would pass. Reversing the verb at any one site takes the
  # count to 1 and Reds. Why the count is taken over flattened text with
  # `grep -o | wc -l` rather than `grep -c`, why `-eq` rather than `-ge`, and
  # why it is captured before it is compared are argued once on the validator
  # carve-out twin above — one decision, not two.
  #
  # `remov` RIDES BESIDE `delet` because this document calls the act by both
  # names — the stale-report paragraph writes "Step 3 removes …" of the very
  # deletes its heading mandates, and this case's own
  # name says `removes`. A pin that Redded when the prose adopted the case's
  # own word would force prose to be rewritten for the grep. The widening
  # cannot raise the count: no `remov` in the section sits within reach of `stale`.
  # The 40-character leash is rewording slack, not reach — the widest real gap
  # is 11 (`delete both stale`).
  deletes=$(printf '%s\n' "$flatsec" | command grep -oiE '(delet|remov)[a-z]*[^.]{0,40}stale' | wc -l)
  [ "$deletes" -eq 2 ]

  # ...AND A COUNT CANNOT CARRY THE DIRECTION. `never delete that agent's
  # stale report file` is the rule reversed and still counts three, because
  # the negation PREFIXES the anchor — the same shape that leaves the
  # `.draft/` carve-out open two cases above. Refused here instead, and
  # ADJACENT so that a negation reaching the verb Reds while prose that merely
  # contains one does not: the stale-report subsection's own "Deleting what is
  # not there is a no-op, never an error" does not trip it, nor does "**Never
  # respawn silently.**" further down the same section.
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?(delet|remov)'
  then
    echo "the stale report file's deletion is stated with a negation on the verb — the rule is reversed"
    return 1
  fi

  # HALF TWO, THE ORDERING, pinned separately so a future reader sees which
  # half broke: `Before each spawn` -> `After each spawn` keeps every word the
  # count above reads and reverses the rule's other half. What is pinned is
  # the ordering word sharing a sentence with BOTH the spawn and the delete —
  # one span in the section, the stale-report heading itself. A bare
  # `before … spawn` would not reach it: the paragraph under that heading says
  # "immediately before spawning" too, so the heading could be inverted alone
  # and stay green.
  #
  # BOTH ORDERS, for the reason the evidence-pair case below takes them: the
  # rule reworded as `delete that agent's stale report file before each spawn`
  # states the same ordering the other way round, and a pin so tight that a
  # faithful rewording false-Reds is a defect too. Neither branch matches
  # anything else in the section, before the mutation or under it.
  #
  # Residual, named rather than left to be found: the paragraph's own
  # restatement inverted ALONE — "each immediately after spawning", the
  # heading intact — stays GREEN. Reaching it costs a second count over
  # `before … spawn`, whose price is a false Red the day that paragraph
  # legitimately stops restating the heading above it.
  printf '%s\n' "$flatsec" \
    | command grep -qiE '(before[^.]{0,20}spawn[a-z]*[^.]{0,30}(delet|remov)|(delet|remov)[a-z]*[^.]{0,60}before[^.]{0,20}spawn)'
}

@test "the procedure reads both verdicts from the report files" {
  # Steps 3-5 conclude from disk; the message is courtesy.
  #
  # A FILENAME DOES NOT CARRY THE DIRECTION. Whether `validation-report` and
  # `audit-report` OCCUR anywhere in the section is a question an inversion of
  # this rule has no reason to change: steps 3 and 4 rewritten to "Take the
  # verdict from the final message" and "take its verdict from its final
  # message the same way" still DELETE their report file, and the stale-report
  # subsection names both files again.
  #
  # Both halves are asserted, and both are needed: the inversion of the steps
  # leaves the `### The verdict is the file; the reply is a courtesy`
  # subsection intact, and the inversion of that subsection leaves the steps
  # intact.
  proc="$(md_section "$VALIDATE_MODE" '^## Validate Mode Procedure' '^## ')"

  # CONCLUDE FROM DISK. Line-based co-location, as at the stale-report case
  # above: this file writes one paragraph per source line, so the report file
  # and the direction have to be stated in the SAME paragraph — the filename
  # cannot be answered by the delete in step 3 while the direction is answered
  # by some unrelated step. What is pinned is the SOURCE of the verdict, not a
  # wording: `read off that report file` and `comes from disk` are the same
  # rule and stay green; `from the final message` is another rule and Reds.
  printf '%s\n' "$proc" | command grep -E 'validation-report' \
    | command grep -qiE 'verdict[^.]{0,60}(from|off)[^.]{0,30}(file|disk)'
  printf '%s\n' "$proc" | command grep -E 'audit-report' \
    | command grep -qiE 'verdict[^.]{0,60}(from|off)[^.]{0,30}(file|disk)'

  # THE MESSAGE IS COURTESY — the half no filename can carry: the reply is the
  # source of NO verdict. The negation has to GOVERN the reply, which is what
  # the reversal cannot keep; moving it onto the file ("The report file is a
  # convenience … and the source of no pass/fail decision") Reds here.
  #
  # NOT co-located with a filename, unlike the pass point below: no line of
  # this section states both halves, and the co-located form is answered by the
  # recovery table's row 2 on its own — "or **not** parseable as YAML | **one**
  # `SendMessage`" — a line the inversion of steps 3-4 never touches.
  #
  # `(no|not|never)` carries a boundary on each side so `now`, `know` and
  # `cannot` are not read as negations — that same row 2 ends "asking it to
  # write its report file now", and it is what made the boundaries necessary.
  printf '%s\n' "$proc" \
    | command grep -qiE '(message|repl(y|ies))[^.]{0,120}[^A-Za-z](no|not|never)[^A-Za-z][^.]{0,40}(pass/fail|verdict|decision)'

  # AND THE PREMISE UNDER BOTH HALVES: the files are readable at step 3 only
  # because each agent writes its report as the LAST step, BEFORE any prose.
  # That is the first clause of this section's own verdict-is-the-file
  # paragraph, and it is the THIRD copy of the ordering the two agent
  # definitions state — the two prompt templates are the other two, pinned in
  # the mirror cases with this identical pattern and this identical guard. It
  # lands in THIS case rather than in a case of its own because this scope is
  # the only one that reaches that paragraph and because the sentence states
  # this case's own rule from the writing side.
  #
  # ONE SPAN IN THIS SCOPE out of three `last` tokens — the other two are step
  # 3's `writes that file as its last step` and the stale-report subsection's
  # `reads last week's `pass``, neither of which has `before ... compos` behind
  # it. The 40-character leashes carry this copy's own gap of 27 (`** step of
  # their protocol, `), which is why the same pattern reads all three copies.
  # It Reds on `**first** step ... after composing any prose`, on `**last**
  # step ... after composing any prose`, and on the clause deleted outright; it
  # stays GREEN on `as the **last** thing they do, before composing any prose`.
  # Why the guard below is needed, what its hop admits and what the pin costs
  # are argued once on the Validator mirror case above.
  #
  # FLATTENED, unlike the three assertions above it, and the difference is the
  # claim rather than taste: those pin a fact to the LINE that names a report
  # file, so flattening would let the filename and the direction come from
  # different paragraphs; this one needs no co-location and takes the reflow
  # tolerance instead. Flattening admits nothing new here: the pin finds one
  # span and the guard no hits, as on the raw section.
  flatproc="$(printf '%s\n' "$proc" | tr '\n' ' ')"
  printf '%s\n' "$flatproc" \
    | command grep -qiE '(^|[^A-Za-z])last[^.]{0,40}before[^.]{0,40}compos'
  if printf '%s\n' "$flatproc" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely|as|the)[^A-Za-z]{1,3}){0,3}last'
  then
    echo "the write-before-prose ordering is stated with a negation on it — the premise this section reads its verdicts under is reversed"
    return 1
  fi
}

@test "an absent or unparseable report is re-requested once via SendMessage, then the run is failed" {
  # The recovery path is one SendMessage, never a silent respawn and never a
  # verdict inferred from prose.
  #
  # Scoped to the recovery subsection. `SendMessage` and `unparseable` also
  # appear in the verdict-is-the-file prose above, so an unscoped check
  # survives deleting any of the three rows this case is named for.
  #
  # End pattern is '^#', NOT the '^## ' the neighbouring cases use: that one
  # carries a trailing space and so runs straight past a '###' subsection,
  # swallowing the rest of the file and putting the scope back where it was.
  # '#' anchored at line start cannot match the table's '| # |' header.
  sec="$(md_section "$VALIDATE_MODE" '^### Absent or unparseable' '^#')"
  # Flattened inline rather than via `flat`, which reads a file and cannot take
  # a captured section on a pipe. A soft wrap must not hide a phrase.
  sec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  # ONE REQUEST, BY SendMessage — AND NEVER A SECOND. `one` alone cannot be
  # pinned: `(^|[^A-Za-z])one[^A-Za-z][^.]{0,80}SendMessage` is satisfied by
  # every phrase that reverses it, because `one` is a SUBSTRING of them (`more
  # than one`, `one per attempt`) — row 2 rewritten to `**one** `SendMessage` …
  # per attempt … — repeat the row as often as it takes`, the paragraph to
  # `**One request per attempt, …**` and row 3 to `after the last of those
  # requests` keeps it GREEN under a rule that licenses unbounded re-requests.
  # No scope and no count reaches that; only different prose does, so the rule
  # carries its bound in a token: `and **never a second**` in row 2 and `and
  # never a second` in the paragraph — a token inside each existing sentence.
  #
  # THE TOKEN IS ONE THE REVERSAL BREAKS RATHER THAN CONTAINS, which is the
  # whole difference from `one`: prose that licenses repeats cannot keep
  # `never a second` and stay coherent. So the per-attempt mutation Reds here,
  # as do `never` dropped, the token dropped, and the rule inverted to `always
  # a second`.
  #
  # MECHANISM AND BOUND IN ONE MATCH, because the case is named for both.
  # `SendMessage` occurs exactly once in this section — row 2 — and the token
  # sits 30 characters from it. BOTH ORDERS, for the reason the ordering pin
  # two cases above takes them: a rewording that states the bound first states
  # the same rule, and a pin so tight that a faithful rewording false-Reds is a
  # defect too. Neither branch matches anything else in the section — the
  # paragraph's own `never a second` has no `SendMessage` within 60 characters.
  printf '%s\n' "$sec" \
    | command grep -qiE '(SendMessage[^.]{0,60}never +a +second|never +a +second[^.]{0,60}SendMessage)'

  # ...AND AT BOTH SITES THAT STATE IT, counted, because a `-q` is answered by
  # either one and a partial removal would pass: row 2 is the instruction the
  # flow executes, the paragraph is the argument for it. The bound reversed at
  # either site alone takes the count to 1 and Reds. `-eq` rather than `-ge`,
  # over flattened text, captured before it is compared: three decisions argued
  # once at the validator carve-out twin above, at the same cost — a legitimate
  # THIRD statement of the bound would false-Red. The ` +` is reflow slack, as
  # in the validator ordering pin; the leading boundary is not decoration
  # either, because `whenever a second` ends in `never a second`.
  #
  # ROW 3 STATES THE BOUND TOO, in its own words rather than in this token's
  # (`after that one request`), and it is pinned at the TAIL of this case
  # instead of counted here: it is the same rule read from the failure side and
  # it shares no anchor with `never a second`. Reversing that row alone leaves
  # this count at 2 and Reds the pairing below, which is how all three sites
  # end up held.
  bounds=$(printf '%s\n' "$sec" | command grep -oiE '(^|[^A-Za-z])never +a +second' | wc -l)
  [ "$bounds" -eq 2 ]

  # ...AND NOT MORE THAN ONE, for the five phrasings this guard names and no
  # others. It Reds on `**more than one** `SendMessage`` and stays GREEN on the
  # `per attempt` form, which is why the bound lives in the PROSE and is pinned
  # above rather than enumerated here. Extending the list is not the
  # mechanism, so the list stays as it is.
  #
  # KEPT, AND NOT REDUNDANT, because an assertion that cannot fail while its
  # neighbour passes is one this file deletes (see the carve-out count above).
  # The vector it alone catches is the MINIMAL widening: row 2's `**one**`
  # swapped for `**more than one**` with the token left standing. The prose
  # then contradicts itself, the pin and the count both stay GREEN, and this
  # guard Reds.
  #
  # NOT a bare `!`, and that is not a style choice: bash exempts a `!`-inverted
  # command from errexit, so its status is discarded anywhere but the LAST
  # statement of the @test — and two assertions follow this one. The
  # negated-assertion lint in tests/assertion-hygiene.bats keeps that shape out
  # of tests/.
  #
  # NOT the generic helper the header forbids: that one rejects any negation in
  # the window before any match and false-Reds on auditor.md's memory clause by
  # construction. This names the modifiers of ONE quantifier, stays inline in
  # the case that owns it, and is silent on the unmutated section — which holds
  # four `one`s: row 2's "**one** `SendMessage`", row 3's "after that one
  # request", the paragraph's "One request and never a second" and the respawn
  # paragraph's "looping over one failure".
  #
  # One red-on-correct vector, accepted: "never more than one `SendMessage`"
  # Reds here, and that is accepted because row 2 is an imperative action cell
  # whose prohibition is already stated, adjacent, as `**never a second**`.
  if printf '%s\n' "$sec" \
    | command grep -qiE '((more than|not just|not only|at least|greater than)[^.]{0,10}one[^A-Za-z]|one[^A-Za-z]{1,4}or more)'
  then
    return 1
  fi
  # NEVER a silent respawn — the whole cost the report file exists to avoid,
  # and `never` has to GOVERN `respawn` rather than merely share a sentence
  # with it. A window like `never[^.]{0,80}respawn` passes `**Never conclude
  # without a respawn.**` — a rule that MANDATES the respawn — because that
  # reversal moves the negation's OBJECT and leaves both anchors standing.
  # Pinned ADJACENT instead: the phrase the rule's own name already uses, one
  # span in this section.
  #
  # The optional `-ly` adverb is the one thing English puts between a
  # prohibition and its verb without changing what is prohibited: `**Never
  # silently respawn the agent.**` stays GREEN. Every reversal needs a verb and
  # a preposition in that slot — `conclude without a`, `fail to`, `skip a` — or
  # a bare `not`, and none of those is an adverb: RED, including the `**Always
  # respawn silently.**` control and the deletion.
  # Two residuals, named rather than hidden: an adverb that WEAKENS instead of
  # reversing (`never unnecessarily respawn`) passes, and the prohibition
  # restated with its negation AFTER the verb (`a silent respawn is never the
  # answer`) false-reds — what is pinned is the order the rule's own name
  # states. Closing the adverb slot to buy the first one back would false-red a
  # plain word-order rewording, the costlier of the two.
  printf '%s\n' "$sec" \
    | command grep -qiE '(^|[^A-Za-z])never[^A-Za-z]+([a-z]+ly[^A-Za-z]+)?respawn'
  # THEN THE RUN IS FAILED, stated in exactly those terms. The copula and the
  # participle are required ADJACENT, not merely co-occurring within a window:
  # an inversion writes `not` between them, and `the run[^.]{0,40}fail` matches
  # "the run is **not** failed" exactly as it matches the real row. Safe to
  # tighten because this section holds exactly one `the run … fail` span and it
  # reads `the run is failed` — the same phrase row 3 and this case's own name
  # use, so prose that breaks it is a rewrite of the contract, not a rewording
  # of it. The no-silent-respawn wording is answered by the grep on the line
  # above, not by this one.
  #
  # ...AFTER *ONE* REQUEST, WHICH IS ROW 3'S HALF OF THE BOUND, and the third
  # site the token above does not reach. A bare `the run is failed` cannot
  # carry it: with the bound WIDENED but KEPT — `never a second per attempt` at
  # both token sites, row 3 rewritten to `after the last of those requests` and
  # `repeat the row as often as it takes` appended — every other assertion in
  # this case stays GREEN on a section that licenses unbounded re-requests.
  # Pairing the count with the failure Reds it, because a rule that repeats
  # cannot also say the run is failed after ONE request.
  #
  # THE COUNT SITS ADJACENT TO THE NOUN IT COUNTS, which is what makes `one`
  # usable here although it cannot be pinned on its own. The two directions
  # split: a reversal that licenses repeats must change the noun (`the last of
  # those requests`, `each of those requests`) and so loses the phrase, while a
  # reversal that KEEPS `one` needs a modifier in front of it — `more than one
  # request` — which the guard above refuses. Neither assertion covers the
  # other. `single` rides beside `one` because it is this document's other word
  # for the same count, and the widening adds no span — the section's other
  # `one`s are all further than 60 characters from the failure phrase or behind
  # a full stop. Residual, named rather than left to be found: row 3 reworded
  # to drop the count altogether (`after that request`) false-Reds — the same
  # trade the ordering clause takes.
  printf '%s\n' "$sec" \
    | command grep -qiE '(^|[^A-Za-z])(one|single) +request[^.]{0,60}the run is failed'
}

@test "the pass point keys off the report file's verdict" {
  # Stamping `validated` reads the file, not the message. Scoped to the
  # Status Transition section — "reported" elsewhere must not satisfy it.
  #
  # THE FILENAME IS NOT THE RULE. A section that merely mentions a report file
  # stays green through the rule's own reversal: `Rules 1-3 turn on what an
  # agent said in chat — never on the `verdict` field of
  # `.draft/validation-report.yaml` and `.draft/audit-report.yaml`` keeps every
  # filename.
  #
  # The polarity was already in the prose — "never on what an agent said in
  # chat" — so the match carries it: a negation GOVERNING the reply, on the
  # line that names the report file. Exactly one line of this section names
  # one (the rule itself), so the rejection cannot be borrowed from a
  # neighbouring paragraph.
  #
  # The reversal cannot keep that shape. It moves the negation onto the file
  # half, where the full stops in `.draft/…yaml` close the window before any
  # word for the reply, so it Reds. "The verdict is read from the report
  # files … rather than from the agents' replies" stays GREEN, which is the
  # distinction the pin exists to draw: the direction survives a rewording,
  # the reversal does not.
  md_section "$VALIDATE_MODE" '^## Status Transition' '^## ' \
    | command grep -iE 'validation-report|audit-report|report file' \
    | command grep -qiE '((^|[^A-Za-z])(never|not)[^A-Za-z]|rather than|instead of)[^.]{0,80}(chat|message|repl(y|ies)|said|prose)'
}

# --- Tech Reviewer measures ---------------------------------------------------

@test "tech-reviewer frontmatter grants Bash" {
  grants "$TECH_REVIEWER" "Bash"
}

@test "tech-reviewer's Bash is measurement-only and never mutates" {
  # The grant arrives WITH its restriction, and the no-modify rule survives
  # reworded — both facts, not either one.
  #
  # `measurement` ALONE IS THE TOPIC, NOT THE RULE: rewriting the grant to
  # "`Bash` is not limited to measurement — never mutate files or git state"
  # keeps the word, because the topic word survives every widening of the
  # scope it exists to close. What is pinned instead is the RESTRICTION the
  # agent definition writes — `for measurement only` — which occurs once, so
  # no heading and no cross-reference can answer for it.
  flat "$TECH_REVIEWER" | command grep -qiE '(^|[^A-Za-z])for measurement only'

  # THE PHRASE ALONE IS NOT THE RULE EITHER: the reversal keeps it and negates
  # it. "`Bash` is not for measurement only" contains `for measurement only`
  # verbatim. So the negation is refused where it can reach the phrase —
  # adjacent, or across one hedge ("no longer", "not merely", "must not be").
  # Adjacency rather than a sentence-wide window is the point: a window here
  # would red on "This is a rule, not advice: `Bash` is for measurement only",
  # which states the rule rather than reversing it.
  if flat "$TECH_REVIEWER" \
    | command grep -qiE '(never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?for measurement only'
  then
    echo "the restriction phrase survives, negated: the grant no longer stops at measurement"
    return 1
  fi

  # THE NO-MUTATION HALF NEEDS ITS OWN PIN. A window like
  # `(never|not)[^.]{0,80}mutat` reads 80 characters and cannot say which
  # clause the negation governs: dropping the negation ("— mutate files or git
  # state when the fix is trivial") Reds, but moving its OBJECT ("— never
  # refuse to mutate files or git state when the fix is trivial"), a rule that
  # licenses the mutation, stays GREEN.
  #
  # The negation sits on the mutation word, at most one `for` apart: `no-modif`
  # is excluded on purpose, because this paragraph names the rule as "The
  # no-modification rule" and that noun would answer the assertion by itself
  # while the clause above it said the opposite. Grepping the lines that name
  # the tool first is the co-location this case is named for — the grant
  # arrives WITH its restriction, not somewhere else in the file: the closing
  # "**Do NOT modify files or git state. Only report.**" is a second span of
  # the prohibition and must not be able to stand in for this one.
  #
  # ONE `for` IS THE WHOLE WIDENING, and strict adjacency is too tight without
  # it: rewriting the half to "— never for mutation." preserves the rule
  # exactly and would false-Red. It keeps the sentence's own frame ("is for
  # measurement only") and negates it for mutation, so what is admitted is
  # that clause nominalised, not a gap: a VERB between the two is what
  # re-targets the negation, and "never refuse to mutate" is still RED.
  command grep -E '(^|[^A-Za-z])Bash([^A-Za-z]|$)' "$TECH_REVIEWER" \
    | command grep -qiE '(never|not|no) {1,3}(for {1,3})?(mutat|modif)'
}

@test "a tech-reviewer finding resting on a runnable check cites command and output" {
  # Measured, not argued — the finding carries the evidence pair.
  #
  # SCOPE COMES BEFORE POLARITY. Over the WHOLE file `command[^.]{0,120}output`
  # is answered TWICE — by the rule and by the report-format bullet ("… the
  # command and its output") — so deleting the rule outright would stay GREEN
  # and the obligation could vanish from that file without a Red.
  #
  # SCOPED TO THE SECTION THAT STATES THE RULE. `## Measurement, Not Argument`
  # ends where `## Protocol` begins, which puts the checklist bullet out of
  # scope by construction. The end pattern is `^## ` WITH the trailing space,
  # the idiom the `##`-level captures above use; here it is not load-bearing —
  # the section holds no heading of any depth, so `^##` captures the same
  # lines. Where a `###` subsection DOES sit inside, the space decides the
  # boundary. Inside the section the pair has exactly one span and `output`
  # occurs exactly once, so the deletion Reds. The exclusion holds in the other
  # direction too: the report-format bullet rewritten to `— a paraphrase of
  # what you ran`, the rule untouched, stays GREEN. A span this case does not
  # own must not decide it.
  sec="$(md_section "$TECH_REVIEWER" '^## Measurement, Not Argument' '^## ')"
  # `flat` reads a file, so a captured section is flattened inline.
  flatsec="$(printf '%s\n' "$sec" | tr '\n' ' ')"

  # THEN THE POLARITY, because a scope alone still passes a section stating
  # the opposite. `carries` is the obligation, and English reverses a rule of
  # this shape with a modal plus a bare infinitive — `need not carry`, `does
  # not carry`, `is not required to carry` — every one of which loses the
  # inflection and Reds.
  #
  # The 60-character leash and the two orders are costs, taken on purpose.
  # Rewordings that park a parenthetical between the verb and its object
  # cluster at 40-44 characters (`carries, quoted rather than paraphrased, the
  # exact command …`), and `carries the observed output and the exact command
  # that produced it` states the same pair the other way round; a 40-character
  # single-order pattern false-Reds both. Tightening the leash buys nothing
  # back: a sentence where `carries` governs some OTHER noun while the pair
  # sits in a later clause can fall inside even a 40-character window. That
  # shape is the residual, named rather than discovered later — the leash
  # proves `carries` shares the sentence, and the guard below is what proves it
  # is not negated.
  printf '%s\n' "$flatsec" \
    | command grep -qiE 'carries[^.]{0,60}(command[^.]{0,120}output|output[^.]{0,120}command)'

  # THE INFLECTION IS NOT THE WHOLE RULE. Three reversals keep it and park the
  # negation beside it — `carries neither the command nor its output`, `never
  # carries`, `no longer carries` — and all three pass the match above.
  # Refused here rather than by narrowing that match, because a
  # negation beside `carries` only reverses the rule when it REACHES the pair:
  # `carries no command it did not actually run` restates the rule and stays
  # GREEN, which is what the `output` leash on the second branch is for.
  if printf '%s\n' "$flatsec" \
    | command grep -qiE '((never|not|no)[^A-Za-z]{1,3}((be|longer|more|just|merely|simply|solely)[^A-Za-z]{1,3})?carries|carries[^A-Za-z]{1,3}(no|neither|nothing)[^.]{0,80}output)'
  then
    echo "the evidence pair is stated with a negation beside it — the finding is no longer obliged to carry it"
    return 1
  fi
}

@test "the Tech Reviewer prompt template carries inputs only and defers to the agent definition" {
  # The agent definition is the Tech Reviewer's system prompt. A second copy of
  # its protocol in the spawn prompt costs every spawn twice and drifts; the
  # measurement rule is pinned on the agent definition by the cases above.
  sec="$(md_section "$TECH_REVIEW" '^### Tech Reviewer Prompt Template' '^##')"
  printf '%s\n' "$sec" | command grep -q 'Follow your agent definition'
  if printf '%s\n' "$sec" | command grep -qE '## Protocol|Measurement, Not Argument|for measurement only'; then
    echo "the template restates the agent's protocol"
    return 1
  fi
}

# --- Least-privilege grant sets ----------------------------------------------

@test "Write is granted to exactly auditor, executor and test-advisor" {
  # Write is held by exactly these four agents; nobody else joins. An
  # exact-set compare reddens on an agent ADDED as loudly as on one removed.
  expected="auditor
executor
test-advisor"
  [ "$(agents_granting Write)" = "$expected" ]
}

@test "Bash is granted to exactly auditor, executor, final-reviewer, tech-reviewer and test-advisor" {
  # Bash is held by exactly these agents; nobody else joins. The final reviewer
  # needs it to reproduce each finding in its own temporary copy.
  expected="auditor
executor
final-reviewer
tech-reviewer
test-advisor"
  [ "$(agents_granting Bash)" = "$expected" ]
}

@test "PIN Edit stays the executor's alone" {
  # GREEN PIN: Edit belongs to the executor alone — no other agent gains it. A
  # reddening here means a grant came along for the ride.
  [ "$(agents_granting Edit)" = "executor" ]
}

# --- agent-definition conventions --------------------------------------------
#
# A general agent-definition convention, parked in this file because a single
# case does not earn a file of its own; move this block out when a second
# agent-definition convention joins it. Its helper travels with it, which is why
# that helper sits here rather than with the shared ones at the top.

# The memory: line inside the frontmatter block only — the same shape as
# frontmatter_tools, so prose about memory can never enrol an agent.
frontmatter_memory() {
  awk 'NR==1 && $0=="---" {inb=1; next}
       inb && $0=="---" {exit}
       inb && $0 ~ /^memory:/ {print; exit}' "$1"
}

@test "convention: no agent declares memory: — project memory is ai-memory, written by the orchestrator" {
  # DERIVED FROM THE FRONTMATTER, so a new agent joins this pin by existing.
  offenders=()
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    [ -n "$(frontmatter_memory "$f")" ] && offenders+=("$(basename "$f")")
  done
  if [ "${#offenders[@]}" -gt 0 ]; then
    printf 'declares memory: %s\n' "${offenders[@]}"
    return 1
  fi
}

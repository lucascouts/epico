#!/usr/bin/env bats
# The P1 verdict of the 2026-10-30 SDD battery (epico × 5 frameworks × 7
# languages, persona Bia, n=1 per cell) — each case pins one rule to the
# reference that carries it.
#
#   P1  failure cases are listed, one test each; an unrun case is not done
#       (Superpowers 7/7 turned its cases into tests; BMAD: "a test that never
#       ran counts as absent")
#   P2  a converge pass adds work only on an executed reproduction, and checks
#       the floor too (Spec Kit /speckit-converge; its blind spot was the floor)
#   P3  a page is checked at the URL its own server printed, with curl (a TS
#       run called a page working from another run's server)
#   P4  a layperson closing stays under ~600 characters, checked by
#       epico-jargon --max-chars ("mto texto" in 13/14 runs)
#   P5  the engineering level is inferred from the request, never asked (7/7:
#       the answer picked a 3–5 min or a 12–17 min route; Standard scored lowest)
#   P6  the interface language is inferred from the request's language (7/7
#       asked, 7/7 answered the language the request was written in)
#   P7  "see it running" shows the output as text, never a question right after
#       a question (2/2 Standard runs: Bia never saw the result)
#   P8  a layperson never gets a model hint, a model choice or a handoff
#       command (7/14 runs; one asked to choose and lost a turn)
#   P9  using a thing again is not upkeep, and a layperson whose level the
#       request does not settle takes the lean route (2026-11-02 check: the
#       inference read "I'll keep using it" as tool, 7/7 runs became Standard
#       stories — 22.6 min median against 4.2, 67 questions against 36)
#   P10 nothing leaves the machine unless the requester asked for that step
#       (2026-11-02 check: a run uploaded a 14-year-old's project to a public
#       file host after a yes/no question)

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
REFS="$ROOT/references"

has() { # has <file> <fixed text>
  grep -qiF -- "$2" "$1" || { echo "${1#"$ROOT"/} does not carry: $2" >&2; return 1; }
}
lacks() { # lacks <file> <fixed text>
  if grep -qiF -- "$2" "$1"; then echo "${1#"$ROOT"/} still carries: $2" >&2; return 1; fi
}

@test "P1: failure cases are listed before the code, one test each, and an unrun case is not done" {
  has "$REFS/lean-route.md" 'list the failure cases first'
  has "$REFS/lean-route.md" 'a case whose test did not run is not done'
  has "$REFS/tasks.md" 'one test per failure case'
  has "$REFS/run-mode.md" 'a failure case with no executed test keeps the box open'
}

@test "P2: converge adds work only on an executed reproduction and checks the floor" {
  has "$REFS/run-end.md" '### Converge'
  has "$REFS/run-end.md" 'no reproduction, no change'
  has "$REFS/run-end.md" 'the floor'
  has "$REFS/lean-route.md" 'converge'
}

@test "P3: a page is checked at the URL its own server printed, with curl" {
  has "$REFS/lean-route.md" 'the URL the server itself printed'
  has "$REFS/lean-route.md" 'curl'
  has "$REFS/run-end.md" 'the URL the server itself printed'
}

@test "P4: a layperson closing stays under ~600 characters, checked by epico-jargon" {
  has "$REFS/plain-register.md" '600 characters'
  has "$REFS/plain-register.md" 'epico-jargon --max-chars 600'
  has "$REFS/lean-route.md" '600 characters'
}

@test "P5: the engineering level is inferred from the request, never asked" {
  has "$REFS/triage.md" 'inferred from the whole request, never asked'
  lacks "$REFS/triage.md" 'ask when the request does not settle it'
  has "$REFS/engineering-level.md" 'never asked'
  lacks "$REFS/engineering-level.md" 'is fished for inside the orientation round'
  lacks "$REFS/clarify.md" 'this round carries its indirect questions'
}

@test "P6: the interface language is inferred from the request, asked only when it is in doubt" {
  has "$ROOT/skills/epico/SKILL.md" 'The interface language is inferred, not asked'
  lacks "$ROOT/skills/epico/SKILL.md" 'The interface language is asked, not assumed'
  has "$REFS/clarify.md" 'The interface language is inferred, never asked'
  has "$REFS/clarify.md" 'mixes languages'
}

@test "P7: see it running ends with the output as text, never a question right after a question" {
  has "$REFS/run-end.md" 'show the output as text'
  has "$REFS/run-end.md" 'never a question right after a question'
}

@test "P8: a layperson never gets a model hint, a model choice or a handoff command" {
  has "$REFS/lean-route.md" 'never for a `layperson`'
  has "$REFS/triage.md" 'never for a `layperson`'
  has "$REFS/clarify.md" 'a `layperson` is never asked it'
  has "$REFS/phase-gates.md" 'a `layperson` gets no command'
}

@test "P9: using a thing again is not upkeep; an unsettled layperson takes the lean route" {
  has "$REFS/engineering-level.md" 'using it again is not upkeep'
  has "$REFS/triage.md" 'using it again is not upkeep'
  has "$REFS/triage.md" 'a `layperson` whose level the request does not settle takes the lean route'
  has "$REFS/engineering-level.md" 'a `layperson` whose level the request does not settle takes the lean route'
}

@test "P10: nothing leaves the machine unless the requester asked for that exact step" {
  has "$REFS/lean-route.md" 'nothing leaves the machine'
  has "$REFS/run-mode.md" 'nothing leaves the machine'
  has "$REFS/lean-route.md" 'file host'
  has "$REFS/lean-route.md" 'never move it for them'
}

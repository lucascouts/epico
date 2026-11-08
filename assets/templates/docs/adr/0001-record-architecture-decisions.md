# ADR-0001 — Record architecture decisions

- Status: Accepted
- Date: {{date}}

## Context

Decisions about the stack and the structure get made once and questioned many times. Without a
record, the reasons are lost and the same debate is held again.

## Decision

Each decision with alternatives worth remembering is an ADR in `docs/adr/`, numbered in order. An
ADR's text is never rewritten: a changed decision is a new ADR with `Supersedes: ADR-<n>`; a new
detail on the same decision is a dated entry under Amendments.

## Consequences

The reasons travel with the code, and a newcomer can read why before changing it. Writing an ADR
costs a few minutes per decision.

## Enforcement

- judgment-only: whether a decision deserves an ADR is a call the checkpoint makes with the user.

## Amendments

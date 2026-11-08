---
version: 1
as_of: {{date}}
---

# {{project}} — Roadmap

An index, not the plan itself: each stage keeps its tasks in its own file under `stages/`, and
each task's status is its checkbox there. Stories name the tasks they work on with
`roadmap: [1.1.1]`, and `/epico:epico checkpoint <N>` closes a stage against them.

## Principles

- **Risk first:** the stage that can kill the project comes before the one that polishes it.
- **Rolling wave:** only the current stage is detailed; the next is detailed when this one closes.
- **No dates:** a stage ends when its gate passes, not on a day.

## Stages

| Stage | Goal | Gate | File |
|---|---|---|---|
| 1 | The skeleton runs end to end and its checks pass | — | [01 — Foundation](stages/01-foundation.md) |

## Gates

A gate is a go/no-go decision between stages, recorded in `gates/gate-<n>.md` by the checkpoint.

## Open blockers

Only what blocks work now; a closed blocker moves to the Review of the stage where it closed.

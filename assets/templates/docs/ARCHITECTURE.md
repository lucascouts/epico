---
version: 1
as_of: {{date}}
---

# {{project}} — Architecture

The stack, the modules and the rules between them, as built. A decision with alternatives worth
remembering gets an ADR in `adr/`; this file links it.

## 1. Stack

Runtime and version, language, frameworks, storage — each with the ADR that chose it.

## 2. Modules

| Module | Responsibility | May import |
|---|---|---|
|  |  |  |

## 3. Rules

Each rule names the check that enforces it (a lint rule, a test, a make target), so the rule is a
test and not only a sentence.

## 4. Decisions

One line per ADR, with its link.

- [ADR-0001](adr/0001-record-architecture-decisions.md) — architecture decisions are recorded as ADRs

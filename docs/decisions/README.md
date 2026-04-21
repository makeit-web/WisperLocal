# Decision Log

Every non-trivial technical decision is recorded here. One file per decision.

## File naming

`YYYY-MM-DD-NNN-short-slug.md` — e.g., `2026-04-21-001-swift-over-electron.md`

Counter `NNN` resets nothing; just increment across the project so ordering is unambiguous.

## Template

```markdown
# NNN — Short Decision Title

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Superseded by NNN | Reversed
**Decider:** User (CEO) — on Claude's recommendation

## Context
What problem are we solving? What constraints matter here?

## Options Considered
1. **Option A** — one-line summary. Pros / Cons.
2. **Option B** — one-line summary. Pros / Cons.
3. **Option C** — one-line summary. Pros / Cons.

## Decision
Chosen option and the one-sentence reason.

## Reasoning
Why this option beats the others, in the context above. Link research docs, benchmarks, Apple docs as needed.

## Consequences
- What this enables
- What this locks us out of
- Follow-up work this creates
```

## Rules

- Decisions are immutable once Accepted. To change direction, write a new decision with `Status: Supersedes NNN` and update the old one's status to `Superseded by NNN`.
- If Claude recommends and user approves in a chat, Claude writes the decision file in the same session — don't leave the log behind the actual work.

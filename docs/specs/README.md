# Specs

One spec per phase. Medium discipline — concise but complete.

## File naming

`phase-N-short-name.md` — e.g., `phase-1-whisper-setup.md`

## What a phase spec contains

1. **Goal** — one paragraph. What does "done" look like?
2. **Scope — In** — explicit list of what this phase delivers.
3. **Scope — Out** — explicit list of what this phase does NOT include (kicked to later phase).
4. **Success criteria** — measurable checks. For Phase 1: "WER on 5 Croatian samples ≤ X%."
5. **Open questions** — what must be answered before coding starts.
6. **Approach** — Claude's recommended technical path (tools, flags, libraries).
7. **Risks** — what could go wrong + mitigation.
8. **Test plan** — unit, integration, manual checks.
9. **Dependencies on prior phases / decisions.**

## Workflow

1. Claude drafts the spec from a conversation / brainstorm.
2. User reviews, asks questions, approves.
3. Claude then writes an implementation plan (may live at the bottom of the spec or in a separate `plan-phase-N.md`).
4. User approves the plan.
5. Only then does code get written.

If a spec turns out wrong mid-implementation — **stop, don't pivot.** Update the spec, get approval, continue.

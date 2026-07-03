# WisperLocal — Skills Registry

All roles and workflows used in this project. Single source of truth.

## Structure

```
skills/
├── README.md          <- This file
└── roles/             <- 4 role definitions
    ├── orchestrator.md
    ├── swift-developer.md
    ├── whisper-ml-specialist.md
    └── quality-reviewer.md
```

## Roles

| # | Role | File | When to invoke |
|---|------|------|----------------|
| 1 | Orchestrator | `roles/orchestrator.md` | Start/end of every session; phase transitions; progress tracking |
| 2 | Swift Developer | `roles/swift-developer.md` | Implementing macOS UI, menu bar, hotkey, Accessibility, AVAudioEngine wiring |
| 3 | Whisper / ML Specialist | `roles/whisper-ml-specialist.md` | whisper.cpp build, Core ML model conversion, benchmarking, audio pipeline tuning |
| 4 | Quality Reviewer | `roles/quality-reviewer.md` | After every implementation; Pass 1 of three-pass review |

## Code Review Process (Risk-Scaled)

Review is **risk-scaled** (ADR 004 / master plan §2.5): **Phases 3–5** (app / injection — real attack surface) get the full three passes below; **Phases 1–2** (CLI / benchmark — zero attack surface) get Pass 1 + one Codex pass. The passes:

### Pass 1 — Claude Quality Reviewer
- Uses `roles/quality-reviewer.md`
- Checks: correctness, Swift/Apple conventions, concurrency safety, permission handling, test coverage
- Output: structured findings by severity

### Pass 2 — Codex Standard Review (`/codex:review`)
- Independent AI review, different model
- Review-only (no auto-fix)
- Output: JSON verdict + findings

### Pass 3 — Codex Adversarial Review (`/codex:adversarial-review`)
- Skeptical stance: assumes failure until evidence says otherwise
- Attack surface: audio privacy, accessibility permissions, hotkey conflicts, concurrency, edge cases, OS version compatibility

The passes required for the phase must complete before it is marked done. Findings shown to user; user decides which to fix before moving on.

## External Skills (from superpowers plugin)

Invoked via the `Skill` tool, not read from files:

- `superpowers:brainstorming` — Idea → design → spec
- `superpowers:writing-plans` — Spec → implementation plan
- `superpowers:executing-plans` — Plan → code
- `superpowers:test-driven-development` — TDD workflow
- `superpowers:systematic-debugging` — Bug investigation
- `superpowers:verification-before-completion` — Final checks before marking done
- `superpowers:requesting-code-review` — Post-implementation review

Domain skills that may apply (invoke as needed):
- `debugging` — general bug hunts
- `code-review` — general review discipline
- `security-review` — security-focused pass
- `documentation` — writing docs, runbooks

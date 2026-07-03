# 004. Governance model (lean guardian set + main-only ship flow)

**Date:** 2026-07-02
**Status:** Accepted (master plan approved 2026-07-02)
**Deciders:** Claude (CTO, recommends) + User (CEO, approves)

## Context
Two internal references were adopted: `makeit-web/dev-project-template` (CTO/orchestrator + 8 guardians + gates) and `_agilno/ai-engineering` (governance + mandatory workflow skills). Both are built for enterprise web apps with a Jira/Bitbucket **PR** pipeline. WisperLocal is solo, offline, native-macOS, **main-only / push-when-asked / no PRs / no branches / no worktrees**.

## Options considered
- Adopt the template wholesale — rejected: OWASP/BOLA security-guardian, i18n ux-guardian, PR/Jira/Confluence flow, `/project-init`, hardened HMAC tier, and the web skills-library have no target surface here.
- Ignore it and keep only `CLAUDE.md` — rejected: we'd lose the valuable guardian/gate discipline.
- **Adopt the process spine + a lean, adapted guardian set** — chosen.

## Decision
Adopt: CTO/orchestrator model, spec→plan→gate flow, ADRs, memory conventions, three-pass review, `_method-core` audit discipline. **Guardian set (7, adapted):** spec-alignment, scope-creep, no-shortcuts (Swift profile), test-coverage (Swift), implementation-verifier, **privacy-guardian** (new, replaces OWASP security-guardian), doc-consistency. **Gates** G1 (pre-plan) + G2 (pre-commit) + phase gate + build gate, adapted to a main-only **`ship`-style** commit flow (verify → scoped conventional commit → approval-before-push); the heavy checks run at the phase gate, not per commit. Drop: security-guardian (OWASP/BOLA), ux-language-guardian (i18n), integration-contract-guardian, `/project-init`, hardened tier, web skills-library, worktree discipline.

## Consequences
- Guardian definitions authored in `docs/skills/guardians/` (adapted).
- The Swift language profile (Rules feeding no-shortcuts/test-coverage) is authored in `docs/specs/swift-quality-profile.md` (the template ships only PHP/Python profiles).
- `CLAUDE.md` gains an operational-safety section adapted for Swift/macOS (no signing/entitlement bypass, etc.).

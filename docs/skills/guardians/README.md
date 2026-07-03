# WisperLocal Guardians

> **Status:** v0.2 — corrected after the 2026-07-02 adversarial review. Adapted from `makeit-web/dev-project-template` for a solo, offline, native-macOS app on a **main-only / no-PR** git flow. See ADR `2026-07-02-004`.

## Shared contract
- Guardians are **read-only**. They never write code — the **Orchestrator coordinates fixes by routing them to the implementing sub-role** (Swift Developer / Whisper-ML), then re-runs the gate. (The Orchestrator itself does not write production code — consistent with `docs/skills/roles/orchestrator.md`.)
- **Default verdict = FAIL** when inputs are missing or unsure ("fail-closed").
- A guardian reports **only to the Orchestrator**, which aggregates, resolves conflicts (higher severity governs), and surfaces to the user. **Zero-finding verdicts auto-pass silently** — only non-empty verdicts reach the user (avoids approval fatigue).
- Verdict format: `Guardian:` · `Status: PASS|FAIL` · `Findings:` (each `severity · file:line · evidence · fix`) · `Blocking: YES|NO`. Any CRITICAL/HIGH ⇒ Blocking.
- **Diff base = a `phase-N-start` git tag** set at phase start (robust on main-only, survives session restarts).

## Gates
- **G1 Pre-plan** — spec-alignment (cheap; per plan).
- **G2 Pre-commit** — scope-creep + no-shortcuts (cheap; **every commit**).
- **Phase gate** — the heavy checks run **only at a phase / named milestone, NOT per commit**: test-coverage + implementation-verifier + privacy-guardian + full/risk-scaled review + doc-consistency (advisory) + spec acceptance + user approval.
- **Build gate** — the privacy egress scan runs in the build (see guardian 6) independent of any agent.

## The 7 guardians

### 1. spec-alignment
Every plan item is grounded in an approved spec + resolved open-questions. **G1.** Inputs: the phase spec, `docs/specs/phase-1-open-questions.md`, `docs/decisions/*`, `CLAUDE.md`, master plan. Findings: `NOT_IN_SPEC`, `CONTRADICTS_SPEC`, `OPEN_QUESTION_UNRESOLVED`, `INPUT_UNAVAILABLE`. Pass: every item cites a spec location; no unresolved open-Q blocks it.

### 2. scope-creep
One commit does only what its message says; **and rejects accidentally staged model/audio/binary/secret files** (extension + size). **G2.** Inputs: commit message + `git diff --cached`. Findings: `UNDECLARED_CHANGE`, `INCIDENTAL_REFACTOR`, `VAGUE_MESSAGE`, `MULTIPLE_CONCERNS`, `FORBIDDEN_FILE` (model/audio/binary/secret). Pass: single declared concern; no forbidden files. *(The bidirectional plan↔diff surplus check belongs to implementation-verifier, not here — no overlap.)*

### 3. no-shortcuts (Swift profile)
The Swift Quality Profile (`docs/specs/swift-quality-profile.md`) + destructive/bypass shell/git + **dependency/source pinning**. **G2 + phase gate.** Findings: `FORCE_UNWRAP`, `UNSAFE_CAST`, `SILENT_TRY`, `SILENCED_CONCURRENCY` (excluding the documented C-boundary carve-out, rule §6), `SHIP_PATH_FATALERROR`, `RT_AUDIO_VIOLATION` (unbounded blocking/alloc in the capture tap — rule §15), `FORBIDDEN_PHRASE`, `DESTRUCTIVE_CMD`, `SIGNING_BYPASS`, `UNPINNED_DEPENDENCY` (`Package.resolved` / whisper.cpp commit not pinned). Pass: zero hits.

### 4. test-coverage (Swift)
Unit for logic modules, integration for pipelines; Swift Testing (XCTest for latency). **Phase gate.** Inputs: diff, spec, `swift test`/`xcodebuild` results. Findings: `MISSING_UNIT_TEST`, `MISSING_INTEGRATION_TEST`, `MISSING_LATENCY_TEST`. Pass: new logic has behavior-defining tests that ran green. *(TDD ordering / "test mirrors code" is a **review-checklist judgment**, not a gated finding — read-only can't see commit ordering on squashed history.)*

### 5. implementation-verifier
The diff matches the approved plan **both directions** (owns the surplus check). **Phase gate (post-code).** Inputs: the phase plan + `git diff <phase-N-start>..HEAD`. Findings: `SURPLUS_CHANGE`, `MISSING_IMPLEMENTATION`, `MISSING_TESTS`. Pass: every plan step ↔ a hunk.

### 6. privacy-guardian ⭐
The core promise — audio/transcripts/telemetry never transmitted. **Phase gate + BUILD gate.** The egress check is a **committed build-phase binary scan (`otool -L`/`nm`)** — not just a source grep — because the app is non-sandboxed. Inputs: diff, Swift profile §(vi), the linked binary, `Package.resolved`. Findings: `NETWORK_EGRESS` (`URLSession`/`Network`/`NWConnection`/`socket`/`getaddrinfo`/`Process`/`NSWorkspace.open`/`WKWebView`/C-level, outside the download module), `PASTEBOARD_EGRESS` (`NSPasteboard` write — Universal Clipboard), `AUDIO_OR_PII_IN_LOG` (incl. `.public` on dynamic strings), `MISSING_MODEL_CHECKSUM` (or checksum not from a committed anchor), `TCC_MISUSE`, `INJECTION_INTO_SECURE_FIELD` (no `IsSecureEventInputEnabled` fail-closed). Pass: build scan clean; no egress/pasteboard path; logs clean; model integrity anchored; TCC correct; secure-field fail-closed.

### 7. doc-consistency
Specs, ADRs, master plan, `CLAUDE.md` mutually consistent. **Phase gate — report-only, NON-BLOCKING** (advisory; a dozen markdown files don't warrant a hard gate). Findings: `NUMERICAL_DRIFT`, `CONFLICTING_CANONICAL_VALUES`, `STALE_REF`.

## Dropped (no target surface)
security-guardian (OWASP/BOLA), ux-language-guardian (i18n), integration-contract-guardian, hardened HMAC tier.

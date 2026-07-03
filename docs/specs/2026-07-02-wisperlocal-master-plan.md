# WisperLocal — Master Build Plan

> **Status:** **APPROVED (v1.0)** by CEO on 2026-07-02 — hardened after a 5-reviewer adversarial pass (see `docs/audits/2026-07-02-plan-review.md`). Each **phase spec still requires approval before its own code.**
> **Date:** 2026-07-02 · **Author:** Claude (CTO)
> **Inputs:** `docs/research/2026-07-02-whisper-deep-research.md`; digests of `makeit-web/dev-project-template` and `_agilno/ai-engineering`; `twostraws/swift-agent-skills` eval. Reference clones in `Studio/Private/_refs/` (outside this repo).
> **Companion docs:** `swift-quality-profile.md`, `docs/skills/guardians/README.md`, ADRs `2026-07-02-001..005`.

---

## 0. How to read this
This is the complete, review-hardened plan: **delivery model** (roles, guardians, gates), **technology decisions**, and the **phased build**. It contains **no code** — code starts only after each phase spec is approved. Deviations from the original `CLAUDE.md` are reconciled in §3 and applied to `CLAUDE.md` itself (testing framework, dual-hardware, risk-scaled review).

## 1. Vision & success criteria
Personal, 100% offline macOS menu-bar dictation app. Global hotkey → speak (primarily Croatian, mixed HR/EN) → transcribed text injected into the focused app. No dock icon, no telemetry, no network except model download.

**Success is a UX bar** (`CLAUDE.md` Principle 6), now with **numeric targets**:
- **Latency:** hotkey→recording-start **≤ 150 ms**; end-of-speech→injected-text **≤ ~1.5 s for short utterances**, and RTF-bounded (measured) for long ones. If long-form dictation fails the bar, the streaming-partials upgrade is earmarked for Phase 5.
- **Accuracy:** *your* Croatian usable with minimal edits (gate in §5 Phase 1).
- **Invisibility:** light RAM (coexists with real apps on 8 GB), never crashes into your workflow, fails visibly (menu-bar state), never silently.

**Privacy promise (scoped precisely):** **WisperLocal never transmits** audio/transcripts/telemetry off the machine. (Once you dictate *into* Gmail/iCloud Notes, that destination app's own sync is outside our control and is the user's responsibility.)

**Language strategy (confirmed):** primary **Croatian**, secondary English — same multilingual model handles mixed HR/EN; the app is language-agnostic, so no English-first detour. Croatian is well-supported (stock models ~9–13% WER band; the `GoranS/whisper-large-v3-turbo-hr-parla` fine-tune reaches 8.66% WER on FLEURS-hr) — HR is the target from day one.

**Two hardware tiers** (see `[[hardware_targets]]`): MacBook Air M1 8 GB (constrained / mobile) · Mac mini M4 16 GB (max accuracy).

---

## 2. Delivery model (the "how")
Adopt the **process spine** of `dev-project-template` (WisperLocal already ~70% mirrors it) + the **universal governance** of `ai-engineering`; drop the web-enterprise machinery (OWASP/BOLA guardian, i18n guardian, PR/Jira/Confluence flow, `/project-init`, hardened HMAC tier, web skills-library).

### 2.1 Roles (per `CLAUDE.md`)
User = **CEO** (approves everything). Claude = **CTO** + 4 sub-roles: Orchestrator, Swift Developer, Whisper/ML Specialist, Quality Reviewer (`docs/skills/roles/`).

### 2.2 Guardians (7, adapted) — full defs in `docs/skills/guardians/README.md`
Read-only; **default FAIL if unsure**; verdict only to the Orchestrator, which **coordinates fixes by routing them to the implementing sub-role** (the Orchestrator itself never writes production code — consistent with `orchestrator.md`), then re-runs the gate.

| Guardian | Enforces | Gate | Blocks on |
|----------|----------|------|-----------|
| spec-alignment | items grounded in approved spec + resolved open-Qs | G1 | not-in-spec, unresolved open-Q |
| scope-creep | one commit = one declared concern (owns single-concern + accidental-binary/audio check) | G2 | undeclared change, multiple concerns, committing model/audio/secret |
| no-shortcuts (Swift) | Swift Quality Profile + destructive/bypass shell/git + **dependency pinning** | G2 + phase gate | any hit |
| test-coverage (Swift) | unit/integration present, ran green (Swift Testing; XCTest for latency) | phase gate | new logic without a green test |
| implementation-verifier | diff ↔ plan bidirectionally (**owns the surplus check** to avoid overlap with scope-creep) | phase gate | surplus / missing implementation |
| privacy-guardian ⭐ | no egress (build-gate binary scan, not just grep), no PII in logs, model checksum vs committed anchor, TCC correctness, fail-closed secure-field | phase gate + build | any egress path, unverified model, secure-field risk |
| doc-consistency | specs/ADRs/plan mutually consistent | phase gate (**report-only, non-blocking**) | — (advisory) |

Dropped (no target surface): security-guardian (OWASP/BOLA), ux-language-guardian (i18n), integration-contract-guardian, hardened HMAC tier.

### 2.3 Gates (main-only, no-PR)
- **G1 Pre-plan** — spec-alignment.
- **G2 Pre-commit** — scope-creep + no-shortcuts. (Cheap; every commit.)
- **Phase gate** — the heavy checks run **only at a phase/named milestone, not on every commit**: test-coverage + implementation-verifier + privacy + full review (§2.5) + spec acceptance criteria + your approval.
- **Diff base:** a `phase-N-start` **git tag** (set at phase start) — robust on main-only, survives session restarts (replaces the fragile ephemeral `task_base_sha`).
- **Zero-finding gates auto-pass silently** — only non-empty verdicts are surfaced to you (avoids approval fatigue).

### 2.4 Operational safety (Swift/macOS-adapted)
- **Destructive:** guard `rm -rf` dynamic paths, `git push --force`, `git reset --hard`, `git clean -fd` → explicit approval.
- **Bypass:** no `--no-verify`, no disabling SwiftLint in the same commit as the fix, no skipped/`.only` tests, **no disabling code signing / entitlements**.
- **Silent failure:** no silent fallback / swallowed errors / scope reduction / "TODO later" (`CLAUDE.md` "STOP, don't pivot").
- **Egress & supply chain:** a **committed build-phase egress scan** (`otool -L` / `nm` for CFNetwork/Network/socket symbols) that **fails the build** — independent of any agent; **pin `Package.resolved` + whisper.cpp commit**; new dependency = review gate; **pre-commit guard rejecting model/audio/binary files** (extension + size).
- **Download scripts:** no `curl | bash`, no `sudo`, HTTPS-only, verify-before-use.
- **External:** `git push` / `gh` only when you ask. **No embedded auto-updater** — updates = manual rebuild.

### 2.5 Review (risk-scaled)
- **Phases 3–5** (app / injection — real attack surface): full **three-pass** — Claude Quality Reviewer + `/codex:review` + `/codex:adversarial-review` (adversarial mandatory).
- **Phases 1–2** (CLI / benchmark — zero attack surface): **Claude Quality Reviewer + one Codex pass**.
- Codex unavailable → passes marked "recommended, skipped with warning," never silent. Quality Reviewer uses the `ios-code-audit` + `_method-core` discipline (read-before-grep, `file:line`, verify every Critical by opening the line).

---

## 3. Technology decisions (ADRs in `docs/decisions/`)

| # | Decision | Status |
|---|----------|--------|
| 001 | **App = Swift** (SwiftUI+AppKit; whisper.cpp C engine). Rejected Tauri/Rust, Python, Electron. | **Accepted** |
| 002 | **Testing = Swift Testing** (default) + **XCTest** (latency `measure`). Updates `CLAUDE.md`. | **Accepted** (CEO delegated) |
| 003 | **whisper.cpp + per-tier models.** Air→`large-v3-turbo q8_0` (fallback q5_0); M4→full `large-v3` q8_0/f16 **or** HR fine-tune. q8_0 baseline. Core ML encoder + **auto Metal fallback** (detect+log+measure). Chunked push-to-talk; **VAD = silence-trim layer (optional), not mandatory auto-stop**; `language=hr`; `initial_prompt` A/B tested. **`single_segment` NOT used blindly** — long utterances handled (max-PTT + visible feedback, validated in Phase 1). | **Proposed** (Phase 1 confirms with our numbers) |
| 004 | **Governance model** (lean guardians + main-only ship flow + risk-scaled review). | **Accepted** |
| 005 | **Signing = stable self-signed, non-sandboxed** (AX injection requires non-sandboxed) from Phase 3 — avoids TCC-grant churn of ad-hoc. Ad-hoc only for throwaway Phase-1/2 CLI. | **Proposed** (Phase 3) |

**Croatian fine-tune** `GoranS/whisper-large-v3-turbo-hr-parla` (Apache-2.0, 8.66% WER FLEURS-hr) is a strong accuracy-tier candidate — but trained on read/parliamentary speech, so HR/EN-mix + spontaneous dictation are tested in Phase 1 before it becomes default. First-trust of any third-party model is an explicit decision (gguf parsers have had CVEs); pin repo revision + SHA.

---

## 4. Swift Quality Profile
Full rules in `docs/specs/swift-quality-profile.md` (v0.2, corrected after review). Headline groups: language safety (no `!`/`as!`/silent `try?`/ship-path `fatalError`); concurrency (Swift-6 strict mode, `@MainActor` only for UI, audio+whisper off-main, `CheckedContinuation`-once, **`whisper_full` on a dedicated thread — it is a blocking call, not a callback**); **C-boundary carve-out** (`whisper_context` `OpaquePointer` = a *permanent* documented non-Sendable wrapper); CoreAudio (`installTap` = background queue → bounded/no-unbounded-blocking; the hard real-time rule is reserved for a *true* render callback; explicit **48 k→16 k `AVAudioConverter` resampling**); error handling; testing; performance/memory; privacy (widened egress list, fail-closed secure-field via `IsSecureEventInputEnabled()`, no `.public` on dynamic log strings).

---

## 5. The phased build
Each phase: **Brainstorm → Spec → Plan → Implement → Test → Review → your approval.** No skipping ahead.

### Phase 1 — whisper.cpp setup + Croatian accuracy benchmark *(no app)*
**Goal:** prove the model works for *your* Croatian; lock per-tier config with **our own** numbers.
**Deliverables:** pinned whisper.cpp build (Core ML + Metal); model-download scripts (gitignored `models/`); CLI `transcribe` + benchmark harness; results in `docs/research/`.
**Scope:** acquire turbo q8_0/q5_0, large-v3 q8_0/f16, HR fine-tune, medium fallback; dataset = Common Voice HR + FLEURS-hr + **your voice samples** (gitignored); measure per (model×quant×machine): **CER *and* WER** with a **pinned Croatian-aware normalization** (casing/punct/diacritics/numbers/EN code-switch), RTF, peak RAM/swap (`vm_stat`); **A/B `initial_prompt`**; **long-utterance / single_segment truncation test**; **thermal endurance** on the fanless Air; test the HR fine-tune on HR/EN-mix + spontaneous speech.
**Exit gate (approved):** **WER ≤ 12%** + subjective ≥ 4/5 on your samples + beats macOS dictation; **report both CER & WER**; **hard-stop** if no model clears the bar. Stretch WER ≤ 8%.

### Phase 2 — audio capture + chunked transcription pipeline *(CLI)*
**Scope:** `AVAudioEngine` capture with **explicit 48 k→16 k resampling**, lock-free ring buffer; **`whisper_full` dispatched to a dedicated thread**; VAD (Silero) for **silence-trim** (auto-stop is a separate opt-in mode); decode config per ADR-003; **empty/no-speech → brief "no speech" state**; **mic route-change/disconnect** (`AVAudioEngineConfigurationChange`, AirPods drop) handled → stop cleanly + error state.
**Exit:** latency meets §1 targets on both machines (XCTest `measure`); accuracy holds.

### Phase 3 — menu-bar shell + hotkey + permissions + model provisioning
**Scope:** `NSStatusItem` + `LSUIElement`; **prefer `RegisterEventHotKey`** (event tap only with documented need) + **hotkey-conflict detection** (registration failure → surfaced + rebindable); **onboarding / permission flow** — sequenced Microphone → Accessibility → Input-Monitoring, **denied-state UI with `x-apple.systempreferences:` deep-links + re-check on foreground**; **first-run model provisioning** — storage in `~/Library/Application Support/WisperLocal/`, disk-space precheck, resumable HTTPS download, **on-device SHA256 vs a committed constant**, failure/retry UX, "model missing" menu-bar state; **runtime model selection by chip + *available* RAM/pressure** (dynamic drop to q5_0), Core ML "optimizing" first-run + idle model-unload; **stable self-signed** (ADR-005).
**Exit:** hotkey works, permissions requested+recovered correctly, a model provisions on a clean machine, state visible.

### Phase 4 — text injection via Accessibility API
**Scope:** **capture the frontmost app at hotkey-down** (`NSWorkspace.frontmostApplication` / AX focused element) and **re-target it at injection** (LSUIElement never steals focus); inject via `AXUIElement` (**preferred over pasteboard** — pasteboard risks Universal-Clipboard iCloud sync); **fail-closed secure-field** — check `IsSecureEventInputEnabled()` before any post + fail-closed on unknown subrole + TOCTOU re-check; Croatian diacritics (č/ć/š/ž/đ) + keyboard-layout correctness; **adversarial review mandatory**.
**Exit:** **E2E happy-path acceptance** — real HR dictation into Slack/Mail/browser, diacritics + focus preserved, never into a password field.

### Phase 5 — polish
**Scope:** settings (model/tier override, hotkey rebind, **user-editable domain prompt** if Phase-1 A/B shows HR benefit), HR/EN/auto language selector if it helps, visual/audio feedback, auto-punctuation validation, launch-at-login (`SMAppService`), **model update/versioning + repair (re-download corrupted)**, log rotation. **Streaming-partials upgrade** if long-form latency failed the §1 bar. **No embedded updater.**
**Exit:** daily-usable; you sign off "ship for personal use."

---

## 6. Cross-cutting
- **Privacy (enforced, not just intended):** build-phase egress scan fails the build; widened egress detection (deps/C/DNS/IPC/pasteboard); committed checksum anchor; no `.public` transcript logs; pre-commit model/audio guard. Benchmark logs use **hashed IDs, never absolute sample paths**.
- **Git:** single repo, `main` only, conventional commits, push only when you ask, `ship`-style flow. Never commit models/build/audio/secrets.
- **Testing:** Swift Testing (unit/integration) + XCTest (latency) + manual UI checklist; no phase done without green tests + review.
- **Reproducibility:** pin whisper.cpp commit + toolchain + model rev; log model SHA256 + hashed hardware id per benchmark.

---

## 7. Decisions — resolved (CEO approved 2026-07-02)
1. **Q3 exit criteria:** WER ≤ 12% + subjective ≥ 4/5 + beat Apple dictation + hard-stop; report both CER & WER with pinned normalization. ✅
2. **Testing:** Swift Testing + XCTest-for-latency (ADR-002). ✅
3. **Risk-scaled review:** full three-pass P3–5, light P1–2. ✅
4. **Latency targets** (§1) + **stable self-signed** (ADR-005). ✅

**Still needed from you — not blocking Phase 1 kickoff:**
- **Q4 domain vocabulary** — your frequent terms (company/people/tech/tools/places) for the `initial_prompt` A/B. Send when convenient.
- **Voice samples** — a handful of your real Croatian (and HR/EN-mix) recordings for the subjective gate; only you can provide these. I'll give a short "how to record" note when Phase 1 build is ready.

**Next:** Phase 1 spec (`docs/specs/phase-1-whisper-setup.md`) → your approval → build.

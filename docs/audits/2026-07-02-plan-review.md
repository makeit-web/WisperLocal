# Plan Review — WisperLocal Master Plan (5-reviewer adversarial pass)

> **Date:** 2026-07-02 · **Author:** Claude (CTO, Orchestrator)
> **Reviewed:** master plan v0.1, Swift quality profile, guardians, ADRs 001–004, research doc.
> **Method:** 5 parallel adversarial reviewers, distinct lenses. **Outcome:** master plan → v1.0, profile → v0.2, guardians → v0.2, ADR-003 revised, ADRs 005 added. Approved by CEO 2026-07-02.

## Verdicts
| Lens | Verdict | Theme |
|------|---------|-------|
| Completeness vs user needs | FIX-FIRST | product runtime-path gaps |
| Technical soundness | FIX-FIRST | direction sound; 4 spec-level fixes |
| Privacy & safety | FIX-FIRST | intent strong, *enforcement* not airtight |
| Scope & governance | TRIM | lighten process; +2 cheap tightens |
| Doc consistency | MINOR-FIXES | staleness drift; decisions all consistent |

## Key findings & resolutions

**Product (Completeness) — all folded into phases:**
- ⛔ *In-app model provisioning on a clean machine undefined* → **Phase 3** deliverable (storage path, disk check, resumable download, on-device checksum, failure UX, "model missing" state). ✅
- *Frontmost-target-app capture unspecified* → **Phase 4** (capture at hotkey-down, re-target at injection, LSUIElement never frontmost). ✅
- *Latency has no numeric acceptance* → **§1 targets** (≤150 ms / ≤~1.5 s short) as Phase 2/4 gates; streaming-partials → Phase 5. ✅
- *Permission-denial / onboarding not a deliverable* → **Phase 3** onboarding flow (sequenced TCC + deep-links + re-check). ✅
- Model update/repair → Phase 5; mic route-change → Phase 2; hotkey-conflict → Phase 3; E2E happy-path → Phase 4; resampler → Phase 2. ✅

**Privacy (enforcement hardening):**
- *Non-sandboxed ⇒ source-grep insufficient* → **build-phase binary egress scan (`otool`/`nm`) that fails the build**. ✅
- *Egress via deps/C/DNS/IPC/pasteboard* → widened detection + `Package.resolved` pinning; **Universal-Clipboard** → prefer AX over pasteboard. ✅
- *Checksum has no trust anchor* → **committed SHA constant + pinned HF revision**. ✅
- *`CGEventPost` blind-posts into password fields* → **`IsSecureEventInputEnabled()` fail-closed + TOCTOU re-check**. ✅
- *Privacy enforcement is a skippable agent step* → **committed build gate, agent-independent**. ✅
- Transcript-in-logs (`.public`), ad-hoc-signing TCC churn (→ ADR-005), keylogger-grade event tap (→ prefer `RegisterEventHotKey`), gguf-parser CVE / TOFU, no-updater, download-script hardening, scoped privacy promise. ✅

**Technical:**
- *`single_segment` silently truncates >30 s* → max-PTT + visible feedback (ADR-003). ✅
- *`whisper_full` is blocking, not a callback* → dedicated thread (profile §13). ✅
- *CER gate vs WER numbers* → **gate on WER ≤ 12%**, report both, pinned normalization (ADR-003). ✅
- *`whisper_context` legitimately non-Sendable* → permanent documented carve-out (profile §6). ✅
- *`installTap` is a background queue, not a render callback* → rule §15 softened to "no unbounded blocking"; resampler scoped. ✅
- VAD "optional layer" framing; available-RAM model selection. ✅

**Governance (trim):**
- G3 "per change" ambiguity → **heavy checks at phase/milestone only**; intra-phase = G2. ✅
- fragile `task_base_sha` → **`phase-N-start` git tag**. ✅
- three-pass every phase → **risk-scaled** (full P3–5, light P1–2). ✅
- scope-creep/impl-verifier surplus overlap → de-duped; `ANTIPATTERN_TEST` → review judgment; doc-consistency → report-only. ✅
- +2 tightens: **accidental model/audio commit guard**; **dependency pinning**. ✅
- zero-finding gates auto-pass silently. ✅

**Doc consistency:** master-plan self-state (§3/§4/§7), ADR statuses, "Orchestrator coordinates (not implements)", Q1/Q7 back-filled, Next-steps matrix, whisper-ml role scope, `CLAUDE.md` deviations (testing, dual-hardware, risk-scaled review). ✅ (role + CLAUDE.md applied in the finalize pass.)

## Validated as sound (no change)
Per-tier model split; turbo ≠ large-v3 for HR; Core ML characterization; chunked-PTT over streaming; M4 running full large-v3; `WhisperContext` actor + continuation shape; the CoreAudio carve-out concept; privacy-guardian as the crown-jewel gate; the correct template drops (OWASP/i18n/PR/HMAC); the 4 sub-roles; hard-stop exit discipline; "our own numbers, not research numbers".

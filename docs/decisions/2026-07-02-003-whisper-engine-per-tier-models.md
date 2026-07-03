# 003. Whisper engine config + per-tier model strategy

**Date:** 2026-07-02
**Status:** Proposed (Phase 1 benchmark confirms with our own numbers)
**Deciders:** Claude (CTO, recommends) + User (CEO, approves)

## Context
Engine locked to whisper.cpp. Deep research (`docs/research/2026-07-02-whisper-deep-research.md`, adversarially verified) corrected several assumptions: `large-v3-turbo` ≠ full `large-v3` for Croatian; full large-v3 does not fit comfortably on 8 GB alongside a target app; Croatian is quantization-sensitive; `initial_prompt` may **degrade** non-English WER. Two tiers: Air M1 8 GB, Mac mini M4 16 GB.

## Decision
- **Air M1 8 GB:** `large-v3-turbo q8_0` default; fallback q5_0 **selected dynamically by *available* RAM/memory pressure at launch**, not just total `physicalMemory`.
- **Mac mini M4 16 GB:** full `large-v3` (q8_0/f16) **or** the Croatian fine-tune — Phase 1 decides.
- **Quantization:** q8_0 baseline (never q4/q5 as default for Croatian).
- **Acceleration:** Core ML encoder ON; **Metal fallback is whisper.cpp's automatic behaviour** — we detect + log + measure it, it is not a bespoke component.
- **Pipeline:** chunked push-to-talk. **`single_segment` is NOT used blindly** — it silently truncates audio past the first window (a "fail-silently" violation of `CLAUDE.md`); we enforce a **max PTT duration (~25–30 s) with visible feedback**, and validate long-utterance handling in Phase 1.
- **VAD (Silero):** a **silence-trim layer (optional)**, not a mandatory auto-stop — in a key-up-bounded PTT model, auto-stop could cut a mid-sentence pause. Auto-stop is a separate opt-in mode.
- **Bridge:** `whisper_full` is a **synchronous blocking C call** → dispatched to a dedicated thread and bridged via `withCheckedContinuation` (never awaited on the cooperative pool). See Swift profile §13.
- **Decode:** `language=hr` (forced, not auto-detect), `translate=false`, temperature 0 + fallback; default thresholds.
- **`initial_prompt`:** **A/B tested in Phase 1**, not assumed to help.

## Exit metric (approved)
- Gate on **WER ≤ 12%** (achievable: fine-tune 8.66%, stock turbo 12.73% on FLEURS-hr) + subjective ≥ 4/5 on user samples + beat macOS dictation; **hard-stop** otherwise. Stretch WER ≤ 8%.
- **Report both CER and WER** with a **pinned Croatian-aware normalization** (casing/punctuation/diacritics/numbers/EN code-switch) — WER/CER are normalization-sensitive; CER runs ~2–4× lower than WER for morphologically rich HR, so it is not the gate metric.

## Consequences
- Refines `CLAUDE.md`'s "large-v3 default, medium fallback" into a per-tier strategy (applied to `CLAUDE.md` once Phase 1 confirms).
- Swift app selects the model at runtime by chip + available RAM (not a hard-coded path) — see `[[hardware_targets]]`.
- Phase 1 must produce our own CER/WER + RTF + peak-RAM numbers, and test the fine-tune on HR/EN-mix + spontaneous speech, before this is marked Accepted. First-trust of any third-party model is an explicit decision (pin repo revision + SHA; gguf parsers have had CVEs).

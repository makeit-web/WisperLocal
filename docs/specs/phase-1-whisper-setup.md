# Phase 1 — whisper.cpp Setup & Croatian Accuracy Benchmark (Spec)

> **Status:** DRAFT (v0.1) — **awaiting CEO approval before any code.**
> **Date:** 2026-07-02 · **Author:** Claude (CTO / Whisper-ML Specialist)
> **Grounded in:** master plan §5 Phase 1 · ADR-003 (engine/models) · `docs/research/2026-07-02-whisper-deep-research.md` · the 5-reviewer audit.
> **Reminder:** Phase 1 is **CLI + benchmark only — no Swift, no app.**

## 1. Goal
Prove whisper.cpp transcribes **your** Croatian well enough to build on, and lock the per-tier config (model, quant, flags, decode params) using **our own measured numbers** — not literature. Exit with a defensible model choice per tier, or a hard-stop.

## 2. Functional requirements
- **FR1** — Reproducible whisper.cpp build on Apple Silicon: Core ML encoder + Metal, pinned commit, every flag documented.
- **FR2** — Model acquisition scripts → gitignored `models/`, each with **SHA256 verified against a committed constant** + pinned source revision; never in git.
- **FR3** — A `transcribe <audio>` CLI path (whisper.cpp binary wrapper) using the ADR-003 decode config (`language=hr`, `translate=false`, temp 0 + fallback).
- **FR4** — A benchmark harness that runs the **model × quant × machine** matrix over the datasets and computes **CER *and* WER** with a **pinned Croatian-aware normalization**, plus **RTF** and **peak RAM/swap**.
- **FR5** — `initial_prompt` **A/B** (with vs without domain prompt).
- **FR6** — Results in `docs/research/phase-1-benchmark-YYYY-MM-DD.md` + per-sample CSV.

## 3. Non-functional
- **Determinism:** temperature 0, fixed seed, logged thread count.
- **Reproducibility:** log whisper.cpp commit SHA, model SHA256, quant, flags, toolchain versions, OS version, **hashed** machine id, dataset version.
- **Privacy:** user audio in gitignored `test-audio/`, never leaves the machine; logs use **hashed IDs, never absolute sample paths** (Swift-profile-equivalent rule for the harness).
- **Offline** after the one-time model/dataset download.

## 4. Out of scope (later phases)
Swift/app code, menu bar, hotkey, injection (Phase 2+); real-time streaming (Phase 2); production VAD (Phase 2 — Phase 1 benchmarks on pre-clipped audio); auto-punctuation tuning (Phase 5).

## 5. Design

### 5.1 Toolchain (tool-level decision — CTO)
- **whisper.cpp** pinned to a specific tag/commit — chosen at build time, **verified to build the Core ML path cleanly**, logged as an ADR (ADR-006 at build time).
- **Build:** `cmake -B build -DWHISPER_COREML=1 -DCMAKE_BUILD_TYPE=Release` (Metal auto-enabled on Apple Silicon). Each flag documented; Metal fallback is whisper.cpp's automatic behaviour (detect + log).
- **Core ML conversion:** whisper.cpp `generate-coreml-model.sh` in a **pinned Python 3.11 + coremltools 8.x + torch + numpy<2** env — exact versions **verified & frozen to a `requirements.txt` at build time** (fragile toolchain; do not guess versions).
- **Harness language: Python 3.11** (same env as the Core ML tools) — WER/CER via a vetted library (e.g. `jiwer`) + our custom Croatian normalization. *(Rationale: no Swift needed in Phase 1; Python has the scoring + Core ML tooling.)*

### 5.2 Models (per-tier matrix)
| Tier | Models to benchmark |
|------|--------------------|
| Air M1 8 GB | `large-v3-turbo` q8_0, q5_0 |
| Mac mini M4 16 GB | full `large-v3` q8_0, f16 |
| Cross (accuracy candidate) | `GoranS/whisper-large-v3-turbo-hr-parla` (Apache-2.0) — **verify clean GGML conversion first** |
| Fallback | `medium` q8_0/q5_0 |

Each via a download script from the official source, SHA256-checked, source revision pinned. gguf/ggml parsers have had CVEs → treat any third-party model as an explicit first-trust decision.

### 5.3 Datasets
- **Common Voice HR** (primary) — verify license permits local benchmark use.
- **FLEURS-hr** (secondary).
- **User voice samples** — 10–20 real HR + HR/EN-mix utterances in gitignored `test-audio/` (provided by user; only he can).
- Small **EN** set for the secondary-language sanity check.

### 5.4 Metrics & normalization (the review's key requirement)
- **Report BOTH CER and WER.** Gate metric = **WER ≤ 12%** (ADR-003); CER reported for stability comparison (it runs ~2–4× lower on morphologically rich HR, so it is *not* the gate).
- **Pinned Croatian-aware normalization** applied to hypothesis + reference before scoring — a single fixed, unit-tested function: lowercase; punctuation strip/normalize; a documented number policy (digits ↔ words — pick one); **preserve diacritics** (č/ć/š/ž/đ); defined EN code-switch handling.
- **Subjective score** — user rates 1–5 per sample (correction effort), separate rubric.
- **Latency:** RTF (×-realtime) per run. **Memory:** peak RSS + swap via `vm_stat` sampling.

### 5.5 Runs
For each (model × quant × machine): transcribe Common Voice HR + FLEURS-hr + user samples, **with and without Core ML**; log CER, WER, RTF, peak RAM. Plus:
- **`initial_prompt` A/B** — each model with + without the domain prompt on user samples + a subset.
- **Long-utterance / `single_segment` test** — a dedicated >30 s HR sample to confirm **no silent truncation** with the chosen config (max-PTT strategy validated).
- **Thermal endurance** — sustained back-to-back runs on the fanless Air; watch RTF degradation over N minutes.
- **Apple baseline** — same user samples through macOS built-in dictation (manual) for the "beat Apple" check.

### 5.6 Reproducibility record
Results → `docs/research/phase-1-benchmark-YYYY-MM-DD.md` + per-sample CSV, each run stamped with the §3 reproducibility fields.

## 6. Acceptance criteria (exit gate)
- **AC1** — whisper.cpp builds reproducibly (Core ML + Metal) on both machines; flags documented.
- **AC2** — all matrix models acquire + checksum-verify via scripts; nothing model-sized in git.
- **AC3** — harness computes normalized CER + WER deterministically; **harness is unit-tested**.
- **AC4** — full matrix run completed on both machines; results + CSV in `docs/research/`.
- **AC5** — `initial_prompt` A/B, long-utterance, thermal, and Apple-baseline results recorded.
- **AC6 — EXIT GATE:** ≥1 config achieves **WER ≤ 12% + subjective ≥ 4/5** on user samples **and beats macOS dictation** on ≥1 metric. If none → **HARD-STOP**: write a decision record, reconsider (mic / model / prompt / fine-tune) before Phase 2. Stretch WER ≤ 8%.
- **Review:** Claude Quality Reviewer + one Codex pass (risk-scaled — Phase 1).

## 7. Harness test plan
Unit tests (pytest) for: CER/WER computation (known hyp/ref pairs), the **Croatian normalization function** (case, punctuation, diacritics, numbers, EN code-switch), RTF calculation, result serialization. *(The app's Swift Testing suite starts Phase 2/3.)*

## 8. Inputs needed / open questions
- **User:** domain vocabulary list (for the `initial_prompt` A/B).
- **User:** 10–20 personal HR + HR/EN-mix voice samples → gitignored `test-audio/`.
- Verify Common Voice HR license for local benchmark use (at implementation).
- Exact whisper.cpp tag + Core ML toolchain versions — **verified & pinned at build time**, logged as ADR-006.

## 9. Risks
- **Core ML toolchain fragility** (Python/coremltools/torch/numpy) → pin + freeze; Metal-only fallback if conversion fails (STOP-and-report if it fails, don't silently drop Core ML).
- **HR fine-tune GGML conversion** may fail or behave differently on HR/EN-mix / spontaneous speech → test explicitly; keep stock turbo as fallback.
- **8 GB RAM pressure** on the Air → measure real *available* RAM; drop to q5_0 dynamically.
- **Non-reproducible scores** if normalization drifts → normalization is a single pinned, tested function.

## 10. Next
On approval → `docs/specs/phase-1-plan.md` (concrete ordered build steps) → then build.

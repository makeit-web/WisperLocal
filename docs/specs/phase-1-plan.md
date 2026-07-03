# Phase 1 — Implementation Plan

> **Status:** DRAFT (v0.1) — **awaiting CEO approval before any code.**
> **Date:** 2026-07-02 · **Author:** Claude (CTO)
> **Implements:** `docs/specs/phase-1-whisper-setup.md`. Ordered steps; each ends with a verification. `phase-1-start` git tag is set at Step 1 (diff base). No Swift.

## Legend
🔨 = produces code/artifact · ✅ = verification/gate · 🙋 = needs a user input · 🚦 = STOP-and-report if it fails (per `CLAUDE.md`).

## Steps

**S0 — Preflight** 🔨
- Set the `phase-1-start` git tag. Confirm toolchain present: Xcode Command Line Tools, `cmake`, Python 3.11. Create a `benchmark/` (harness) + `scripts/` (download/build) layout; `models/` and `test-audio/` already gitignored.
- ✅ Tools report expected versions; dirs exist; nothing model-sized tracked by git.

**S1 — Pin & build whisper.cpp** 🔨🚦
- Choose a specific whisper.cpp tag/commit; clone into a build location (not committed). Build: `cmake -B build -DWHISPER_COREML=1 -DCMAKE_BUILD_TYPE=Release`. Record the exact tag + every flag.
- ✅ Binary builds; `whisper-cli --help` runs; Metal auto-detected in logs.
- 🚦 If the Core ML build path fails → STOP, report options (different tag / Metal-only), don't silently drop Core ML.
- → Write **ADR-006** (whisper.cpp tag + toolchain pins).

**S2 — Core ML toolchain + encoder conversion** 🔨🚦
- Create the pinned Python 3.11 env (coremltools 8.x / torch / numpy<2); freeze to `benchmark/requirements-coreml.txt`. Run `generate-coreml-model.sh` for the base models.
- ✅ `.mlmodelc` produced; a smoke transcription runs via the Core ML encoder.
- 🚦 Conversion fragility failure → STOP, report (version matrix) before proceeding.

**S3 — Model download scripts + integrity** 🔨
- `scripts/download-models.sh` fetching the per-tier matrix (turbo q8_0/q5_0, large-v3 q8_0/f16, medium) + the `GoranS` HR fine-tune, from official/pinned revisions; verify each SHA256 against a committed constants file.
- ✅ Each model downloads + checksum matches; re-run is idempotent; `git status` shows no model files.
- Verify the **HR fine-tune converts to GGML cleanly** (else keep stock turbo as the accuracy candidate + note it).

**S4 — `transcribe` CLI wrapper** 🔨
- Thin wrapper over `whisper-cli` applying the ADR-003 decode config (`language=hr`, `translate=false`, temp 0 + fallback, no blind `single_segment`).
- ✅ `transcribe sample.wav` → plausible Croatian text on a hand-checked clip.

**S5 — Scoring core (TDD — tests first)** 🔨✅
- Write tests first for: the **Croatian normalization** function and **CER/WER** computation (known hyp/ref pairs incl. diacritics + EN code-switch + a number case). Then implement to green.
- ✅ `pytest` green; normalization is deterministic and documented.

**S6 — Benchmark harness** 🔨✅
- Orchestrate the (model × quant × machine) matrix: run `transcribe` over a dataset, score CER+WER (normalized), measure RTF, sample peak RAM/swap via `vm_stat`; emit per-sample CSV + a summary; stamp reproducibility fields (SHA, hashed machine id, versions). Unit-test RTF calc + serialization.
- ✅ Dry-run on a tiny fixture set produces a correct CSV + summary; logs contain no absolute sample paths (hashed IDs).

**S7 — Datasets** 🔨🙋
- `scripts/get-datasets.sh` for Common Voice HR + FLEURS-hr (**verify Common Voice license** for local benchmark use first). 🙋 **User provides** 10–20 HR + HR/EN-mix voice samples → `test-audio/` (gitignored). 🙋 **User provides** the domain vocabulary list for the prompt.
- ✅ Datasets present; user samples loaded; vocab captured into an `initial_prompt` file.

**S8 — Run the matrix (Air)** 🔨✅
- Full matrix on the MacBook Air M1 8 GB, with + without Core ML; `initial_prompt` A/B; long-utterance (>30 s) truncation check; thermal endurance (sustained runs).
- ✅ Results + CSV written; RAM/swap + RTF captured; long-utterance shows no silent truncation.

**S9 — Run the matrix (Mac mini)** 🔨✅
- Same on the Mac mini M4 16 GB (adds full large-v3 f16 + the HR fine-tune at comfort). Cross-machine comparison.
- ✅ Results + CSV; cross-machine table assembled.

**S10 — Apple baseline + subjective scoring** ✅🙋
- Run the user samples through macOS built-in dictation (manual). 🙋 **User rates** 1–5 (correction effort) per sample per top config.
- ✅ Baseline + subjective scores recorded.

**S11 — Results report + decision** 🔨✅
- Write `docs/research/phase-1-benchmark-YYYY-MM-DD.md` (summary + CSV links + interpretation + per-tier recommendation).
- Evaluate the **exit gate (AC6)**: WER ≤ 12% + subjective ≥ 4/5 + beat Apple.
  - **Pass** → write the model-choice ADR (mark ADR-003 Accepted with real numbers).
  - **Fail** → 🚦 **HARD-STOP** decision record; reconsider before Phase 2 (do not proceed).

**S12 — Review & phase gate** ✅
- Risk-scaled review (Quality Reviewer + one Codex pass). Guardians at the phase gate: no-shortcuts, test-coverage, privacy (no egress beyond model/dataset download; hashed logs), implementation-verifier (diff ↔ this plan). doc-consistency advisory.
- ✅ Green tests + review complete → **present to CEO for phase sign-off.** Phase 2 opens only after approval.

## Dependencies / critical path
S0→S1→S2→S3→S4→S5→S6 are Claude-only and sequential-ish. **S7 (user samples + vocab), S10 (subjective ratings)** are the only user-gated steps — the matrix mechanics (S8/S9) can run on Common Voice/FLEURS first, then re-scored on user samples when provided. Nothing here writes app code.

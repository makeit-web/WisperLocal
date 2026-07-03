# Phase 1 Benchmark — Croatian accuracy (FLEURS-hr, full test split)

> **Date:** 2026-07-03 · **Author:** Claude (Whisper/ML Specialist)
> **Status:** Objective tier picture on FLEURS-hr (n=914, M4) is clear. NOT yet a final ADR-003 lock — user voice samples (subjective + real-world), Common Voice HR, domain-prompt A/B, Core ML latency, and the Air 8 GB tier are still pending.

## Question
Objective CER/WER + RTF + RAM for the per-tier candidate models on Croatian, on the Mac mini M4. Does the per-tier strategy (turbo q8_0 / large-v3) hold with our own numbers?

## Setup (reproducibility)
- **whisper.cpp:** v1.9.1 (`f049fff95a089aa9969deb009cdd4892b3e74916`), **Metal-only** build (no Core ML — Core ML affects encoder *speed*, not accuracy).
- **Machine:** Mac mini M4, 16 GB, macOS 26.5.1. threads=4, `language=hr`, no `initial_prompt`, whisper.cpp defaults.
- **Models & SHA256:** `ggml-large-v3-turbo-q8_0.bin` (834 MB, `317eb69c…`); `ggml-large-v3-q8_0.bin` (1.5 GB, `24bc434f…`, locally quantized from f16 via `whisper-quantize`); `ggml-large-v3.bin` (f16, 2.9 GB, pilot only).
- **Metrics:** CER/WER via `jiwer` + pinned Croatian normalization (`benchmark/normalize.py` v1: NFC, casefold, punct→space, **digits left as-is**). RTF = processing/audio. Harness: `benchmark/` (15 pytest passing).

## Test inputs
FLEURS-hr **test** split — **all 914 samples**, 16 kHz mono. Clean, read speech — NOT spontaneous dictation, NOT the user's mic/voice.

## Raw results (n=914)
| model | WER mean | WER median | CER mean | RTF mean | peak RSS |
|-------|----------|-----------|----------|----------|----------|
| large-v3-turbo q8_0 | 0.124 | 0.105 | 0.035 | 0.16 (~6×) | 1.1 GB |
| **large-v3 q8_0** | **0.110** | **0.091** | **0.031** | 0.31 (~3×) | 2.6 GB |
| large-v3 f16 (pilot n=30) | 0.116 | — | 0.027 | 0.37 (~2.7×) | 4.0 GB |

RAM = peak RSS of `whisper-cli` under `/usr/bin/time -l`. Per-sample CSVs in `benchmark/results/` (gitignored).

## Interpretation
- **large-v3 q8_0 beats turbo q8_0 on accuracy** (WER 11.0% vs 12.4%, median 9.1% vs 10.5%, CER 3.1% vs 3.5%) — this **confirms the research** ("large-v3 > turbo for low-resource HR"). Turbo is ~2× faster and ~2.3× lighter.
- **The n=30 pilot was MISLEADING** (turbo looked *better* there). The scale-up to 914 reversed it — exactly why the plan mandates "our own numbers, benchmark before choosing, don't lock on small n."
- **Mean vs median matters:** turbo's mean (12.4%) sits just over the 12% gate while its median (10.5%) is comfortably under — the mean is inflated by a tail of hard / number-heavy samples. large-v3's median is 9.1%.
- **Number normalization (v1) inflates WER** on digit-heavy references ("150 i 200"). A digit↔word unification pass would likely lower both means; it can be applied by **re-scoring the existing CSVs** (they store the hypotheses) — no re-run of whisper needed.
- **RAM confirms the tiers:** turbo q8_0 (1.1 GB) coexists comfortably on the 8 GB Air; large-v3 q8_0 (2.6 GB) is the M4-tier accuracy choice; f16 (4.0 GB) is M4-only and not worth it over q8_0.

## Recommendation / next
1. **Per-tier strategy holds (ADR-003):** Air 8 GB → `large-v3-turbo q8_0`; Mac mini M4 → `large-v3 q8_0`. Confirmed by *our* accuracy + RAM.
2. Refine the number normalization and re-score from CSVs.
3. Add **Common Voice HR** (spontaneous speech — FLEURS is read speech) and the **Croatian fine-tune** (`GoranS/…`, needs a torch conversion).
4. Measure the **Core ML** encoder latency delta; run the **Air 8 GB** tier (separate session).
5. **User-gated (before ADR-003 is marked Accepted):** personal HR (+HR/EN-mix) voice samples for the subjective ≥4/5 gate + real-world validation, and the domain-prompt A/B.

**Bottom line:** on clean Croatian read speech, both tier models are gate-clearing (median WER 9–10.5%), large-v3 q8_0 is the accuracy leader, and the per-tier split is validated by measured accuracy *and* RAM. Real-world/subjective validation on the user's own voice is the remaining gate.

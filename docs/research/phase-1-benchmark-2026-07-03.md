# Phase 1 Benchmark — first Croatian numbers (FLEURS-hr pilot)

> **Date:** 2026-07-03 · **Author:** Claude (Whisper/ML Specialist)
> **Status:** PILOT (n=30) — encouraging, but NOT a model-selection decision. Scale-up required before ADR-003 is marked Accepted.

## Question
What objective CER/WER does whisper.cpp give on Croatian, on the Mac mini M4, for the Air-tier model (`large-v3-turbo q8_0`) vs the full `large-v3`? Does anything clear the WER ≤ 12% gate?

## Setup (reproducibility)
- **whisper.cpp:** v1.9.1 (commit `f049fff95a089aa9969deb009cdd4892b3e74916`), **Metal-only build** (`WHISPER_COREML=0`) — no Core ML yet (Core ML affects encoder *speed*, not accuracy).
- **Machine:** Mac mini M4, 16 GB, macOS 26.5.1.
- **Decode:** `language=hr`, no `initial_prompt`, threads=4, whisper.cpp defaults (temp fallback), `-nt`.
- **Models:** `ggml-large-v3-turbo-q8_0.bin` (834 MB, SHA256 `317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1`); `ggml-large-v3.bin` (f16, 2.9 GB).
- **Metrics:** CER + WER via `jiwer`, with the pinned Croatian normalization (`benchmark/normalize.py` v1: NFC, casefold, punctuation→space, collapse ws, **digits left as-is**). RTF = processing/audio (<1 = faster than real time).
- **Harness:** `benchmark/` (unit-tested: 15 passing).

## Test inputs
FLEURS-hr **test** split (914 total), **first 30 samples**, 16 kHz mono. Clean, read speech — NOT spontaneous dictation, NOT the user's mic/voice.

## Raw results
| model | WER mean | WER median | CER mean | RTF mean |
|-------|----------|-----------|----------|----------|
| large-v3-turbo q8_0 | **0.101** | 0.103 | 0.031 | **0.16** |
| large-v3 f16 | 0.116 | 0.115 | **0.027** | 0.37 |

Per-sample CSVs: `benchmark/results/*.csv` (gitignored).

## Interpretation
- **Both clear the 12% WER gate** on this set. Turbo q8_0 ~10% WER at ~6× real time; large-v3 f16 ~12% WER at ~2.7× real time.
- **Turbo ≈ large-v3 here** — turbo even edges WER, large-v3 edges CER. This mildly contradicts the research's "turbo materially worse for low-resource" claim, **but n=30 is far too small to conclude** — the gap is within sampling noise. CER (more stable) marginally favors large-v3, as expected.
- **Number normalization inflates WER** on digit-heavy samples (reference "150 i 200" vs a spelled-out hypothesis). The v1 normalization keeps digits as-is; a digit↔word unification pass would likely *lower* WER further.
- RTF is excellent on M4 even without Core ML — latency is clearly not a problem on this tier.

## Recommendation / next
1. **Do NOT lock the model** on n=30. Scale to the full 914 FLEURS-hr + add Common Voice HR.
2. Refine the normalization (number handling) and re-score.
3. Add the **Croatian fine-tune** `GoranS/whisper-large-v3-turbo-hr-parla` (needs a torch-based GGML conversion) — the research's 8.66% candidate.
4. Quantize `large-v3 q8_0` locally (`whisper-quantize`) to match ADR-003 (only f16/q5_0 are prebuilt).
5. Measure peak RAM/swap; run the **Core ML** encoder path for the latency delta.
6. Then the parts that need the user: **his voice samples** (subjective gate + real-world), the **domain-prompt A/B**, and the **Air 8 GB tier** (separate session).

**Bottom line:** the pipeline is proven and Croatian accuracy is already gate-clearing on clean read speech — a strong start, pending the scale-up and real-world/subjective validation before ADR-003 is finalized.

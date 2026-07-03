# Whisper Deep Research - WisperLocal

> **Status:** Deep-research output (v1). **Date:** 2026-07-02. **Author:** Claude (CTO / Whisper-ML specialist).
> **Method:** multi-agent fan-out (6 research slices) + adversarial verification (6 decision-critical claims) + synthesis. Engine locked = whisper.cpp.
> **⚠️ Caveat:** accuracy/latency/RAM numbers here are *illustrative* from public sources. Phase 1 MUST produce our own Croatian WER/CER + on-device RTF/RAM figures before any config is locked.

## TL;DR (decisions this informs, 5-8 bullets)

- **Model is a per-tier, accuracy-vs-latency tradeoff — NOT one model everywhere.** For Croatian, `large-v3-turbo` is *not* equal to full `large-v3`; OpenAI states turbo performs like large-v2, and large-v3 is 10-20% better than large-v2 across FLEURS/Common Voice, so expect turbo to be ~1-2.5 WER points worse on Croatian, with the gap widening on spontaneous/noisy/code-switched speech (https://github.com/openai/whisper/discussions/2363, https://github.com/openai/whisper/discussions/1762, https://huggingface.co/GoranS/whisper-large-v3-turbo-hr-parla).
- **Air M1 8GB default = quantized `large-v3-turbo` (q8_0, fallback q5_0).** Full large-v3 (even quantized) is memory-tight on 8GB and only ~1.0x RTF at best on M1 ("transcribe-then-wait") — it swaps once macOS + a target app are resident (https://justvoice.ai/blog/whisper-benchmark-apple-silicon-m3-m4, https://www.getvoibe.com/resources/best-local-whisper-model-superwhisper/).
- **Mac mini M4 16GB default = full `large-v3` (f16 or q8_0)** or a Croatian fine-tune — this is the accuracy tier; memory and RTF (~2.6x) are comfortable (https://getspeakup.app/blog/whisper-cpp-benchmark-mac/).
- **Quantization: q8_0 for Croatian (near-lossless), never q4/q5 as default.** Croatian is lower-resource and more quant-sensitive; keep q8_0 or f16, use q5_0 only as an M1 low-RAM fallback (https://github.com/ggml-org/whisper.cpp, https://fazm.ai/blog/ggml-large-v3-turbo-bin).
- **Core ML is worth enabling but is NOT a large win vs Metal** — it accelerates the encoder only (~1.25x for turbo, the likely default), the conversion is fragile, and ANE can fail and fall back to Metal, so a Metal fallback is mandatory (https://arxiv.org/html/2507.10860v1, https://github.com/ggml-org/whisper.cpp/issues/3702).
- **Pipeline = chunked push-to-talk (record→transcribe once), not the sliding-window `stream` loop.** VAD (Silero, built into whisper.cpp) is the strongly-recommended primary hallucination defense, but it is layered with decoder-side guards, not strictly mandatory (https://github.com/ggml-org/whisper.cpp/issues/1724, https://arxiv.org/html/2505.12969v1).
- **Decode config: force `language=hr`, `translate=false`, temperature 0 + fallback 0.2, default thresholds.** `initial_prompt` is an *unproven* lever for Croatian (documented to degrade non-English WER) and must be A/B tested, not assumed (https://arxiv.org/html/2502.11572v1).
- **Almost every accuracy/latency number here is illustrative — Phase 1 must produce our own Croatian WER + on-device RTF/RAM figures before locking the config.**

## 1. Model choice for Croatian (ranked recommendation + why)

Croatian is a lower-resource, morphologically rich Slavic language for Whisper, so its WER sits well above the ~3-5% of high-resource languages — expect roughly 9-13% from stock models, which is normal, not a defect (https://novascribe.ai/how-accurate-is-whisper, https://elevenlabs.io/speech-to-text/croatian). The one hard Croatian data point: stock `openai/whisper-large-v3-turbo` = **12.73% WER on FLEURS hr**, and the Croatian fine-tune `GoranS/whisper-large-v3-turbo-hr-parla` (Apache-2.0) = **8.66%**, while `whisper-base` collapses to ~66% (https://huggingface.co/GoranS/whisper-large-v3-turbo-hr-parla).

**Ranked for Croatian dictation:**

1. **Croatian fine-tune** (`GoranS/whisper-large-v3-turbo-hr-parla`, Apache-2.0) — accuracy ceiling among free options (8.66% FLEURS hr) and turbo-architecture so it stays fast. **Caveat:** it must be verified to convert cleanly to GGML for the pinned whisper.cpp, and it was trained on Croatian parliamentary/read speech — its behavior on **English and mixed HR/EN dictation is undocumented** and must be tested before it becomes default (https://huggingface.co/GoranS/whisper-large-v3-turbo-hr-parla).
2. **Full `large-v3` (stock)** — best stock model for Croatian and the reference-quality baseline; heaviest/slowest. The accuracy choice on the M4 16GB tier.
3. **Stock `large-v3-turbo`** — best stock speed/accuracy balance (~12.73% HR FLEURS, ~2-4x faster than large-v3). The pragmatic default on the M1 8GB where full large-v3 is too heavy.
4. **`medium`** — emergency low-memory fallback only.

**Verdict-driven nuance (Claim 1, holds=false):** do **not** treat turbo as "essentially equal" to full large-v3 for Croatian. Multiple 2026 sources specifically recommend full large-v3 over turbo for low-resource languages because turbo's 4-layer decoder (vs 32) hurts languages needing more decode computation (https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks, https://www.emergentmind.com/topics/whisper-large-v3-turbo). Treat model choice as an explicit per-tier accuracy-vs-latency decision.

**Excluded:** `distil-whisper` (English-only, no Croatian checkpoints — https://huggingface.co/distil-whisper/distil-large-v3/discussions/2); `small`/`base` (unusable HR WER). A related Serbian fine-tune (`Sagicc/whisper-large-v3-sr-cmb`, closely related štokavian) exists as a secondary candidate but is unverified for HR.

## 2. Quantization & memory (model × quant → size, RAM, notes)

Guidance: for multilingual/low-resource work stay on **f16 or q8_0**; q5_0 is an English-only compromise; avoid q4_0 for Croatian (https://snailtext.app/blog/how-whisper-cpp-works/, https://fazm.ai/blog/ggml-large-v3-turbo-bin, https://github.com/ggml-org/whisper.cpp). Quantization affects only the GGML decoder weights; the Core ML encoder is separate and unquantized.

| Model × quant | On-disk (approx) | RAM (approx, load + buffers) | Accuracy / speed note |
|---|---|---|---|
| large-v3 f16 | ~2.9 GiB | ~3.9 GB (up to ~10 GB w/ beam) | Reference HR accuracy. Impractical on 8GB M1; fine on M4 16GB. RTF ~1.0x M1 / ~2.6x M4 (https://github.com/ggml-org/whisper.cpp, https://getspeakup.app/blog/whisper-cpp-benchmark-mac/) |
| large-v3 q8_0 | ~1.6-1.7 GB | ~2.5-3 GB | Near-lossless vs f16. **M4-tier default candidate**; still tight on 8GB with target app resident |
| large-v3 q5_0 | ~1.1 GB | ~3.8 GB load + ~1.2 GB buffers (vendor, worst-case) | On 8GB M1 leaves <500 MB → swap, multi-minute transcriptions. **Do NOT default on M1** (https://fazm.ai/blog/ggml-large-v3-bin) |
| large-v3-turbo f16 | ~1.5 GB | ~1.7 GB | Full encoder + 4-layer decoder; ~2-4x faster than large-v3, small HR accuracy loss |
| **large-v3-turbo q8_0** | **~800-900 MB** | **~0.9-1.7 GB** | **Air M1 8GB default (accuracy-first).** Near-lossless quant, fits alongside browser/Slack (https://fazm.ai/blog/ggml-large-v3-turbo-bin) |
| large-v3-turbo q5_0 | ~550 MB | ~0.6-1.0 GB | M1 low-RAM fallback if q8_0 shows swap. Minor multilingual degradation |
| large-v3-turbo q4_0 | ~450 MB | ~0.5 GB | Too aggressive for Croatian; last-resort only |
| medium f16 | ~1.5 GiB | ~2.1 GB | Emergency HR fallback; RTF ~2.5x M1 |

**Verdict-driven nuance (Claims 2 & 4, both holds=false):** a quantized **full** large-v3 does not reliably fit on 8GB alongside macOS (~3-4 GB) + a heavy target app (Slack/Chrome ~1.5-4 GB) without swapping, and is only ~1.0x RTF on M1 even without memory pressure. The largest model that coexists comfortably on 8GB is quantized **large-v3-turbo** (~0.9-1.7 GB) (https://www.getvoibe.com/resources/best-local-whisper-model-superwhisper/, https://openwhispr.com/blog/whisper-model-sizes-explained). All RAM figures are approximate vendor numbers — confirm peak RSS + swap via `vm_stat` on the actual 8GB M1 in Phase 1.

## 3. whisper.cpp build & Core ML on Apple Silicon (flags, workflow, pin)

**Build (both acceleration paths stack):**
```
cmake -B build -DWHISPER_COREML=1 -DCMAKE_BUILD_TYPE=Release
cmake --build build -j --config Release
```
- **Metal** is auto-enabled on Apple Silicon (no flag); it runs the decoder on the GPU and the encoder when Core ML is absent (https://github.com/ggml-org/whisper.cpp).
- **`-DWHISPER_COREML=1`** offloads *only the encoder* to the ANE. whisper.cpp auto-loads `models/ggml-<model>-encoder.mlmodelc` when built with Core ML. Requires macOS Sonoma 14+ (older macOS can cause hallucination). First run is slow (ANE compiles a device-specific format) — warm the model at launch and show a one-time "optimizing" state.
- Document each flag in `docs/decisions/` per CLAUDE.md.

**Verdict-driven nuance (Claim 3, holds=false):** the headline ">3x" Core ML figure is **encoder-only and vs CPU-only**, not vs Metal and not end-to-end (https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/README.md). Against the real Metal baseline the net gain is **modest and model-dependent**: documented ~2-3x lifts are for small/base/medium; one benchmark found ANE "about on par" with the Metal GPU (https://news.ycombinator.com/item?id=43880345); WhisperKit measured ANE practical speedup ~2.24x for large-v3 but only **~1.25x for large-v3-turbo** — the project's likely default (https://arxiv.org/html/2507.10860v1). ANE can also fail and silently fall back to Metal (issue #3702, M4 + macOS beta — https://github.com/ggml-org/whisper.cpp/issues/3702). **Treat Core ML as opt-in with a mandatory Metal fallback, and measure the actual net gain per tier before assuming it helps.**

**Core ML conversion workflow (version-fragile — pin everything):**
```
python3.11 -m venv coreml-venv && source coreml-venv/bin/activate
pip install "numpy<2.0" coremltools ane_transformers openai-whisper
xcode-select --install    # if needed
./models/generate-coreml-model.sh <model>
```
The classic failure is NumPy 2.0 incompatibility (`np.issctype` removed); pin **Python 3.11 + numpy<2 + a recent coremltools 8.x**. Multiple open issues track breakage (#2423, #3012, #2042 — the last reported large-v3 conversion problems, so test large-v3/turbo conversion end-to-end). Record exact pinned versions; do **not** commit `.mlmodelc` or `.bin` to git — scripts only, models gitignored (https://github.com/ggml-org/whisper.cpp, https://github.com/ggml-org/whisper.cpp/issues/2423, https://github.com/ggml-org/whisper.cpp/issues/2042).

**Quantize:**
```
./build/bin/quantize models/ggml-<model>.bin models/ggml-<model>-q8_0.bin q8_0
```

**Pin (verify before committing):** the v1.9.x line is current as of mid-2025 (releases page returned v1.9.1 2025-06-19, v1.9.0 2025-06-17), but sources conflicted on version/date — **do not trust a tag from this research blindly.** Confirm with `git ls-remote --tags https://github.com/ggml-org/whisper.cpp` at implementation time and pin an explicit tag that includes the Silero VAD integration. Never track a fork's `main` (https://github.com/ggml-org/whisper.cpp/releases).

## 4. Real-time pipeline & VAD (shape, chunk sizes, latency)

Whisper is fundamentally chunked (30s window); there is no native token streaming, so any "real-time" whisper.cpp is overlapping-chunk reprocessing (https://modal.com/blog/open-source-stt, https://huggingface.co/openai/whisper-large-v3).

**Recommended shape: chunked push-to-talk, NOT the sliding-window `stream` loop.** Hotkey down → AVAudioEngine captures 16kHz mono Float32 into a growing buffer → hotkey up → run **one** `whisper_full` pass with `single_segment=true`. For short-to-medium dictation this maximizes Croatian accuracy (full context, no boundary splits) and latency stays low because utterances are short. This matches the industry-standard shape of OpenWhispr/Voibe/Superwhisper-class apps targeting sub-300ms perceived latency (https://openwhispr.com/blog/how-whisper-ai-works, https://github.com/sam-pop/WhisperDictation).

**VAD (strongly recommended primary layer, not mandatory).** whisper.cpp ships a built-in Silero VAD (2025): `--vad -vm models/ggml-silero-v6.2.0.bin`, downloaded via `./models/download-vad-model.sh silero-v6.2.0` (gitignored). A streaming API (`whisper_vad_detect_speech_no_reset` + `whisper_vad_reset_state`) maintains LSTM state across live mic chunks (https://github.com/ggml-org/whisper.cpp, https://huggingface.co/ggml-org/whisper-vad, https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/include/whisper.h). Use VAD to (a) trim leading/trailing silence before decode and (b) optionally auto-stop after a silence window.

**Verdict-driven nuance (Claim 6, holds=false on "needed"):** VAD is the single most effective mitigation but is **neither strictly required nor sufficient**. Push-to-talk is user-bounded, so the long silent passages that trigger hallucination are largely absent by construction; bounded capture + light silence trim + decoder-side guards can suppress silence hallucination without a dedicated VAD (https://arxiv.org/html/2505.12969v1, https://github.com/SYSTRAN/faster-whisper/issues/843). Conversely Silero v5 is only ~61% utterance-accurate on noise and can occasionally worsen results. **Adopt layered defenses: bounded capture + silence trim + decoder thresholds, with Silero VAD as the primary/default layer.** It is legitimate to ship the first cut without a dedicated VAD and add it as a robustness upgrade — but VAD-trimming is doubly valuable on the 8GB M1 (shorter audio → less peak RAM and decode time).

**Silero VAD starting params** (confirm actual `whisper_vad_default_params()` from the pinned source; reported values are secondary): threshold 0.5, min_speech 250ms, min_silence 100ms, speech_pad 30ms, samples_overlap 0.1s. **Tune for Croatian:** raise `min_silence` to ~500-700ms for natural sentence auto-stop; keep `speech_pad ≥30ms` so word onsets aren't clipped.

**Optional (do NOT ship first cut):** a live-preview sliding window (step ~500-700ms, length ~5000ms, keep ~200ms) feeding a non-committed preview buffer, with a final full-utterance re-decode on key release for authoritative text. Prior art ("fast partial + accurate final") uses tiny/base for partials and the chosen model for the final pass (https://github.com/luisalima/local-whisper). This costs accuracy/battery on the M1 8GB — defer.

## 5. Accuracy tuning knobs (recommended values)

whisper.cpp exposes decode tuning via `whisper_full_params` (mirrored by CLI). Recommended Croatian dictation profile:

| Knob | Recommended value | Why |
|---|---|---|
| `language` / `detect_language` | `"hr"` / `false` | Never auto-detect on short clips — a mis-detect (Serbian/Slovenian/Bosnian/English) corrupts the whole segment. Forced hr still transcribes embedded English words (https://huggingface.co/openai/whisper-large-v3) |
| `translate` | `false` | Must output Croatian as spoken, not English (https://github.com/ggml-org/whisper.cpp/blob/master/examples/cli/README.md) |
| `temperature` / `temperature_inc` | `0.0` / `0.2` | Deterministic base + fallback ladder; never set inc=0 (makes loops unrecoverable) (https://github.com/openai/whisper/blob/main/whisper/transcribe.py) |
| `beam_size` | **M4: 5; M1: greedy / small** | Beam improves accuracy modestly (<~1.5 pts) but costs latency/memory; hardware-split (https://arxiv.org/pdf/2503.06924) |
| `entropy_thold` / `logprob_thold` / `no_speech_thold` | `2.40` / `-1.00` / `0.60` (defaults) | Well-tuned anti-hallucination guards; only adjust after observing real Croatian failures (https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/include/whisper.h) |
| `suppress_blank` | `true` (default) | Prevents leading blank tokens |
| `suppress_nst` / `suppress_regex` | off | Enable only if a specific artifact (`[music]`, subtitle credits) actually appears |
| `token_timestamps` | `false` | DTW overhead with no dictation benefit |
| `no_context` | `true` (reset between sessions) | Stops stale text/hallucinations leaking across independent hotkey bursts (https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/include/whisper.h) |
| `initial_prompt` | **treat as experimental — see below** | — |

**`initial_prompt` — verdict-driven nuance (Claim 5, holds=false).** There is **no `hotwords` field** in mainline ggml-org whisper.cpp (open request #1979); vocabulary biasing is only via `initial_prompt` (soft) or GBNF grammar (avoid for free-form dictation) (https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/include/whisper.h, https://github.com/ggml-org/whisper.cpp/issues/1979). Critically, prompt-based contextual biasing is documented to be **ineffective or actively harmful for non-English**: arXiv 2502.11572 shows prompting *raising* WER for French (+2.8pp) and German (+9pp U-WER) — both higher-resource than Croatian (https://arxiv.org/html/2502.11572v1). The prompt slot was trained to hold the *previous segment's transcript*, not a word list; it is capped at ~224 tokens with attention weighting the end, and can be silently ignored or induce hallucinations. The quantified "5-15%" gains are vendor-blog claims with no methodology. **Position: `initial_prompt` is unproven for Croatian and carries real degradation risk.** A short natural Croatian sentence (correct dijakritika č/ć/š/ž/đ, key terms last, <224 tokens, `carry_initial_prompt` for long dictation) *may* give small style/spelling gains — but it must be **A/B benchmarked on the user's own Croatian audio before being relied upon.** Fine-tuning, not prompting, is the demonstrated path to Croatian accuracy.

## 6. Apple Silicon performance (M1 8GB vs M4 16GB — RTF, viability)

RTF numbers below are self-described illustrative ranges, not controlled measurements against a Croatian corpus (https://getspeakup.app/blog/whisper-cpp-benchmark-mac/, https://justvoice.ai/blog/whisper-benchmark-apple-silicon-m3-m4):

| Model | Air M1 8GB (RTF, approx) | Mac mini M4 16GB (RTF, approx) |
|---|---|---|
| large-v3 f16 | ~1.0x — "transcribe-then-wait", memory-tight → swap risk | ~2.6x — comfortable near-real-time |
| large-v3-turbo | ~2-3x (pushed up by 4-layer decoder) | well above real-time (turbo ≈ 17.7x on M3 Ultra as an upper reference) |
| medium f16 | ~2.5x | ~5x |

**Viability verdict per tier:**

- **Air M1 8GB — VIABLE only with turbo (quantized).** Full large-v3 is borderline on speed (~1.0x, zero headroom) and fails on memory (swap once target app resident) — Claims 2 & 4. **Default: `large-v3-turbo` q8_0 + Core ML encoder + Metal**, drop to q5_0 if `vm_stat` shows swap. Watch thermals on the fanless Air under back-to-back dictations (undocumented — test in Phase 1). Consider unloading the model after N idle minutes.
- **Mac mini M4 16GB — COMFORTABLY VIABLE for the accuracy tier.** ~3.4x ANE headroom + 16GB → run **full `large-v3`** (f16 or q8_0) or a Croatian fine-tune with `beam_size=5` for best Croatian accuracy; turbo if latency is prioritized.

Note: the Core ML first-run compile delay affects the first dictation after install/OS-update — warm at launch. No Croatian-specific WER exists for large-v3 vs turbo vs medium anywhere — the accuracy side of the tradeoff is entirely unverified for HR (https://gigagpu.com/whisper-large-v3-turbo-vs-large-v3-comparison/).

## 7. Swift integration & prior art (architecture only)

- **Embedding:** whisper.cpp ships an official SwiftUI example (`examples/whisper.swiftui`, macOS+iOS) as the canonical reference. Prefer the **prebuilt XCFramework** (`build-xcframework.sh`) consumed as an SPM `binaryTarget` pinned to a specific release tag (per CLAUDE.md "never main of a fork"); fall back to git-submodule + C bridging header only if custom compile flags are needed. Note the ObjC++/C++ same-target constraint if mixing (https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.swiftui/README.md, https://github.com/ggerganov/whisper.spm).
- **Concurrency:** mirror the example's `WhisperContext` **Swift actor** wrapping `whisper_full` off the main thread; reserve `@MainActor` for menu bar/UI state. This satisfies the strict-concurrency + "whisper off main thread" rules for free.
- **Hotkey:** use a **CGEvent tap** monitoring key down/up for press-and-hold push-to-talk (as WhisperDictation does with Right Option / local-whisper with Right-Cmd) — RegisterEventHotKey is oriented to discrete presses. For an optional discrete toggle, wrap RegisterEventHotKey via `sindresorhus/KeyboardShortcuts`, but avoid Option-only / Option+Shift-only combos on macOS 15 (FB15168205) (https://github.com/sam-pop/WhisperDictation, https://github.com/sindresorhus/KeyboardShortcuts, https://developer.apple.com/forums/thread/735223).
- **Text injection:** default to **pasteboard + synthesized Cmd+V** (save/restore the previous clipboard) — most reliable for Croatian diacritics and long dictations. Offer **CGEvent Unicode typing** (`keyboardSetUnicodeString`) as a fallback for apps where paste misbehaves (needs inter-keystroke delays). Both break under **Secure Input** (password fields) — detect Secure Input state and surface a menu bar warning. AXUIElement direct value insertion is inconsistent (Electron/non-native apps) — niche only (https://developer.apple.com/documentation/coregraphics/cgevent/1456028-keyboardsetunicodestring, https://blog.kulman.sk/implementing-auto-type-on-macos/).
- **Distribution/permissions:** any injection/accessibility path forces a **non-sandboxed, Developer-ID-signed** app (not Mac App Store) — fine for personal use. Bake an explicit `AXIsProcessTrustedWithOptions()` permission flow (system prompt shows once per launch) into Phase 3/4, plus mic permission via Info.plist (https://developer.apple.com/forums/thread/61387).

## 8. Recommended DEFAULT config per hardware tier

Auto-select on **detected chip AND available RAM** (opcija A) — 8GB is the binding constraint on M1, so pick the quantized model when RAM is low.

**MacBook Air M1 8GB (latency/memory-constrained):**
- Model: `large-v3-turbo` **q8_0** (fallback q5_0 if swap observed). Candidate upgrade: `GoranS/whisper-large-v3-turbo-hr-parla` q8_0 *if* it converts to GGML and holds up on mixed HR/EN.
- Build: `-DWHISPER_COREML=1` + Metal, Core ML encoder **with mandatory Metal fallback**.
- Decode: `language=hr`, `translate=false`, temp 0 / inc 0.2, **greedy** (beam disabled or ≤5), thresholds at default, `no_context=true`, `token_timestamps=false`, `single_segment=true`.
- Pipeline: chunked push-to-talk + silence trim + Silero VAD (primary layer). VAD-trim to cut peak RAM.
- Injection: pasteboard + Cmd+V.

**Mac mini M4 16GB (accuracy tier):**
- Model: full `large-v3` **q8_0** (or f16), or Croatian fine-tune. Turbo only if latency is prioritized.
- Build: same (`-DWHISPER_COREML=1` + Metal); expect a smaller Core ML net lift on turbo (~1.25x) — measure.
- Decode: same profile but **`beam_size=5`** for best Croatian accuracy.
- Pipeline & injection: same as M1.

Both tiers: warm/preload the model at launch and handle the Core ML first-run compile with a visible "optimizing" state.

## 9. MUST be empirically benchmarked in Phase 1 (what literature cannot settle)

1. **Croatian WER on OUR dictation audio** (short, spontaneous, mixed HR/EN, no punctuation) for: full large-v3, large-v3-turbo, medium, and the GoranS fine-tune — across q4_0/q5_0/q8_0/f16. No primary source pins the full-v3-vs-turbo Croatian delta; every clue says turbo is meaningfully behind, but the magnitude is unknown.
2. **Does `GoranS/whisper-large-v3-turbo-hr-parla` convert cleanly to GGML** for the pinned build, and does it degrade on **English / code-switched HR-EN** dictation (it was trained on read parliamentary speech)?
3. **On-device RTF + peak RSS + swap** (`vm_stat`) on the **actual 8GB M1** with a realistic target app (Slack/Chrome) resident, for turbo q8_0 / q5_0 — confirm no swapping. Vendor RAM numbers are approximate and inconsistent.
4. **Core ML net gain vs Metal-only** on both M1 and M4 with the chosen Croatian model (expected small for turbo ~1.25x) — decide whether the fragile conversion is worth it per tier. Verify large-v3/turbo encoder conversion succeeds on current coremltools (issue #2042 risk).
5. **Beam=5 vs greedy** — Croatian WER gain vs latency cost on M1 8GB and M4 16GB.
6. **`initial_prompt` A/B** on the user's own Croatian audio — does it help style/diacritics or degrade/hallucinate (cross-lingual evidence says it can hurt)? Also test `carry_initial_prompt`.
7. **VAD on/off hallucination reduction** for Croatian silence/noise cases; tune `no_speech_thold` (default 0.60 may drop soft Croatian speech) and Silero `min_silence` for natural auto-stop without cutting mid-sentence pauses. Confirm actual `whisper_vad_default_params()` from the pinned source.
8. **Thermal throttling** on the fanless Air under 10-15 min of back-to-back dictations (RTF degradation).
9. **End-to-end injection latency + reliability** of pasteboard+Cmd+V vs CGEvent typing across the user's real apps (Slack, Mail, Safari, Electron), including Secure Input behavior.

## Sources (deduped URL list)

- https://github.com/ggml-org/whisper.cpp
- https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/README.md
- https://github.com/ggml-org/whisper.cpp/releases
- https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/README.md
- https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/examples/stream/stream.cpp
- https://github.com/ggml-org/whisper.cpp/blob/master/README.md
- https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/include/whisper.h
- https://github.com/ggml-org/whisper.cpp/blob/master/examples/cli/README.md
- https://github.com/ggml-org/whisper.cpp/blob/master/examples/whisper.swiftui/README.md
- https://github.com/ggml-org/whisper.cpp/issues/1724
- https://github.com/ggml-org/whisper.cpp/issues/1979
- https://github.com/ggml-org/whisper.cpp/issues/2042
- https://github.com/ggml-org/whisper.cpp/issues/2423
- https://github.com/ggml-org/whisper.cpp/issues/2881
- https://github.com/ggml-org/whisper.cpp/issues/3003
- https://github.com/ggml-org/whisper.cpp/issues/3012
- https://github.com/ggml-org/whisper.cpp/issues/3702
- https://github.com/ggml-org/whisper.cpp/discussions/348
- https://github.com/ggml-org/whisper.cpp/discussions/1608
- https://github.com/ggml-org/whisper.cpp/discussions/1722
- https://github.com/ggml-org/whisper.cpp/discussions/2003
- https://github.com/ggml-org/whisper.cpp/discussions/2047
- https://github.com/openai/whisper
- https://github.com/openai/whisper/discussions/1762
- https://github.com/openai/whisper/discussions/2363
- https://github.com/openai/whisper/discussions/679
- https://github.com/openai/whisper/blob/main/whisper/transcribe.py
- https://huggingface.co/openai/whisper-large-v3
- https://huggingface.co/openai/whisper-large-v3-turbo
- https://huggingface.co/GoranS/whisper-large-v3-turbo-hr-parla
- https://huggingface.co/Sagicc/whisper-large-v3-sr-cmb
- https://huggingface.co/distil-whisper/distil-large-v3/discussions/2
- https://github.com/huggingface/distil-whisper
- https://huggingface.co/ggml-org/whisper-vad
- https://arxiv.org/abs/2311.01070
- https://arxiv.org/pdf/2503.23542
- https://arxiv.org/pdf/2604.04598
- https://arxiv.org/html/2503.09905v1
- https://arxiv.org/pdf/2303.00747
- https://arxiv.org/pdf/2501.11378
- https://arxiv.org/html/2501.11378v1
- https://arxiv.org/html/2410.18363v1
- https://arxiv.org/pdf/2503.06924
- https://arxiv.org/pdf/2503.06924
- https://arxiv.org/html/2502.11572v1
- https://arxiv.org/pdf/2502.11572
- https://arxiv.org/html/2505.12969v1
- https://arxiv.org/html/2507.10860v1
- https://arxiv.org/pdf/2501.06117
- https://novascribe.ai/how-accurate-is-whisper
- https://elevenlabs.io/speech-to-text/croatian
- https://slsolucije.hr/en/products/speech-recognition-stt
- https://medium.com/@bnjmn_marie/whisper-large-v3-turbo-as-good-as-large-v2-but-6x-faster-97f0803fa933
- https://medium.com/axinc-ai/prompt-engineering-in-whisper-6bb18003562d
- https://fazm.ai/blog/ggml-large-v3-turbo-bin
- https://fazm.ai/blog/ggml-large-v3-bin
- https://fazm.ai/blog/whisper-cpp-metal-apple-silicon
- https://snailtext.app/blog/how-whisper-cpp-works/
- https://justvoice.ai/blog/whisper-benchmark-apple-silicon-m3-m4
- https://getspeakup.app/blog/whisper-cpp-benchmark-mac/
- https://mundwerkapp.de/en/blog/whisper-benchmark-m3-ultra/
- https://gigagpu.com/whisper-large-v3-turbo-vs-large-v3-comparison/
- https://whispernotes.app/blog/introducing-whisper-large-v3-turbo
- https://groq.com/blog/whisper-large-v3-turbo-now-available-on-groq-combining-speed-quality-for-speech-recognition
- https://www.promptquorum.com/local-llms/apple-silicon-whisper-metal-benchmark
- https://www.phoronix.com/news/Whisper-cpp-1.8.3-12x-Perf
- https://www.alibaba.com/product-insights/how-to-choose-between-whisper-cpp-and-faster-whisper-for-offline-transcription-on-macbook-air.html
- https://openwhispr.com/blog/how-whisper-ai-works
- https://openwhispr.com/blog/whisper-model-sizes-explained
- https://openwhispr.com/blog/whisper-local-speech-to-text
- https://www.getvoibe.com/blog/superwhisper-alternatives/
- https://www.getvoibe.com/resources/best-local-whisper-model-superwhisper/
- https://voxtype.io/
- https://modal.com/blog/open-source-stt
- https://weesperneonflow.ai/en/blog/2026-03-31-voxtral-whisper-open-source-speech-models-comparison-2026/
- https://dev.to/nareshipme/whisper-hallucination-on-silence-why-your-transcript-loops-the-same-phrase-2pg4
- https://memo.ac/blog/whisper-hallucinations
- https://blog.gdeltproject.org/experiments-with-whisper-asr-model-parameters-non-determinism-temperature_increment_on_fallback/
- https://www.rubydoc.info/gems/whispercpp
- https://github.com/sam-pop/WhisperDictation
- https://github.com/human37/open-wispr
- https://github.com/luisalima/local-whisper
- https://github.com/starmel/OpenSuperWhisper
- https://github.com/ggerganov/whisper.spm
- https://github.com/anvanvan/mac-whisper-speedtest
- https://github.com/sindresorhus/KeyboardShortcuts
- https://github.com/soffes/HotKey
- https://github.com/feedback-assistant/reports/issues/552
- https://developer.apple.com/forums/thread/735223
- https://developer.apple.com/forums/thread/61387
- https://developer.apple.com/documentation/coregraphics/cgevent/1456028-keyboardsetunicodestring
- https://blog.kulman.sk/implementing-auto-type-on-macos/
- https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-input-monitoring-screen-capture-accessibility.html
- https://news.ycombinator.com/item?id=43880345
- https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks
- https://www.emergentmind.com/topics/whisper-large-v3-turbo
- https://github.com/SYSTRAN/faster-whisper/issues/843
- https://macwhisper.helpscoutdocs.com/article/34-transcription-is-slower-than-expected
- https://www.saytowords.com/blogs/Whisper-Accuracy-Tips/
- https://sotto.to/blog/improve-whisper-accuracy-prompts

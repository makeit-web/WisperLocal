# Phase 1 — Open Questions (awaiting user answers)

**Created:** 2026-04-21
**Status:** 🟡 Awaiting user answers
**Blocks:** `docs/specs/phase-1-whisper-setup.md` (cannot be finalized until these are resolved)
**Author:** Claude (CTO)

---

## How to use this document

Read each question. For each one you can either:
1. **Write your answer in the `Answer:` slot** — free text, full decision, or notes.
2. **Type `✅ Recommended`** if you accept Claude's recommendation as-is.
3. **Type `❓ Discuss`** if you want to talk through it more before deciding.

Once all questions are answered, Claude will incorporate the decisions into the Phase 1 spec.

**Priority labels:**
- 🚨 **BLOCKER** — spec cannot be written without this answer.
- ⚠️ **IMPORTANT** — spec can be drafted with Claude's recommendation, but user should confirm.
- ℹ️ **INFORMATIONAL** — minor decision, Claude proceeds with recommendation unless challenged.

---

## 🎤 Q1 — Microphone hardware 🚨 BLOCKER

### Why this matters
The microphone is the single biggest accuracy variable in the entire project — bigger than the Whisper model choice. A mediocre model with a great mic beats a great model with a mediocre mic. Roughly 30% of real-world accuracy comes from mic quality and placement, not the model.

### The question (three parts)

**1a.** On the MacBook Air M1, will you use:
- The built-in microphone (convenient, but picks up keyboard noise and has aggressive compression)
- An external microphone (USB, Bluetooth headset, AirPods, etc.) — specify which

**1b.** The Mac mini has **no built-in microphone**. What's your plan for it?
- Buying a USB microphone (e.g., Blue Yeti, Samson Q2U, Elgato Wave:3)
- Using AirPods or another Bluetooth headset
- Using an existing external mic you already own — specify which
- Something else

**1c.** Do you want the app to be **mic-aware** (detect which mic is active and adapt the audio pipeline), or pick one default mic per machine and keep it simple?

### Claude's recommendation
For Phase 1 benchmarks to be representative, **use the same mic class you'll use in real life**. If you plan to dictate with AirPods, benchmark with AirPods. If with a USB desk mic, benchmark with that.

Phase 1 pragma: pick your "daily driver" mic for each machine, document it, benchmark on it. If you're undecided between two options, we benchmark both.

For Mac mini: **recommend a USB desk mic with cardioid pickup** (Samson Q2U ~€70, or Blue Yeti ~€130). Cardioid rejects room noise; omnidirectional picks up everything. Avoid USB headsets for desk use — inconsistent audio gain.

### Answer
_Air mic:_
_Mac mini mic:_
_Mic-aware app:_

---

## 📏 Q2 — WER methodology for Croatian ⚠️ IMPORTANT

### Why this matters
WER (Word Error Rate) is the industry-standard metric for transcription accuracy. But Croatian has rich morphology — 7 noun cases, complex verb conjugation — that makes WER over-penalize the model for meaningful-but-imperfect output. Example: transcript "idem kući" vs truth "idem u kuću" = 2 word errors, but the meaning is essentially preserved.

We need to pick a metric (or combination) that actually tells us if the app will feel good to use.

### Options

- **A) Strict WER** — standard, comparable to external benchmarks, but penalizes HR morphology heavily. "15% WER" in HR feels like 8% in English.
- **B) CER (Character Error Rate)** — counts character-level differences. More stable for inflected languages; less affected by case endings being off by one character.
- **C) Normalized WER with lemmatization** — lemmatize both transcript and truth before comparing. Closest to "semantic accuracy." Needs a HR lemmatizer (Classla, Stanza). Extra setup.
- **D) Subjective correction effort score** — user reads transcript, rates "how many edits to make this usable." Not reproducible, but closest to real user experience.

### Claude's recommendation
**B + D combination.**
- **CER** for objective per-model ranking (reproducible, fast to compute, stable for HR).
- **Subjective score** on your real-voice samples — you rate 1-5 per sample based on correction effort. Not for public comparison, but for the "ship it?" gate.

Skip A (misleading for HR) and C (lemmatizer overhead not worth it for Phase 1; add in Phase 2 if we need finer measurements).

### Answer
_

---

## 🎯 Q3 — Exit criteria ("what is good enough") 🚨 BLOCKER

### Why this matters
You said "accuracy should be as high as possible." That's not a threshold — it's a direction. Without a concrete "good enough" number, Phase 1 has no exit condition. We could over-invest trying to squeeze out the last 2% improvement, or ship too early.

### Options

- **A) Pragmatic thresholds.** Example: "CER ≤ 10% on Common Voice HR, AND subjective score ≥ 4/5 on user samples." If best model clears these → ship. If not → tune before ship.
- **B) Relative benchmark.** "Best model must be materially better than macOS built-in dictation." Requires Apple dictation as a baseline we also measure. Good if we want to justify building at all.
- **C) Hard stop safety net.** "If no model meets the user's subjective bar, we pause the project and reconsider — don't force shipping something that doesn't work."
- **D) A + B + C combined.** Pragmatic threshold primary; Apple baseline as sanity check; hard stop as the escape hatch.

### Claude's recommendation
**D (A + B + C).**
- **Primary threshold:** CER ≤ 10% on Common Voice HR, subjective ≥ 4/5 on your samples.
- **Sanity check:** must beat macOS built-in dictation on at least one metric. (If Apple ships free better dictation, project is moot.)
- **Hard stop:** if best model fails primary threshold, we stop, write a decision record, and reconsider (better mic? better prompt? different model family? abandon?).

Stretch goal: **CER ≤ 6%** — if we hit this, we're competitive with commercial products.

### Answer
_Primary threshold acceptable?_
_Sanity check worth doing?_
_Hard stop rule agreed?_
_Different numbers you'd set?_

---

## 🧠 Q4 — Initial prompt / domain vocabulary ⚠️ IMPORTANT

### Why this matters
Whisper accepts an `initial_prompt` parameter that biases decoding toward specific vocabulary. For Croatian — and especially for **your** Croatian (tech terms, company names, colleagues, cities you mention) — this can be the difference between "usable" and "unusable."

Example prompt:
```
Ovo je diktat na hrvatskom jeziku u poslovnom kontekstu. Koriste se izrazi
poput: ponuda, račun, klijent, sastanak, deadline, review, sprint, backlog,
Agilno, MakeIT, Studio, web@makeit.hr.
```

The model then "expects" these tokens and transcribes them correctly instead of phonetically guessing.

### The question (two parts)

**4a.** Should the benchmark test **each model both ways** (no prompt + with prompt)? This doubles benchmark time but produces invaluable data on how much prompt helps. Expected: prompt matters 5–15% of CER on domain terms.

**4b.** If you agree with 4a, **send me your domain vocabulary list** — terms you'd expect to dictate often. Examples:
- Company names (Agilno, MakeIT, WisperLocal, clients...)
- People you work with (first names, last names)
- Technical terms in English that you mix into HR speech (sprint, deadline, PR, backlog...)
- Tools/platforms (Slack, Jira, Figma, Notion...)
- Places (cities, streets you mention)
- Your own name + email + phone if you ever dictate them

More is better up to ~200 tokens (that's the prompt budget).

**4c.** Do you want the finished app (Phase 5) to have a **user-editable domain prompt** in settings? (Claude recommendation: yes.)

### Claude's recommendation
**Yes to 4a** (benchmark with + without prompt). **Send vocabulary list when you answer this doc.** **Yes to 4c** (Phase 5 adds configurable prompt field).

### Answer
_4a (benchmark both ways):_
_4b (vocabulary list — paste below or in a separate message):_
_4c (user-editable prompt in Phase 5):_

---

## 🔐 Q5 — Code signing strategy ℹ️ INFORMATIONAL (Phase 3+)

### Why this matters
Not relevant for Phase 1 (CLI tool, no signing needed). But it **will** matter from Phase 3 onward (the actual macOS app). Deciding now saves rework later.

### Options

- **A) Ad-hoc signing** (`codesign --sign -`) — works forever on your own Mac(s), but every rebuild needs "right-click → Open" the first time. No cost.
- **B) Self-signed with a local certificate** — same as A, with an extra trust prompt on first launch. No cost.
- **C) Free Apple ID signing via Xcode** — works on your devices while logged in, but **certificate expires every 7 days**. App stops running if not rebuilt.
- **D) Paid Apple Developer account ($99/year)** — proper signing, notarization, works everywhere, no friction.

### Claude's recommendation
**A (ad-hoc) for Phases 1–4.** Zero cost, works for your two machines. The "right-click → Open" friction only happens once per rebuild, rare after dev stabilizes.

If by Phase 5 we decide to share the app with a colleague or have issues with macOS Gatekeeper updates, **reconsider D** ($99/yr). No commitment needed until then.

### Answer
_

---

## 🔊 Q6 — Voice Activity Detection (VAD) for Phase 1 ℹ️ INFORMATIONAL

### Why this matters
Without VAD, Whisper "hallucinates" in silence — famously outputs phrases like "Hvala na gledanju!" or "Thanks for watching!" (YouTube training data leaking). In production (Phase 2+), we definitely want VAD. The question is whether to include it in Phase 1 benchmarks.

### Options

- **A) No VAD in Phase 1** — benchmark on clean clipped audio (no silence pre/post). Measures pure model capability. Simpler, isolates the variable.
- **B) With VAD in Phase 1** — benchmark on raw audio with silence. More realistic, but conflates "model quality" with "VAD quality."

### Claude's recommendation
**A (no VAD in Phase 1).** Keep the Phase 1 benchmark about model quality only. VAD choice (Silero vs WebRTC vs whisper.cpp built-in) moves into Phase 2 spec where it belongs.

### Answer
_

---

## 💾 Q7 — Mac mini specifics 🚨 BLOCKER

### Why this matters
"Mac mini 16GB" covers machines from 2020 (M1) through 2024 (M4 / M4 Pro). The gap in ML performance is enormous:
- M1: 16-core Neural Engine, 11 TOPS
- M2: 16-core Neural Engine, 15.8 TOPS
- M4: 16-core Neural Engine, 38 TOPS (3.4× M1)
- M4 Pro: even more ANE + GPU cores

This materially changes expected latency, which affects whether large-v3 q8_0 is viable for real-time use or only for post-hoc transcription.

### The question (three parts)

**7a.** Which Mac mini model? (M1 / M2 / M4 / M4 Pro)
**7b.** Already ordered, or still choosing? If still choosing, Claude can factor in benchmark projections.
**7c.** 16GB is confirmed, or is upgrade to 24GB / 32GB an option? (More RAM = more comfort with large-v3 q8_0 + other apps.)

### Claude's recommendation
If not yet ordered: **M4 base with 16GB is the sweet spot for this project** — enormous ANE jump vs M1, plenty of RAM for large-v3 q8_0, price-performance is excellent. 24GB upgrade is worth €200 only if you plan heavy multi-app work beyond dictation.

If already ordered: we work with what you have. Tell me which model and I factor it into the spec.

### Answer
_7a Model:_
_7b Status:_
_7c RAM final:_

---

## Decisions Claude is making without asking (challenge if you disagree)

These are technical defaults Claude will apply in the Phase 1 spec unless you object:

| # | Decision | Reasoning |
|---|----------|-----------|
| D1 | **Audio format:** 16 kHz mono PCM float32 | Standard Whisper input; AVAudioEngine handles resampling natively on M-series with best quality |
| D2 | **Core ML conversion:** whisper.cpp pinned commit + Python 3.11 + coremltools 8.x | Documented in decision record; toolchain is fragile, must pin everything |
| D3 | **Reproducibility:** `temperature=0.0`, no sampling, fixed seed | Eliminates run-to-run variance from the benchmark |
| D4 | **Benchmark record:** every run logs git SHA of whisper.cpp + SHA256 of model + hardware ID | So results are auditable and re-runnable |
| D5 | **Phase 1 deliverable:** command-line tool `transcribe <audio.wav>` + benchmark harness script. **No Swift app in Phase 1.** | Focus Phase 1 on the transcription pipeline; UI is Phase 3's concern |
| D6 | **Dataset:** Common Voice HR as primary, FLEURS-HR as backup, user samples for subjective validation | Common Voice is standard, open, annotated; FLEURS is Google's multilingual set; user samples cover real-world gap |
| D7 | **Privacy:** user audio samples stay in gitignored `test-audio/` on-disk only; never leave machine | Matches the project's core offline-only principle |
| D8 | **Results storage:** raw benchmark output in `docs/research/phase-1-benchmark-YYYY-MM-DD.md` with CSV of per-sample scores | Reproducibility + history |
| D9 | **Approval mechanism:** for every decision needing your sign-off, Claude writes a decision record draft, you review in chat, and say "Approved — proceed." Claude then marks the decision `Accepted` and logs it | Clear governance trail |
| D10 | **Language of this repo's docs:** English per `CLAUDE.md` | Already established rule |

Say "challenge D<N>" if any of these is wrong for you.

---

## Next steps once this doc is answered

1. Claude writes `docs/specs/phase-1-whisper-setup.md` incorporating your answers.
2. You review the spec in chat → approve or request changes.
3. Claude writes `docs/specs/phase-1-plan.md` (concrete implementation steps).
4. You approve the plan.
5. Claude starts building: whisper.cpp build, model download scripts, benchmark harness, Common Voice download.
6. This week's Phase 1a runs on the Air (3 models: large-v3 q5_0, q4_0, medium q5_0).
7. Mac mini arrives → Phase 1b runs (adds q8_0, cross-machine comparison).
8. Final decision record written → model and config locked.
9. Phase 2 spec opens.

---

## Notes

Add any other thoughts or questions that occur to you while answering:

_

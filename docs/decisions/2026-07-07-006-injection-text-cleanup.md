# 006. Strip trailing periods at injection time

**Date:** 2026-07-07
**Status:** Accepted (applies from Phase 5 polish)
**Deciders:** Claude (CTO, recommends) + User (CEO, approves)

## Context
Whisper is trained on written text, so it appends a sentence-ending period (and
sometimes an ellipsis) to the transcript. WisperLocal injects that transcript
verbatim into the focused field. For prose the period is fine, but for **dictated
URLs and file paths it breaks the input** — e.g. `makeit-web.com.` is not an
openable URL. Real user report (2026-07-07): dictating a URL into the browser
yields a trailing `.` that has to be deleted by hand.

Current behaviour: `WhisperContext.runFull` trims only surrounding whitespace
(`.whitespacesAndNewlines`); punctuation passes through unchanged.

## Options considered
1. **Always strip the trailing period** (chosen). Remove any run of trailing
   periods / `…` and surrounding whitespace before injection. Keep `?`, `!`, and
   all internal punctuation. Simplest, least surprising; the user types their own
   final period on the rare occasion they want one.
2. **Context-aware** — strip only when the text "looks like" a URL / single word,
   keep the period for full sentences. Nicer for prose but the detection is
   fragile (URL/heuristic misclassification) — rejected as brittle.
3. **Keep current + menu toggle** to enable/disable stripping. Most code, manual
   per-use choice — deferred; can be layered on option 1 later if prose suffers.

## Decision
- Adopt **option 1**. A pure, unit-tested function `TextCleanup.forInjection(_:)`
  in `WisperCore` removes trailing whitespace + any run of trailing `.`/`…`, then
  trims leading whitespace. It keeps `?`, `!`, commas, colons, and every internal
  mark.
- **Placement:** the app calls it in `AppDelegate.deliver(_:)` immediately before
  `TextInjector.inject`. `WhisperContext` keeps returning the **faithful**
  transcript (so the CLI / any future scoring path are unaffected) — cleanup is an
  injection-time concern, not a transcription concern. (Rejected the alternative
  of stripping inside `WhisperContext`, which would change the raw-transcript
  contract.)

## Consequences
- Prose sentences also lose their final period (accepted by the CEO). If this
  proves annoying, option 3's menu toggle is a cheap additive follow-up.
- Edge: a trailing-period abbreviation loses its last dot (`U.S.A.` → `U.S.A`).
  Rare in dictation-injection; accepted.
- Covered by `TextCleanupTests` (URL, path, prose, `?`/`!`, internal `3.14`,
  abbreviation, ellipsis, diacritics, whitespace, empty, only-period).

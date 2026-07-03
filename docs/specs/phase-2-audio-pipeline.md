# Phase 2 — Swift Audio Capture + Transcription Pipeline (Spec)

> **Status:** DRAFT (v0.1) — proceeding under the CEO's standing "build the app to working, without me" mandate (2026-07-03). Grounded in master plan §5 Phase 2 + the Swift Quality Profile.
> **Author:** Claude (CTO).

## Goal
A native-Swift pipeline that captures the microphone, transcribes it with whisper.cpp, and prints the text — proving the Swift↔whisper.cpp integration and the audio path end to end. **English must work; Croatian as good as the current models allow** (HR fine-tune comes later, with the user). Delivered as a CLI (`wisper-cli`) before the menu-bar app (Phase 3).

## Architecture (SPM package in `src/`)
- **`CWhisper`** — a C target exposing `whisper.h`; links the **static** whisper.cpp + ggml libraries (Metal), pinned to v1.9.1 (`f049fff`). Metal shaders are embedded (no runtime `.metallib`).
- **`WisperCore`** (Swift library):
  - **`WhisperContext`** — an `actor` wrapping the `OpaquePointer` context. The pointer is a *permanent, documented* non-Sendable→Sendable boundary (profile §6). `transcribe(samples:)` dispatches the **blocking** `whisper_full` to a **dedicated thread** and bridges via `CheckedContinuation` resumed exactly once (profile §13) — never on the cooperative pool.
  - **`AudioCapture`** — `AVAudioEngine` input tap → **`AVAudioConverter` 48 k→16 k mono** (profile §15) → a lock-free ring buffer; the tap does no allocation/await; a consumer actor drains it. Push-to-talk (start/stop) for Phase 2.
  - **`ModelStore`** — resolves the model file by chip + available RAM (turbo q8_0 ≤8 GB / large-v3 q8_0 otherwise), from `models/`.
  - **`Transcriber`** — orchestrates capture → 16 kHz `[Float]` → `WhisperContext` → text, with the ADR-003 decode config (`language`, no blind `single_segment`, temp fallback).
- **`wisper-cli`** (executable): `wisper-cli file <wav>` and `wisper-cli record [--lang hr|en|auto]`.

## Language
Configurable; default `hr`, but `en` and `auto` supported (same multilingual model). "English works" = a first-class tested path.

## Tests (Swift Testing)
- `WhisperContext` transcribes a fixture WAV to expected text (EN `jfk.wav`; a short HR clip).
- `AVAudioConverter` resampling 48 k→16 k produces correct sample count/rate.
- Ring buffer: bounded, no data race under concurrent produce/consume.
- `ModelStore` selection logic by RAM.
- Continuation resumed exactly once on success/throw/cancel.

## Exit criteria
- `wisper-cli file jfk.wav` → correct English text (proves the bridge).
- `wisper-cli record` → speak → correct text (HR and EN), off the main actor, no crashes, failures surfaced.
- Latency measured (XCTest `measure`) against the §1 targets.
- Green tests + risk-scaled review (Phase 1–2: Quality Reviewer + one Codex pass).

## Out of scope (later)
Menu bar / hotkey / permissions UI (Phase 3); text injection (Phase 4); streaming partials (Phase 5).

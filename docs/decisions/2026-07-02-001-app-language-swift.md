# 001. App language = Swift (SwiftUI + AppKit)

**Date:** 2026-07-02
**Status:** Accepted
**Deciders:** Claude (CTO, recommends) + User (CEO, approved — "tvoja odluka, ako treba idi")

## Context
WisperLocal is an always-on, offline macOS menu-bar dictation app requiring: global hotkey, Accessibility-API text injection, `NSStatusItem`, microphone capture, tight whisper.cpp (C/C++) integration, low latency, and a small memory footprint (must coexist with real apps on an 8 GB M1). The CEO explicitly asked whether Swift is required or another approach could work.

## Options considered
- **Swift + SwiftUI/AppKit (native)** — first-class access to AX/CGEvent, Carbon hotkeys, `NSStatusItem`, TCC entitlements, Core ML; excellent C interop for whisper.cpp; smallest footprint; cleanest signing/notarization. Con: none material for this use-case.
- **Tauri (Rust core + web UI)** — lighter than Electron; `whisper-rs` exists. Con: macOS AX text-injection, global hotkey, and menu-bar still need Rust→ObjC bindings (objc2/cacao) that are less mature/ergonomic; more moving parts for a solo build; no benefit here.
- **Python (rumps + pyobjc + whisper.cpp bindings)** — fast to prototype. Con: poor packaging/signing, higher memory footprint; not "invisible/polished." *(The real cons are packaging/footprint/signing — whisper.cpp releases the GIL during compute, so GIL contention is not the issue.)*
- **Electron/JS** — disqualified: ~200 MB idle footprint alongside a 1–3 GB model on 8 GB; weak system-API access.

## Decision
**Swift 5.9+ / SwiftUI + AppKit for the app; whisper.cpp (C/C++) linked as the engine.** Native wins precisely on the constraints that matter (footprint, AX injection, hotkey, latency, signing). Phase 1 (benchmark CLI) does not require Swift and may be a thin C/shell/Python harness.

## Consequences
- All app code follows the Swift Quality Profile (`docs/specs/swift-quality-profile.md`).
- whisper.cpp integrated via C interop (module map / bridging); memory management and threading across the C boundary become explicit rules.
- Distribution via Xcode; ad-hoc signing only for the Phase 1–2 CLI, **stable self-signed from Phase 3** (ADR 005).

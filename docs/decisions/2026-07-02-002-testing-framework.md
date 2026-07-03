# 002. Testing framework = Swift Testing (default) + XCTest (perf only)

**Date:** 2026-07-02
**Status:** Accepted
**Deciders:** Claude (CTO, decides — CEO delegated the testing-tool choice: "ti odlucujes testing tool ne ja")

## Context
`CLAUDE.md` originally specified XCTest. WisperLocal is a greenfield 2026 codebase that is concurrency-heavy (actors, task groups, cancellation) and needs data-driven tests over many HR/EN audio fixtures. The CEO delegated the framework choice to the CTO.

## Options considered
- **Swift Testing (`import Testing`)** — async-native tests, `confirmation()`, `.timeLimit`, parameterized tests, tags, `#require` (clean optional unwrap → reinforces no-force-unwrap). The forward path for new projects. Con: evolves fast, Apple docs lag; no `measure`/`XCTMetric` equivalent yet; no UI testing.
- **XCTest** — mature; has `measure {}` for performance and XCUITest for UI. Con: legacy-maintenance; clunky async (`wait(for:)`), verbose.

## Decision
**Swift Testing is the default for all unit + integration tests.** **XCTest is kept only for (a) latency/performance regression (`measure {}`)** — hotkey→transcription→injection latency is a success criterion — **and (b) any XCUITest** (near-zero for a menu-bar app; `CLAUDE.md` already mandates a manual UI checklist).

## Consequences
- Updates `CLAUDE.md` tech-stack row (XCTest → Swift Testing + XCTest-for-perf) on plan approval.
- Pin the Swift toolchain (as we pin whisper.cpp); treat the installed toolchain as authoritative over lagging docs.
- Test rules live in the Swift Quality Profile §(iv).

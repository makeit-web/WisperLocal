import AppKit
import Testing

@testable import WisperCore

/// Behaviour spec for the double-tap-Control state machine — the app's primary
/// dictation trigger (CLAUDE.md mandates unit tests for the hotkey handler).
/// The NSEvent adapter stays thin; all timing/chord logic lives here.
/// (`register` is mutating, so results land in lets — `#expect` can't call it.)
struct DoubleTapDetectorTests {
    @Test func twoQuickTapsFireExactlyOnce() {
        var detector = DoubleTapDetector(interval: 0.4)
        let first = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.0)
        let release = detector.register(ctrlDown: false, ctrlAlone: false, at: 0.1)
        let second = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.3)
        #expect(!first)
        #expect(!release)
        #expect(second)
    }

    @Test func firingConsumesTheWindow() {
        // A third quick tap right after a double-tap must start a fresh pair,
        // not chain into a second fire.
        var detector = DoubleTapDetector(interval: 0.4)
        _ = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.0)
        _ = detector.register(ctrlDown: false, ctrlAlone: false, at: 0.1)
        let fired = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.2)
        _ = detector.register(ctrlDown: false, ctrlAlone: false, at: 0.3)
        let third = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.4)
        #expect(fired)
        #expect(!third)
    }

    @Test func slowTapsDoNotFire() {
        var detector = DoubleTapDetector(interval: 0.4)
        _ = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.0)
        _ = detector.register(ctrlDown: false, ctrlAlone: false, at: 0.1)
        let second = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.6)
        #expect(!second)
    }

    @Test func aChordPressDoesNotArmTheWindow() {
        // Ctrl pressed together with another modifier is a shortcut, not a tap.
        var detector = DoubleTapDetector(interval: 0.4)
        let chord = detector.register(ctrlDown: true, ctrlAlone: false, at: 0.0)
        _ = detector.register(ctrlDown: false, ctrlAlone: false, at: 0.1)
        let tap = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.2)
        #expect(!chord)
        #expect(!tap)
    }

    @Test func chordJoiningWhileHeldInvalidatesPendingTap() {
        // The ⌃⌥D case: Ctrl lands alone (arms the window), Option joins while
        // Ctrl is still held, the Carbon hotkey fires. A quick Ctrl tap right
        // after release must NOT count as the second tap of a double-tap —
        // otherwise ⌃⌥D + a reflexive tap toggles dictation twice.
        var detector = DoubleTapDetector(interval: 0.4)
        let armed = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.0)
        let joined = detector.register(ctrlDown: true, ctrlAlone: false, at: 0.05)  // Option joins
        _ = detector.register(ctrlDown: false, ctrlAlone: false, at: 0.1)
        let tap = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.2)
        #expect(!armed)
        #expect(!joined)
        #expect(!tap)
    }

    @Test func heldCtrlDoesNotSelfFire() {
        // Repeated flagsChanged observations while Ctrl stays down are not taps.
        var detector = DoubleTapDetector(interval: 0.4)
        let down = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.0)
        let heldA = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.1)
        let heldB = detector.register(ctrlDown: true, ctrlAlone: true, at: 0.2)
        #expect(!down)
        #expect(!heldA)
        #expect(!heldB)
    }

    // MARK: - NSEvent flags mapping (the Caps Lock fix)

    @Test func capsLockLatchedIsStillCtrlAlone() {
        // deviceIndependentFlagsMask includes .capsLock, so an exact-match
        // guard (flags == .control) kills the trigger whenever Caps Lock is
        // latched. Only chording modifiers may count.
        let inputs = DoubleTapDetector.chordInputs([.control, .capsLock])
        #expect(inputs.ctrlDown)
        #expect(inputs.ctrlAlone)
    }

    @Test func functionAndNumericPadFlagsAreIgnored() {
        let inputs = DoubleTapDetector.chordInputs([.control, .function, .numericPad])
        #expect(inputs.ctrlDown)
        #expect(inputs.ctrlAlone)
    }

    @Test func realChordingModifiersAreNotCtrlAlone() {
        #expect(!DoubleTapDetector.chordInputs([.control, .shift]).ctrlAlone)
        #expect(!DoubleTapDetector.chordInputs([.control, .option]).ctrlAlone)
        #expect(!DoubleTapDetector.chordInputs([.control, .command]).ctrlAlone)
        #expect(DoubleTapDetector.chordInputs([.control, .shift]).ctrlDown)
    }

    @Test func noControlMeansNotDown() {
        let inputs = DoubleTapDetector.chordInputs([.option])
        #expect(!inputs.ctrlDown)
        #expect(!inputs.ctrlAlone)
    }

    @Test func doubleTapWithCapsLockLatchedFires() {
        // End-to-end through mapping + state machine: the exact regression
        // from the QA report (trigger silently dead while Caps Lock is on).
        var detector = DoubleTapDetector(interval: 0.4)
        let down = DoubleTapDetector.chordInputs([.control, .capsLock])
        let up = DoubleTapDetector.chordInputs([.capsLock])
        let first = detector.register(ctrlDown: down.ctrlDown, ctrlAlone: down.ctrlAlone, at: 0.0)
        let release = detector.register(ctrlDown: up.ctrlDown, ctrlAlone: up.ctrlAlone, at: 0.1)
        let second = detector.register(ctrlDown: down.ctrlDown, ctrlAlone: down.ctrlAlone, at: 0.3)
        #expect(!first)
        #expect(!release)
        #expect(second)
    }
}

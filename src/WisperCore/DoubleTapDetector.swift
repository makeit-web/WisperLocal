import AppKit

/// Pure state machine for the double-tap-Control dictation trigger. The
/// NSEvent adapter (`DoubleTapCtrl` in the app target) feeds it observations;
/// all timing and chord logic lives here so it is unit-testable (ADR 008).
public struct DoubleTapDetector {
    private let interval: TimeInterval
    private var pendingTap: TimeInterval?
    private var ctrlHeld = false

    public init(interval: TimeInterval = 0.4) {
        self.interval = interval
    }

    /// Feed one flags-changed observation. `ctrlDown`: Control is physically
    /// down. `ctrlAlone`: Control is the only *chording* modifier (per
    /// `chordInputs`). Returns `true` exactly when a double-tap fires.
    public mutating func register(ctrlDown: Bool, ctrlAlone: Bool, at time: TimeInterval) -> Bool {
        guard ctrlDown else {
            ctrlHeld = false
            return false
        }
        if ctrlHeld {
            // Still held: another modifier joining (e.g. ⌥ for the ⌃⌥D hotkey)
            // turns this press into a chord — it can no longer be a tap.
            if !ctrlAlone { pendingTap = nil }
            return false
        }
        ctrlHeld = true
        guard ctrlAlone else {
            pendingTap = nil
            return false
        }
        if let pending = pendingTap, time - pending <= interval {
            pendingTap = nil  // consume the window: no chaining into a third fire
            return true
        }
        pendingTap = time
        return false
    }

    /// Reduce raw modifier flags to the detector's inputs, counting only the
    /// chording modifiers. Latched non-chording flags — Caps Lock, fn, numeric
    /// pad — must not affect the trigger: an exact match against `.control`
    /// silently kills double-tap for as long as Caps Lock is on (QA 2026-07-08).
    public static func chordInputs(
        _ flags: NSEvent.ModifierFlags
    ) -> (ctrlDown: Bool, ctrlAlone: Bool) {
        let chord = flags.intersection([.control, .option, .command, .shift])
        return (chord.contains(.control), chord == .control)
    }
}

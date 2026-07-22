import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

public enum InjectionResult: Equatable, Sendable {
    case injected
    case notTrusted
    /// The focused field is a password field.
    case secureField
    /// Something holds the session-wide secure input lock, so no app can
    /// receive synthesized keys. Distinct from `secureField`: nothing about the
    /// *user's* current field is secret — the block is system-wide.
    ///
    /// `likelyApp` is a lead, never a certainty: the OS reports whichever app
    /// was frontmost when the lock was engaged, not the process that requested
    /// it (see `SecureInput`, ADR 009). Named so no call site can present it as
    /// fact by accident.
    case secureInputLocked(likelyApp: RunningApp?)
}

/// OS-level probes and the event sink for `TextInjector.inject`, injectable so
/// the decision chain and chunking are unit-testable with fakes (ADR 008; same
/// pattern as `ModelStore.resolveModelPath`). `live()` wires the real C calls.
struct InjectionProbes {
    var isTrusted: () -> Bool
    var secureInputActive: () -> Bool
    var focusedFieldIsSecure: () -> Bool
    /// Best guess at who holds the secure input lock. Consulted only when
    /// already refusing — it is two IPC round trips.
    var secureInputHolder: () -> RunningApp?
    var postChunk: ([UInt16]) -> Void
    var pace: () -> Void

    /// Real probes. One `CGEventSource` per injection (created here, captured by
    /// `postChunk`) — creating it per chunk is unnecessary; it cannot fail mid-loop.
    static func live() -> InjectionProbes {
        let source = CGEventSource(stateID: .combinedSessionState)
        return InjectionProbes(
            isTrusted: { AXIsProcessTrusted() },
            secureInputActive: { IsSecureEventInputEnabled() },
            focusedFieldIsSecure: { TextInjector.axFocusedFieldIsSecure() },
            secureInputHolder: { SecureInput.likelyHolder() },
            postChunk: { TextInjector.postUnicode($0, source: source) },
            pace: { usleep(1200) }  // ~1.2 ms lets the target app's input queue drain
        )
    }
}

/// Types text into the frontmost app via synthesized Unicode keyboard events.
/// Unicode posting handles Croatian diacritics (č/ć/š/ž/đ) directly. Requires
/// Accessibility permission; refuses both when the focused field is a password
/// field and when secure input is locked session-wide (ADR 009), never touching
/// the pasteboard.
public enum TextInjector {
    /// Max UTF-16 units per synthesized keyboard event. A single event carrying a
    /// very long string truncates/garbles in some apps (the real cause of "types
    /// worse than paste"); small chunks post reliably. Empirical, not documented API.
    private static let chunkSize = 16

    /// Injection paces with `usleep` between chunks — a blocking call that must
    /// not run on the Swift cooperative pool (Swift Quality Profile §13), so it
    /// runs on this dedicated serial queue, mirroring `WhisperContext`.
    private static let queue = DispatchQueue(label: "local.wisper.injection")

    /// Current Accessibility trust — drives the menu hint for the double-tap
    /// trigger (a global flags monitor silently never fires without it).
    public static func isTrusted() -> Bool { AXIsProcessTrusted() }

    /// Prompt the user to grant Accessibility permission (System Settings).
    @discardableResult
    public static func requestTrustPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Inject `text` into the focused app. Runs off the cooperative pool; safe
    /// to call from any actor.
    public static func inject(_ text: String) async -> InjectionResult {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: inject(text, probes: .live()))
            }
        }
    }

    /// Testable core: the full decision chain + chunked posting.
    ///
    /// Secure-input is re-checked before every chunk (not only once up front):
    /// posting follows the *current* focus, so a password dialog stealing focus
    /// mid-injection must stop the remaining chunks — fail closed at the sink.
    /// The AX subrole probe is deliberately checked only up front: it is two
    /// synchronous IPC round-trips that can stall if the frontmost app hangs,
    /// and async auth dialogs (sudo, keychain, browsers) all flip the cheap
    /// global secure-input flag that IS re-checked per chunk (ADR 008).
    static func inject(_ text: String, probes: InjectionProbes) -> InjectionResult {
        guard !text.isEmpty else { return .injected }
        guard probes.isTrusted() else { return .notTrusted }
        if probes.secureInputActive() { return .secureInputLocked(likelyApp: probes.secureInputHolder()) }
        if probes.focusedFieldIsSecure() { return .secureField }

        let units = Array(text.utf16)
        for range in chunkRanges(of: units, max: chunkSize) {
            if probes.secureInputActive() {
                return .secureInputLocked(likelyApp: probes.secureInputHolder())
            }
            probes.postChunk(Array(units[range]))
            probes.pace()
        }
        return .injected
    }

    /// Split `units` into ranges of at most `max`, never ending a range on a
    /// high surrogate (would corrupt an emoji / rare glyph at the chunk
    /// boundary). High surrogates are 0xD800...0xDBFF. Pure — unit-tested.
    static func chunkRanges(of units: [UInt16], max: Int) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        while start < units.count {
            var end = min(start + max, units.count)
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]), end - 1 > start {
                end -= 1
            }
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    /// Post one chunk as a matched key-down (carrying the Unicode payload) + key-up.
    /// The payload goes on key-down only; key-up is the matching release (setting it
    /// on both can double-insert in some apps). Modifier flags are cleared so a
    /// logically-held Control (from the double-tap trigger) isn't read as a shortcut.
    fileprivate static func postUnicode(_ units: [UInt16], source: CGEventSource?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        down.flags = []
        up.flags = []
        units.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// True when the focused UI element reports a secure text-field subrole.
    /// Complements `IsSecureEventInputEnabled` for native secure fields that don't
    /// toggle global secure input. An unknown/unavailable subrole — including any
    /// failed AX query — is deliberately NOT treated as secure: failing closed
    /// there would break typing into ordinary web / Electron fields, the app's
    /// core purpose. `IsSecureEventInputEnabled` is the authoritative primary
    /// guard; this probe only adds coverage (residual risk documented in ADR 007).
    fileprivate static func axFocusedFieldIsSecure() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focusedRef = focused,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return false }
        // Safe by the CFGetTypeID check above: focusedRef IS an AXUIElement.
        let element = focusedRef as! AXUIElement  // swiftlint:disable:this force_cast
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSubroleAttribute as CFString, &subrole
        ) == .success, let value = subrole as? String else { return false }
        return value == (kAXSecureTextFieldSubrole as String)
    }
}

import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum InjectionResult {
    case injected
    case notTrusted
    case secureField
}

/// Types text into the frontmost app via synthesized Unicode keyboard events.
/// Unicode posting handles Croatian diacritics (č/ć/š/ž/đ) directly. Requires
/// Accessibility permission; refuses when secure input is active (password
/// fields), never touching the pasteboard. Safe to call off the main thread.
enum TextInjector {
    /// Max UTF-16 units per synthesized keyboard event. A single event carrying a
    /// very long string truncates/garbles in some apps (the real cause of "types
    /// worse than paste"); small chunks post reliably. Empirical, not documented API.
    private static let chunkSize = 16

    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    /// Prompt the user to grant Accessibility permission (System Settings).
    @discardableResult
    static func requestTrustPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func inject(_ text: String) -> InjectionResult {
        guard !text.isEmpty else { return .injected }
        guard AXIsProcessTrusted() else { return .notTrusted }
        // Refuse password fields. IsSecureEventInputEnabled covers native secure
        // fields and browsers that enable secure input (Chrome/Safari on password
        // fields); the AX subrole check adds native fields that don't toggle it.
        if IsSecureEventInputEnabled() || focusedFieldIsSecure() { return .secureField }

        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            var end = min(start + chunkSize, units.count)
            // Never split a UTF-16 surrogate pair at the chunk boundary (would
            // corrupt an emoji / rare glyph). High surrogates are 0xD800...0xDBFF.
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]), end - 1 > start {
                end -= 1
            }
            postUnicode(Array(units[start..<end]), source: source)
            start = end
            usleep(1200)  // ~1.2 ms lets the target app's input queue drain between events
        }
        return .injected
    }

    /// Post one chunk as a matched key-down (carrying the Unicode payload) + key-up.
    /// The payload goes on key-down only; key-up is the matching release (setting it
    /// on both can double-insert in some apps). Modifier flags are cleared so a
    /// logically-held Control (from the double-tap trigger) isn't read as a shortcut.
    private static func postUnicode(_ units: [UInt16], source: CGEventSource?) {
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
    /// toggle global secure input. An unknown/unavailable subrole is deliberately
    /// NOT treated as secure — doing so would break typing into ordinary web /
    /// Electron fields, which is the app's core purpose (residual risk documented
    /// in ADR 007).
    private static func focusedFieldIsSecure() -> Bool {
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

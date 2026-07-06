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
/// Accessibility permission; fails closed when secure input is active (password
/// fields), never touching the pasteboard.
enum TextInjector {
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    /// Prompt the user to grant Accessibility permission (System Settings).
    @discardableResult
    static func requestTrustPrompt() -> Bool {
        // kAXTrustedCheckOptionPrompt is imported as a non-concurrency-safe global
        // var; its documented CFString value is this literal.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func inject(_ text: String) -> InjectionResult {
        guard !text.isEmpty else { return .injected }
        guard AXIsProcessTrusted() else { return .notTrusted }
        // Password fields enable secure event input — refuse to type into them.
        if IsSecureEventInputEnabled() { return .secureField }

        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return .injected
        }
        // Clear real modifier state (e.g. Control logically held from the double-tap
        // trigger) so the text is not interpreted as keyboard shortcuts.
        down.flags = []
        up.flags = []
        // Unicode payload goes on key-down only; key-up is just the matching release
        // (setting it on both can double-insert in some apps).
        units.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .injected
    }
}

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
        post(units, source: source, keyDown: true)
        post(units, source: source, keyDown: false)
        return .injected
    }

    private static func post(_ units: [UInt16], source: CGEventSource?, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else {
            return
        }
        units.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
            }
        }
        event.post(tap: .cghidEventTap)
    }
}

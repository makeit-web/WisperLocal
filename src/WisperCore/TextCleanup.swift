import Foundation

/// Text cleanup applied at injection time (ADR 006) — never to the raw transcript.
/// Whisper is trained on written text and appends a sentence-ending period (or an
/// ellipsis), which breaks dictated URLs and file paths (`makeit-web.com.`). We
/// strip trailing periods/ellipses and surrounding whitespace before typing,
/// keeping every internal mark and intentional terminal `?` / `!`.
public enum TextCleanup {
    /// Characters treated as a strippable sentence terminator at the very end.
    private static let trailingStopMarks: Set<Character> = [".", "\u{2026}"]  // "." and "…"

    /// Returns `text` with trailing whitespace + any run of trailing period/ellipsis
    /// removed, and leading whitespace trimmed. Internal punctuation, `?`, `!`, and
    /// all diacritics are preserved.
    public static func forInjection(_ text: String) -> String {
        var result = Substring(text)
        while let last = result.last, last.isWhitespace || trailingStopMarks.contains(last) {
            result = result.dropLast()
        }
        while let first = result.first, first.isWhitespace {
            result = result.dropFirst()
        }
        return String(result)
    }
}

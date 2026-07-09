import Foundation

/// Text cleanup applied at injection time (ADR 006) — never to the raw transcript.
/// Whisper is trained on written text and appends a sentence-ending period (or an
/// ellipsis), which breaks dictated URLs and file paths (`makeit-web.com.`). We
/// strip trailing periods/ellipses and surrounding whitespace before typing,
/// keeping every internal mark and intentional terminal `?` / `!`.
///
/// Control characters are also filtered here — the single choke point before
/// synthetic keystrokes. A newline typed into a terminal is Return (executes the
/// pending line); ESC and other C0/C1 controls can trigger editor commands.
/// Line breaks become a space; other controls are dropped (ADR 008).
public enum TextCleanup {
    /// Characters treated as a strippable sentence terminator at the very end.
    private static let trailingStopMarks: Set<Character> = [".", "\u{2026}"]  // "." and "…"

    /// Scalars that separate lines; a run containing any of these maps to one space.
    /// Tab is included: dictated text never legitimately needs focus-moving tabs.
    private static let lineBreakScalars: Set<Unicode.Scalar> = [
        "\u{09}", "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{85}", "\u{2028}", "\u{2029}",
    ]

    /// Returns `text` with control characters neutralized, trailing whitespace +
    /// any run of trailing period/ellipsis removed, and leading whitespace trimmed.
    /// Internal punctuation, `?`, `!`, and all diacritics are preserved.
    public static func forInjection(_ text: String) -> String {
        var result = Substring(filterControlCharacters(text))
        while let last = result.last, last.isWhitespace || trailingStopMarks.contains(last) {
            result = result.dropLast()
        }
        while let first = result.first, first.isWhitespace {
            result = result.dropFirst()
        }
        return String(result)
    }

    /// Collapse each run of C0/C1 control scalars (incl. Unicode line separators)
    /// to a single space when the run breaks a line, or to nothing otherwise.
    private static func filterControlCharacters(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var runBreaksLine = false
        var inControlRun = false
        for scalar in text.unicodeScalars {
            let isControl = scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
                || lineBreakScalars.contains(scalar)
            if isControl {
                inControlRun = true
                runBreaksLine = runBreaksLine || lineBreakScalars.contains(scalar)
            } else {
                if inControlRun, runBreaksLine { scalars.append(" ") }
                inControlRun = false
                runBreaksLine = false
                scalars.append(scalar)
            }
        }
        if inControlRun, runBreaksLine { scalars.append(" ") }
        return String(scalars)
    }
}

import Testing

@testable import WisperCore

/// Behaviour spec for injection-time text cleanup (ADR 006): strip trailing
/// periods/ellipses + surrounding whitespace, keep internal punctuation and the
/// intentional terminal marks `?` / `!`.
struct TextCleanupTests {
    @Test func stripsTrailingPeriodFromURL() {
        #expect(TextCleanup.forInjection("makeit-web.com.") == "makeit-web.com")
    }

    @Test func stripsTrailingPeriodFromURLWithPath() {
        #expect(TextCleanup.forInjection("Otvori google.com/mail.") == "Otvori google.com/mail")
    }

    @Test func stripsTrailingPeriodFromProse() {
        #expect(TextCleanup.forInjection("Evo teksta.") == "Evo teksta")
    }

    @Test func keepsQuestionMark() {
        #expect(TextCleanup.forInjection("Kako si?") == "Kako si?")
    }

    @Test func keepsExclamationMark() {
        #expect(TextCleanup.forInjection("Super!") == "Super!")
    }

    @Test func preservesInternalPeriod() {
        #expect(TextCleanup.forInjection("3.14") == "3.14")
    }

    @Test func stripsOnlyFinalPeriodOfAbbreviation() {
        #expect(TextCleanup.forInjection("U.S.A.") == "U.S.A")
    }

    @Test func stripsRunOfTrailingPeriods() {
        #expect(TextCleanup.forInjection("Više točaka...") == "Više točaka")
    }

    @Test func stripsEllipsisCharacter() {
        #expect(TextCleanup.forInjection("Čekaj…") == "Čekaj")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(TextCleanup.forInjection("  spaced.  ") == "spaced")
    }

    @Test func preservesCroatianDiacritics() {
        #expect(TextCleanup.forInjection("Češe žđ ćč.") == "Češe žđ ćč")
    }

    @Test func handlesEmptyString() {
        #expect(TextCleanup.forInjection("") == "")
    }

    @Test func handlesOnlyPeriod() {
        #expect(TextCleanup.forInjection(".") == "")
    }

    // Control characters are filtered at the injection choke point: a newline
    // typed into a terminal is Return (executes the pending line), ESC can
    // trigger editor commands. Whisper output is untrusted model output.

    @Test func replacesInteriorNewlineWithSpace() {
        #expect(TextCleanup.forInjection("prvi red\ndrugi red.") == "prvi red drugi red")
    }

    @Test func replacesCRLFRunWithSingleSpace() {
        #expect(TextCleanup.forInjection("prvi\r\ndrugi") == "prvi drugi")
    }

    @Test func replacesTabWithSpace() {
        #expect(TextCleanup.forInjection("lijevo\tdesno") == "lijevo desno")
    }

    @Test func dropsNonWhitespaceControlCharacters() {
        #expect(TextCleanup.forInjection("zvuk\u{07}dalje") == "zvukdalje")
        #expect(TextCleanup.forInjection("esc\u{1B}dalje") == "escdalje")
        #expect(TextCleanup.forInjection("del\u{7F}dalje") == "deldalje")
    }

    @Test func mixedControlRunWithNewlineBecomesOneSpace() {
        #expect(TextCleanup.forInjection("a\u{07}\n\u{1B}b") == "a b")
    }

    @Test func replacesUnicodeLineSeparatorsWithSpace() {
        #expect(TextCleanup.forInjection("a\u{2028}b\u{2029}c") == "a b c")
    }

    @Test func trailingNewlineIsTrimmedNotSpaced() {
        #expect(TextCleanup.forInjection("kraj.\n") == "kraj")
    }
}

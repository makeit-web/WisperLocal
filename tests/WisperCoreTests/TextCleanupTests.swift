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
}

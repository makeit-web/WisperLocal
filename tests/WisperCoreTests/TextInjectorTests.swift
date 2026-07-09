import Testing

@testable import WisperCore

/// Behaviour spec for the injection decision chain and the UTF-16 chunker —
/// the app's top privacy invariant (never type into secure fields) and its
/// subtlest algorithm (never split a surrogate pair), tested through injected
/// probes (ADR 008; same pattern as ModelStore.resolveModelPath).
struct TextInjectorTests {
    // MARK: - chunkRanges (pure)

    @Test func emptyInputYieldsNoRanges() {
        #expect(TextInjector.chunkRanges(of: [], max: 16).isEmpty)
    }

    @Test func shortInputIsOneRange() {
        let units = Array("kava".utf16)
        #expect(TextInjector.chunkRanges(of: units, max: 16) == [0..<4])
    }

    @Test func exactMultipleSplitsEvenly() {
        let units = [UInt16](repeating: 65, count: 32)
        #expect(TextInjector.chunkRanges(of: units, max: 16) == [0..<16, 16..<32])
    }

    @Test func loneFinalUnitGetsOwnRange() {
        let units = [UInt16](repeating: 65, count: 17)
        #expect(TextInjector.chunkRanges(of: units, max: 16) == [0..<16, 16..<17])
    }

    @Test func highSurrogateAtBoundaryMovesBoundaryBack() {
        // 15 ASCII units then an emoji (surrogate pair) straddling position 15/16:
        // the chunk must end at 15 so the pair stays whole in the next chunk.
        var units = [UInt16](repeating: 65, count: 15)
        units.append(contentsOf: Array("😀".utf16))  // D83D DE00
        #expect(units.count == 17)
        #expect(TextInjector.chunkRanges(of: units, max: 16) == [0..<15, 15..<17])
    }

    @Test func rangesCoverEveryUnitExactlyOnce() {
        let units = Array(String(repeating: "š😀a", count: 23).utf16)
        let ranges = TextInjector.chunkRanges(of: units, max: 16)
        let reassembled = ranges.flatMap { Array(units[$0]) }
        #expect(reassembled == units)
        #expect(ranges.allSatisfy { !$0.isEmpty && $0.count <= 16 })
    }

    @Test func degenerateOneUnitChunkStillAdvances() {
        // With max=1 a surrogate pair cannot avoid being split; the
        // `end - 1 > start` guard must keep the loop advancing, not stall.
        let units = Array("😀".utf16)
        #expect(TextInjector.chunkRanges(of: units, max: 1) == [0..<1, 1..<2])
    }

    // MARK: - decision chain (fake probes)

    private final class Recorder {
        var chunks: [[UInt16]] = []
        var secureNow = false
    }

    private func probes(
        recorder: Recorder,
        trusted: Bool = true,
        secureOnPost: Bool = false
    ) -> InjectionProbes {
        InjectionProbes(
            isTrusted: { trusted },
            secureInputActive: { recorder.secureNow },
            focusedFieldIsSecure: { false },
            postChunk: { units in
                recorder.chunks.append(units)
                if secureOnPost { recorder.secureNow = true }
            },
            pace: {}
        )
    }

    @Test func emptyTextInjectsWithZeroEvents() {
        let recorder = Recorder()
        let result = TextInjector.inject("", probes: probes(recorder: recorder))
        #expect(result == .injected)
        #expect(recorder.chunks.isEmpty)
    }

    @Test func notTrustedRefusesBeforeAnyEvent() {
        let recorder = Recorder()
        let result = TextInjector.inject("tajna", probes: probes(recorder: recorder, trusted: false))
        #expect(result == .notTrusted)
        #expect(recorder.chunks.isEmpty)
    }

    @Test func secureInputActiveRefusesBeforeAnyEvent() {
        let recorder = Recorder()
        recorder.secureNow = true
        let result = TextInjector.inject("tajna", probes: probes(recorder: recorder))
        #expect(result == .secureField)
        #expect(recorder.chunks.isEmpty)
    }

    @Test func secureSubroleRefusesBeforeAnyEvent() {
        let recorder = Recorder()
        var fake = probes(recorder: recorder)
        fake.focusedFieldIsSecure = { true }
        let result = TextInjector.inject("tajna", probes: fake)
        #expect(result == .secureField)
        #expect(recorder.chunks.isEmpty)
    }

    @Test func trustIsCheckedBeforeSecureInput() {
        // Matches the shipped decision order: an untrusted process reports
        // .notTrusted even if secure input happens to be active.
        let recorder = Recorder()
        recorder.secureNow = true
        let result = TextInjector.inject("tajna", probes: probes(recorder: recorder, trusted: false))
        #expect(result == .notTrusted)
        #expect(recorder.chunks.isEmpty)
    }

    @Test func injectsAllTextChunked() {
        let recorder = Recorder()
        let text = String(repeating: "brza smeđa lisica ", count: 4)  // > 2 chunks
        let result = TextInjector.inject(text, probes: probes(recorder: recorder))
        #expect(result == .injected)
        #expect(recorder.chunks.flatMap { $0 } == Array(text.utf16))
        #expect(recorder.chunks.allSatisfy { $0.count <= 16 && !$0.isEmpty })
    }

    @Test func secureInputFlipMidInjectionAbortsRemainingChunks() {
        // TOCTOU guard: a password dialog stealing focus mid-injection flips
        // secure input; every remaining chunk must be withheld (fail closed).
        let recorder = Recorder()
        let text = String(repeating: "a", count: 64)  // 4 chunks
        let result = TextInjector.inject(
            text, probes: probes(recorder: recorder, secureOnPost: true)
        )
        #expect(result == .secureField)
        #expect(recorder.chunks.count == 1)
    }
}

import Testing

@testable import WisperCore

/// Resampling behaviour (no audio files needed — synthetic Float buffers).
struct AudioFileTests {
    @Test func resampleEmptyReturnsEmpty() throws {
        #expect(try AudioFile.resampleMono([], sourceRate: 48_000).isEmpty)
    }

    @Test func resampleAt16kIsIdentity() throws {
        let input: [Float] = [0.1, -0.2, 0.3, -0.4]
        #expect(try AudioFile.resampleMono(input, sourceRate: 16_000) == input)
    }

    @Test func resampleDownsamplesLength() throws {
        // 1 s of 48 kHz → ~1 s of 16 kHz (about a third of the samples).
        let input = [Float](repeating: 0, count: 48_000)
        let out = try AudioFile.resampleMono(input, sourceRate: 48_000)
        #expect(out.count > 14_000 && out.count < 18_000)
    }
}

/// Leak test (Swift Quality Profile §23): the capture object must not outlive its scope.
struct AudioCaptureLifetimeTests {
    @Test func deallocatesWhenReleased() {
        weak var weakRef: AudioCapture?
        do {
            let capture = AudioCapture()
            weakRef = capture
            #expect(weakRef != nil)
        }
        #expect(weakRef == nil)
    }
}

import Foundation
import Testing

@testable import WisperCore

/// These integration tests need a model in `models/` and the whisper.cpp sample
/// WAVs; they are skipped when those aren't present so the suite stays green on
/// a bare checkout.
struct WhisperContextTests {
    static let modelPath = "models/ggml-large-v3-turbo-q8_0.bin"
    static let jfkPath = "whisper.cpp/samples/jfk.wav"

    private static func assetsPresent() -> Bool {
        FileManager.default.fileExists(atPath: modelPath)
            && FileManager.default.fileExists(atPath: jfkPath)
    }

    @Test func transcribesEnglishSample() async throws {
        try #require(Self.assetsPresent(), "model/sample missing — skipping integration test")
        let samples = try AudioFile.loadPCM16kMono(path: Self.jfkPath)
        #expect(samples.count > 16_000)  // > 1 s of 16 kHz audio

        let context = try WhisperContext(modelPath: Self.modelPath)
        let text = try await context.transcribe(samples: samples, language: "en")
        #expect(text.lowercased().contains("countrymen") || text.lowercased().contains("country"))
    }

    @Test func modelLoadFailsCleanly() async throws {
        #expect(throws: WhisperError.self) {
            _ = try WhisperContext(modelPath: "models/does-not-exist.bin")
        }
    }
}

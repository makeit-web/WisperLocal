import Foundation
import Testing

@testable import WisperCore

/// These integration tests need a model in `models/` (scripts/download-model.sh)
/// and the whisper.cpp sample WAVs; the model-dependent test is *skipped* — via
/// `.enabled(if:)`, the only real skip in Swift Testing — when those aren't
/// present, so `swift test` stays green on a checkout without the 834 MB model.
/// (`#require` would record a FAILURE, not a skip — QA 2026-07-08. Building the
/// suite at all still needs whisper.cpp compiled: scripts/setup-whisper.sh.)
struct WhisperContextTests {
    static let modelPath = "models/ggml-large-v3-turbo-q8_0.bin"
    static let jfkPath = "whisper.cpp/samples/jfk.wav"

    static func assetsPresent() -> Bool {
        FileManager.default.fileExists(atPath: modelPath)
            && FileManager.default.fileExists(atPath: jfkPath)
    }

    @Test(.enabled(
        if: WhisperContextTests.assetsPresent(),
        "model + jfk.wav not present — run scripts/download-model.sh"
    ))
    func transcribesEnglishSample() async throws {
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

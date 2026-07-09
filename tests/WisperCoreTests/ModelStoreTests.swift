import Testing

@testable import WisperCore

/// RAM-tier selection (ADR-003) and model-path preference (Croatian fine-tune →
/// RAM model → turbo fallback), tested through the pure cores.
struct ModelStoreTests {
    @Test func picksTurboForLowRam() {
        #expect(ModelStore.modelName(forRamGiB: 8) == "ggml-large-v3-turbo-q8_0.bin")
    }

    @Test func picksTurboAtTwelveGigThreshold() {
        #expect(ModelStore.modelName(forRamGiB: 12) == "ggml-large-v3-turbo-q8_0.bin")
    }

    @Test func picksLargeForHighRam() {
        #expect(ModelStore.modelName(forRamGiB: 16) == "ggml-large-v3-q8_0.bin")
    }

    @Test func prefersCroatianFineTuneWhenPresent() {
        let path = ModelStore.resolveModelPath(dir: "/m", ramGiB: 16, fileExists: { _ in true })
        #expect(path == "/m/ggml-hr-parla-q8_0.bin")
    }

    @Test func fallsBackToRamModelWhenNoFineTune() {
        let path = ModelStore.resolveModelPath(dir: "/m", ramGiB: 16) { $0.hasSuffix("ggml-large-v3-q8_0.bin") }
        #expect(path == "/m/ggml-large-v3-q8_0.bin")
    }

    @Test func fallsBackToTurboWhenOnlyTurboPresent() {
        // Dev flow: a >12 GB machine where large-v3 quantization hasn't run yet
        // still dictates with the turbo model download-model.sh always fetches.
        let path = ModelStore.resolveModelPath(dir: "/m", ramGiB: 16) {
            $0.hasSuffix("ggml-large-v3-turbo-q8_0.bin")
        }
        #expect(path == "/m/ggml-large-v3-turbo-q8_0.bin")
    }

    @Test func fallsBackToFineTuneWhenNothingPresent() {
        // The last-resort name must match what installers actually provision:
        // install-prebuilt.sh ships ONLY the fine-tune (and deletes the turbo),
        // so a turbo fallback was a rung no colleague's Mac could ever satisfy
        // (QA 2026-07-08) — the error path now names the restorable file.
        let path = ModelStore.resolveModelPath(dir: "/m", ramGiB: 16, fileExists: { _ in false })
        #expect(path == "/m/ggml-hr-parla-q8_0.bin")
    }
}

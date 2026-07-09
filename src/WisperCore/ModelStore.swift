import Foundation

/// Resolves the whisper model for this machine by installed RAM (ADR-003):
/// ≤ ~12 GB (Air 8 GB tier) → turbo q8_0; otherwise (Mac mini M4 16 GB) → large-v3 q8_0.
///
/// Model filenames + the RAM threshold are re-encoded in scripts/download-model.sh,
/// scripts/make-app.sh and scripts/install-prebuilt.sh — keep all in sync.
public enum ModelStore {
    /// RAM-tier model choice — pure, so it is unit-tested directly.
    static func modelName(forRamGiB ramGiB: Double) -> String {
        ramGiB <= 12 ? "ggml-large-v3-turbo-q8_0.bin" : "ggml-large-v3-q8_0.bin"
    }

    public static func defaultModelName() -> String {
        modelName(forRamGiB: physicalMemoryGiB())
    }

    /// The models directory: `~/Library/Application Support/WisperLocal/models`
    /// if present (the installed app), else `models` (dev / CLI from repo root).
    public static func modelsDirectory() -> String {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("WisperLocal/models").path
            if FileManager.default.fileExists(atPath: dir) { return dir }
        }
        return "models"
    }

    /// Full path to the model to load. Prefers the Croatian fine-tune if installed
    /// (more accurate for HR, turbo-sized), else the RAM-selected model.
    public static func defaultModelPath() -> String {
        resolveModelPath(
            dir: modelsDirectory(),
            ramGiB: physicalMemoryGiB(),
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    /// Testable core of `defaultModelPath` — pure given its `fileExists` dependency.
    /// Chain: fine-tune → RAM model → turbo (dev machines have it even before the
    /// large-v3 quantize step). When NOTHING exists, return the fine-tune name:
    /// it is the one file every install path provisions (install-prebuilt.sh
    /// ships ONLY it and deletes the turbo), so the failure log names a file
    /// the installer can actually restore (QA 2026-07-08).
    static func resolveModelPath(
        dir: String, ramGiB: Double, fileExists: (String) -> Bool
    ) -> String {
        let fineTune = "\(dir)/ggml-hr-parla-q8_0.bin"
        if fileExists(fineTune) { return fineTune }
        let primary = "\(dir)/\(modelName(forRamGiB: ramGiB))"
        if fileExists(primary) { return primary }
        let turbo = "\(dir)/ggml-large-v3-turbo-q8_0.bin"
        if fileExists(turbo) { return turbo }
        return fineTune
    }

    private static func physicalMemoryGiB() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }
}

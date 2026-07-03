import Foundation

/// Resolves the whisper model for this machine by installed RAM (ADR-003):
/// ≤ ~12 GB (Air 8 GB tier) → turbo q8_0; otherwise (Mac mini M4 16 GB) → large-v3 q8_0.
public enum ModelStore {
    public static func defaultModelName() -> String {
        let gib = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        return gib <= 12 ? "ggml-large-v3-turbo-q8_0.bin" : "ggml-large-v3-q8_0.bin"
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

    /// Full path to the RAM-selected model, falling back to the turbo model.
    public static func defaultModelPath() -> String {
        let dir = modelsDirectory()
        let primary = "\(dir)/\(defaultModelName())"
        if FileManager.default.fileExists(atPath: primary) { return primary }
        return "\(dir)/ggml-large-v3-turbo-q8_0.bin"
    }
}

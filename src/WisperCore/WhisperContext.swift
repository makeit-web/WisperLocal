import CWhisper
import Foundation

public enum WhisperError: Error {
    case modelLoadFailed(String)
    case transcriptionFailed(Int32)
}

/// A whisper.cpp context.
///
/// The raw `OpaquePointer` is only ever touched on `queue` (a serial queue) — a
/// permanent, documented isolation invariant, which is why this is
/// `@unchecked Sendable` (Swift Quality Profile §6, the C-boundary carve-out).
/// `whisper_full` is a synchronous, multi-second **blocking** C call, so it runs
/// on `queue`, never on the Swift cooperative pool (§13); results are bridged
/// back with a `CheckedContinuation` resumed exactly once on every path.
public final class WhisperContext: @unchecked Sendable {
    private let ctx: OpaquePointer
    private let queue = DispatchQueue(label: "local.wisper.whisper-inference")

    public init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let created = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.modelLoadFailed(modelPath)
        }
        ctx = created
    }

    deinit {
        whisper_free(ctx)
    }

    /// Transcribe 16 kHz mono Float32 samples. `language` is an ISO code
    /// ("hr", "en") or "auto".
    public func transcribe(samples: [Float], language: String = "hr") async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.runFull(samples: samples, language: language))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runFull(samples: [Float], language: String) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.no_timestamps = true
        params.translate = false
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))

        let status = language.withCString { langPtr -> Int32 in
            params.language = langPtr
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
            }
        }
        guard status == 0 else { throw WhisperError.transcriptionFailed(status) }

        var text = ""
        let segments = whisper_full_n_segments(ctx)
        for index in 0..<segments {
            if let segment = whisper_full_get_segment_text(ctx, index) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

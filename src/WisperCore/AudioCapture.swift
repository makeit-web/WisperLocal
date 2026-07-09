import AVFoundation

/// One finished dictation: 16 kHz mono Float32 samples, plus whether the
/// recording hit the memory cap and lost its tail (surfaced to the user —
/// a silently shortened transcript would be a hidden wrong result).
public struct Recording: Sendable {
    public let samples: [Float]
    public let truncated: Bool
}

/// Microphone capture for push-to-talk dictation.
///
/// The input tap runs on a background audio queue (not the real-time render
/// thread), so it accumulates raw mono samples at the hardware rate under a
/// lightweight lock; the single 16 kHz resample happens once at `stop()`, which
/// avoids per-buffer converter-state artifacts. `@unchecked Sendable` with the
/// documented invariant that mutable state is only touched under `lock`.
public final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var native: [Float] = []
    private var sourceRate: Double = 16_000
    private var running = false
    private var truncated = false
    /// Memory bound: stop accumulating past this many seconds so a forgotten
    /// recording can't grow unbounded next to the ~834 MB model on an 8 GB
    /// machine (~115 MB at 48 kHz for the 600 s default). Injectable for tests.
    private let maxSeconds: Double

    public convenience init() {
        self.init(maxSeconds: 600)
    }

    init(maxSeconds: Double) {
        self.maxSeconds = maxSeconds
    }

    public func start() throws {
        // Never touch AVAudioEngine without microphone permission — doing so
        // raises an uncatchable ObjC exception. The Phase 3 app requests this.
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            throw AudioError.readFailed("microphone permission not granted (status \(status.rawValue))")
        }
        lock.lock()
        if running { lock.unlock(); throw AudioError.readFailed("already recording") }
        native = []; truncated = false; running = true
        lock.unlock()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            lock.lock(); running = false; lock.unlock()
            throw AudioError.readFailed("no usable microphone input — grant Microphone permission")
        }
        lock.lock(); sourceRate = format.sampleRate; lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.accumulate(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            lock.lock(); running = false; lock.unlock()
            throw AudioError.readFailed("engine start: \(error.localizedDescription)")
        }
    }

    /// Stop capture and return the recording as 16 kHz mono Float32.
    public func stop() throws -> Recording {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        return try finishRecording()
    }

    /// Engine-free core of `stop()` (testable with synthetic buffers): takes
    /// sole ownership of the accumulated samples — releasing the up-to-~115 MB
    /// buffer instead of holding it while the app idles — and resamples once.
    func finishRecording() throws -> Recording {
        lock.lock()
        let raw = native
        native = []
        let rate = sourceRate
        let wasTruncated = truncated
        running = false
        lock.unlock()
        return Recording(
            samples: try AudioFile.resampleMono(raw, sourceRate: rate),
            truncated: wasTruncated
        )
    }

    func accumulate(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData else { return }
        let slice = UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength))
        var justTruncated = false
        lock.lock()
        if native.count < Int(sourceRate * maxSeconds) {
            native.append(contentsOf: slice)
        } else if !truncated {
            truncated = true
            justTruncated = true
        }
        lock.unlock()
        // Log outside the lock (file IO); once per recording, on first drop.
        if justTruncated {
            Log.event("recording hit the max-duration cap — discarding further audio")
        }
    }
}

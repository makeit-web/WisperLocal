import AVFoundation

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

    public init() {}

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    public func start() throws {
        // Never touch AVAudioEngine without microphone permission — doing so
        // raises an uncatchable ObjC exception. The Phase 3 app requests this.
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            throw AudioError.readFailed("microphone permission not granted (status \(status.rawValue))")
        }
        lock.lock(); native.removeAll(keepingCapacity: true); running = true; lock.unlock()

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
    public func stop() throws -> [Float] {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        lock.lock()
        let raw = native
        let rate = sourceRate
        running = false
        lock.unlock()
        return try AudioFile.resampleMono(raw, sourceRate: rate)
    }

    private func accumulate(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData else { return }
        let slice = UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength))
        lock.lock()
        native.append(contentsOf: slice)
        lock.unlock()
    }
}

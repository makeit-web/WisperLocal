import AVFoundation

public enum AudioError: Error {
    case openFailed(String)
    case formatUnavailable
    case bufferAllocFailed
    case readFailed(String)
    case conversionFailed(String)
    case noChannelData
}

/// Single-shot feed flag for the AVAudioConverter pull block. The block runs
/// synchronously inside `convert(to:error:withInputFrom:)`, so this is not
/// actually concurrent — `@unchecked Sendable` with that documented invariant.
private final class ConverterFeed: @unchecked Sendable {
    var supplied = false
}

/// Loads audio files as the 16 kHz mono Float32 that whisper.cpp expects.
public enum AudioFile {
    public static func loadPCM16kMono(path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioError.openFailed("\(path): \(error.localizedDescription)")
        }

        let sourceFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: max(frames, 1)) else {
            throw AudioError.bufferAllocFailed
        }
        do {
            try file.read(into: input)
        } catch {
            throw AudioError.readFailed(error.localizedDescription)
        }

        if sourceFormat.sampleRate == 16_000, sourceFormat.channelCount == 1 {
            return try samples(from: input)
        }
        return try resampleTo16kMono(input, from: sourceFormat)
    }

    /// Resample an already-mono Float32 signal to 16 kHz.
    public static func resampleMono(_ input: [Float], sourceRate: Double) throws -> [Float] {
        if sourceRate == 16_000 || input.isEmpty { return input }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.count)) else {
            throw AudioError.bufferAllocFailed
        }
        buffer.frameLength = AVAudioFrameCount(input.count)
        guard let channel = buffer.floatChannelData else { throw AudioError.noChannelData }
        input.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel[0].update(from: base, count: input.count)
            }
        }
        return try resampleTo16kMono(buffer, from: format)
    }

    private static func resampleTo16kMono(
        _ input: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat
    ) throws -> [Float] {
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        ) else {
            throw AudioError.formatUnavailable
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
            throw AudioError.conversionFailed("no converter \(sourceFormat.sampleRate) -> 16000")
        }
        let ratio = 16_000.0 / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw AudioError.bufferAllocFailed
        }

        let feed = ConverterFeed()
        var conversionError: NSError?
        let outcome = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if feed.supplied {
                statusPointer.pointee = .noDataNow
                return nil
            }
            feed.supplied = true
            statusPointer.pointee = .haveData
            return input
        }
        if outcome == .error {
            throw AudioError.conversionFailed(conversionError?.localizedDescription ?? "unknown")
        }
        return try samples(from: output)
    }

    private static func samples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let channel = buffer.floatChannelData else {
            throw AudioError.noChannelData
        }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }
}

import AVFoundation
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

/// Buffer ownership + the 10-minute memory cap, tested through the internal
/// `accumulate`/`finishRecording` seam with synthetic buffers (no microphone,
/// no permissions). QA 2026-07-08: the cap used to trip silently and the raw
/// recording (up to ~115 MB) stayed resident after stop().
struct AudioCaptureBufferTests {
    /// 16 kHz mono synthetic buffer — at the default sourceRate the resample
    /// step is an exact identity, so sample counts compare exactly.
    private func makeBuffer(frames: Int, value: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        if let channel = buffer.floatChannelData {
            for index in 0..<frames { channel[0][index] = value }
        }
        return buffer
    }

    @Test func stopReturnsAccumulatedSamples() throws {
        let capture = AudioCapture(maxSeconds: 600)
        capture.accumulate(makeBuffer(frames: 2048))
        let recording = try capture.finishRecording()
        #expect(recording.samples.count == 2048)
        #expect(!recording.truncated)
    }

    @Test func stopReleasesTheBuffer() throws {
        // After stop() the capture object must not keep the recording alive:
        // a second drain sees an empty buffer.
        let capture = AudioCapture(maxSeconds: 600)
        capture.accumulate(makeBuffer(frames: 2048))
        _ = try capture.finishRecording()
        let second = try capture.finishRecording()
        #expect(second.samples.isEmpty)
    }

    @Test func capStopsAccumulationAndIsReported() throws {
        // Cap = 0.25 s at 16 kHz = 4000 samples. The buffer that crosses the
        // cap still appends whole (documented up-to-one-buffer overshoot);
        // everything after it is dropped and the drop is surfaced.
        let capture = AudioCapture(maxSeconds: 0.25)
        capture.accumulate(makeBuffer(frames: 2048))
        capture.accumulate(makeBuffer(frames: 2048))  // crosses 4000 → appends to 4096
        capture.accumulate(makeBuffer(frames: 2048))  // at cap → dropped
        capture.accumulate(makeBuffer(frames: 2048))  // still dropped
        let recording = try capture.finishRecording()
        #expect(recording.samples.count == 4096)
        #expect(recording.truncated)
    }

    @Test func recordingBelowCapIsNotTruncated() throws {
        let capture = AudioCapture(maxSeconds: 0.25)
        capture.accumulate(makeBuffer(frames: 2048))
        let recording = try capture.finishRecording()
        #expect(!recording.truncated)
    }
}

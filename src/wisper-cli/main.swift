import Foundation
import WisperCore

@main
struct WisperCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            printUsage()
            exit(2)
        }

        var modelPath = "models/ggml-large-v3-turbo-q8_0.bin"
        var language = "auto"
        var seconds: Double?

        // Options are scanned after the subcommand's positionals, and anything
        // unrecognized is a hard usage error — a silently ignored typo
        // (`--land hr`) used to produce misleading results with no signal.
        func parseOptions(from startIndex: Int) {
            var index = startIndex
            while index < args.count {
                switch args[index] {
                case "--model" where index + 1 < args.count:
                    modelPath = args[index + 1]; index += 2
                case "--lang" where index + 1 < args.count:
                    language = args[index + 1]; index += 2
                case "--seconds" where index + 1 < args.count:
                    // Validate here: the trapping Double→UInt64 conversion in
                    // record() crashes on negative/huge values otherwise. Upper
                    // bound = AudioCapture's 600 s cap, so we never record audio
                    // that would be silently discarded past the cap.
                    guard let value = Double(args[index + 1]), value > 0, value <= 600 else {
                        log("error: --seconds expects a number in (0, 600], got '\(args[index + 1])' (capture caps at 10 min)")
                        printUsage()
                        exit(2)
                    }
                    seconds = value; index += 2
                default:
                    log("error: unknown or incomplete option '\(args[index])'")
                    printUsage()
                    exit(2)
                }
            }
        }

        switch args[1] {
        case "file":
            guard args.count >= 3 else { printUsage(); exit(2) }
            parseOptions(from: 3)
            try await transcribeFile(args[2], modelPath: modelPath, language: language)
        case "record":
            parseOptions(from: 2)
            try await record(modelPath: modelPath, language: language, seconds: seconds)
        default:
            printUsage()
            exit(2)
        }
    }

    static func transcribeFile(_ path: String, modelPath: String, language: String) async throws {
        let samples = try AudioFile.loadPCM16kMono(path: path)
        let context = try WhisperContext(modelPath: modelPath)
        print(try await context.transcribe(samples: samples, language: language))
    }

    static func record(modelPath: String, language: String, seconds: Double?) async throws {
        // Load the model DURING recording — the 1–3 s load is independent of
        // capture, so serializing it after stop() just pads the user's wait.
        let modelTask = Task.detached { try WhisperContext(modelPath: modelPath) }
        let capture = AudioCapture()
        try capture.start()
        if let seconds {
            log("recording \(seconds)s...")
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } else {
            log("recording... press Enter to stop")
            _ = readLine()
        }
        let recording = try capture.stop()
        if recording.truncated { log("warning: recording hit the duration cap; tail was dropped") }
        log("captured \(String(format: "%.1f", Double(recording.samples.count) / 16_000))s; transcribing...")
        let context = try await modelTask.value
        print(try await context.transcribe(samples: recording.samples, language: language))
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func printUsage() {
        log("""
        usage:
          wisper-cli file <wav> [--model <path>] [--lang hr|en|auto]
          wisper-cli record [--seconds N] [--model <path>] [--lang hr|en|auto]
        """)
    }
}

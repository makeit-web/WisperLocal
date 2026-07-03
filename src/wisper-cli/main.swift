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
        var language = "hr"
        var seconds: Double?
        var index = 2
        while index < args.count {
            switch args[index] {
            case "--model" where index + 1 < args.count: modelPath = args[index + 1]; index += 2
            case "--lang" where index + 1 < args.count: language = args[index + 1]; index += 2
            case "--seconds" where index + 1 < args.count: seconds = Double(args[index + 1]); index += 2
            default: index += 1
            }
        }

        switch args[1] {
        case "file":
            guard args.count >= 3 else { printUsage(); exit(2) }
            try await transcribeFile(args[2], modelPath: modelPath, language: language)
        case "record":
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
        let capture = AudioCapture()
        try capture.start()
        if let seconds {
            log("recording \(seconds)s...")
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } else {
            log("recording... press Enter to stop")
            _ = readLine()
        }
        let samples = try capture.stop()
        log("captured \(String(format: "%.1f", Double(samples.count) / 16_000))s; transcribing...")
        let context = try WhisperContext(modelPath: modelPath)
        print(try await context.transcribe(samples: samples, language: language))
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

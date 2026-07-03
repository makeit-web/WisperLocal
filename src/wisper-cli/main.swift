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
        guard args.count >= 3, args[1] == "file" else {
            print("usage: wisper-cli file <wav> [--model <path>] [--lang hr|en|auto]")
            exit(2)
        }

        let wavPath = args[2]
        var modelPath = "models/ggml-large-v3-turbo-q8_0.bin"
        var language = "hr"
        var index = 3
        while index + 1 < args.count {
            switch args[index] {
            case "--model": modelPath = args[index + 1]; index += 2
            case "--lang": language = args[index + 1]; index += 2
            default: index += 1
            }
        }

        let samples = try AudioFile.loadPCM16kMono(path: wavPath)
        let context = try WhisperContext(modelPath: modelPath)
        let text = try await context.transcribe(samples: samples, language: language)
        print(text)
    }
}

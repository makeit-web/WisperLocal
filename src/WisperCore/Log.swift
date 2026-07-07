import Foundation

/// Local, transcript-free file logger (CLAUDE.md + Swift Quality Profile §18/§36).
/// Writes lifecycle + error events to `~/Library/Logs/WisperLocal/wisperlocal.log`
/// and nowhere else — no network, ever. The message is a `StaticString`, so a
/// transcript or audio value (a runtime `String` / `[Float]`) is **type-level
/// impossible** to log by mistake; only compile-time-constant text, our own
/// `Error` values, and integer status codes are accepted.
public enum Log {
    private static let queue = DispatchQueue(label: "local.wisper.log")

    private static let fileURL: URL? = {
        guard let library = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = library.appendingPathComponent("Logs/WisperLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wisperlocal.log")
    }()

    public static func event(_ message: StaticString) { write("INFO", "\(message)") }

    public static func error(_ message: StaticString, _ error: Error? = nil) {
        write("ERROR", error.map { "\(message) — \($0)" } ?? "\(message)")
    }

    public static func error(_ message: StaticString, code: Int) {
        write("ERROR", "\(message) (code \(code))")
    }

    private static func write(_ level: String, _ text: String) {
        guard let fileURL else { return }
        let now = Date()
        queue.async {
            let line = "\(now.ISO8601Format()) [\(level)] \(text)\n"
            guard let data = line.data(using: .utf8) else { return }
            // Logging failures are swallowed on purpose — never crash the app
            // (or block a work path) because a log write failed.
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}

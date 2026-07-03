// swift-tools-version: 6.0
import PackageDescription

// whisper.cpp is built (static, Metal) into this gitignored dir by
// scripts/setup-whisper.sh (pinned to v1.9.1). Paths are relative to the repo root.
let ws = "whisper.cpp/build-static"

let whisperLink: [LinkerSetting] = [
    .unsafeFlags([
        "-L\(ws)/src",
        "-L\(ws)/ggml/src",
        "-L\(ws)/ggml/src/ggml-blas",
        "-L\(ws)/ggml/src/ggml-metal",
        "-lwhisper", "-lggml", "-lggml-cpu", "-lggml-blas", "-lggml-metal", "-lggml-base",
        "-lc++",
    ]),
    .linkedFramework("Metal"),
    .linkedFramework("Accelerate"),
    .linkedFramework("AVFoundation"),
]

let package = Package(
    name: "WisperLocal",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CWhisper", path: "src/CWhisper"),
        .target(name: "WisperCore", dependencies: ["CWhisper"], path: "src/WisperCore"),
        .executableTarget(
            name: "wisper-cli",
            dependencies: ["WisperCore"],
            path: "src/wisper-cli",
            linkerSettings: whisperLink
        ),
        .testTarget(
            name: "WisperCoreTests",
            dependencies: ["WisperCore"],
            path: "tests/WisperCoreTests",
            linkerSettings: whisperLink
        ),
    ]
)

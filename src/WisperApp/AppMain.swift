import AppKit
import AVFoundation
import Carbon.HIToolbox
import WisperCore

/// WisperLocal menu-bar app. Global hotkey (⌃⌥D) toggles push-to-talk dictation:
/// record → transcribe → deliver. Phase 3 delivers to the clipboard; Phase 4
/// replaces that with Accessibility injection into the focused app.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private let capture = AudioCapture()
    private var context: WhisperContext?
    private var isRecording = false
    private let language = "hr"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu-bar only, no dock icon
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        loadModel()
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if !granted { self.setIcon("🚫") }
                self.installHotKey()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🎤"
        let menu = NSMenu()
        menu.addItem(withTitle: "WisperLocal — ⌃⌥D to dictate", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func loadModel() {
        do {
            context = try WhisperContext(modelPath: ModelStore.defaultModelPath())
        } catch {
            setIcon("⚠️")
            NSLog("WisperLocal: model load failed: \(error)")
        }
    }

    private func installHotKey() {
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
    }

    private func toggle() {
        isRecording ? stopAndTranscribe() : startRecording()
    }

    private func startRecording() {
        do {
            try capture.start()
            isRecording = true
            setIcon("🔴")
        } catch {
            setIcon("🚫")
            NSLog("WisperLocal: capture start failed: \(error)")
        }
    }

    private func stopAndTranscribe() {
        isRecording = false
        setIcon("⏳")
        let ctx = context
        let lang = language
        Task { @MainActor in
            do {
                let samples = try self.capture.stop()
                guard let ctx else { self.setIcon("⚠️"); return }
                let text = try await ctx.transcribe(samples: samples, language: lang)
                self.deliver(text)
                self.setIcon("🎤")
            } catch {
                self.setIcon("⚠️")
                NSLog("WisperLocal: transcription failed: \(error)")
            }
        }
    }

    /// Phase 3 interim delivery: clipboard. Phase 4 replaces this with
    /// Accessibility injection into the focused app (no pasteboard).
    private func deliver(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func setIcon(_ symbol: String) {
        statusItem?.button?.title = symbol
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

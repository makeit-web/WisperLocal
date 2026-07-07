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
    private var doubleTap: DoubleTapCtrl?
    private let splash = SplashWindow()
    private let capture = AudioCapture()
    private var context: WhisperContext?
    private var isRecording = false
    private var language = "hr"  // default Croatian (best accuracy); switch via the menu

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // menu-bar only, no dock icon
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        splash.show(for: 3)
        loadModel()
        _ = TextInjector.requestTrustPrompt()  // Accessibility, for text injection
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
        menu.addItem(withTitle: "WisperLocal — double-tap Ctrl (or ⌃⌥D)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for (title, code) in [("Croatian", "hr"), ("English", "en"), ("Auto-detect", "auto")] {
            let entry = NSMenuItem(title: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            entry.representedObject = code
            entry.state = code == language ? .on : .off
            languageMenu.addItem(entry)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(
            withTitle: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings), keyEquivalent: ""
        )
        menu.addItem(.separator())
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { " · v\($0)" } ?? ""
        let credit = NSMenuItem(title: "Built by Ante Kujundžić\(version)", action: nil, keyEquivalent: "")
        credit.isEnabled = false
        menu.addItem(credit)
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
        // Primary trigger: double-tap Control. Secondary: ⌃⌥D.
        doubleTap = DoubleTapCtrl { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
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
            } catch {
                self.setIcon("⚠️")
                NSLog("WisperLocal: transcription failed: \(error)")
            }
        }
    }

    /// Inject the transcription into the focused app. If Accessibility isn't
    /// granted yet, keep the text on the clipboard so it isn't lost and prompt.
    private func deliver(_ text: String) {
        guard !text.isEmpty else { setIcon("🎤"); return }
        switch TextInjector.inject(text) {
        case .injected:
            setIcon("🎤")
        case .secureField:
            setIcon("🔒")  // refuse to type into a password field
        case .notTrusted:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            setIcon("🔐")
            _ = TextInjector.requestTrustPrompt()
        }
    }

    private func setIcon(_ symbol: String) {
        statusItem?.button?.title = symbol
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        language = code
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String) == code ? .on : .off }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

import AppKit
import AVFoundation
import Carbon.HIToolbox
import UserNotifications
import WisperCore

/// WisperLocal menu-bar app. Global hotkey (⌃⌥D) toggles push-to-talk dictation:
/// record → transcribe → deliver. Phase 3 delivers to the clipboard; Phase 4
/// replaces that with Accessibility injection into the focused app.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var loginMenuItem: NSMenuItem?
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
        Log.event("app launched")
        setupStatusItem()
        splash.show(for: 3)
        loadModel()
        _ = TextInjector.requestTrustPrompt()  // Accessibility, for text injection
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
        menu.delegate = self  // refresh the Launch-at-Login checkmark on open
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

        let loginItem = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: ""
        )
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)
        loginMenuItem = loginItem

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
            Log.event("model loaded")
        } catch {
            setIcon("⚠️")
            Log.error("model load failed", error)
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
            Log.error("capture start failed", error)
        }
    }

    private func stopAndTranscribe() {
        isRecording = false
        setIcon("⏳")
        let ctx = context
        let lang = language
        let cap = capture
        Task { @MainActor in
            do {
                // Resample off the main actor so long recordings don't stall the UI.
                let samples = try await Task.detached(priority: .userInitiated) {
                    try cap.stop()
                }.value
                // Ignore accidental near-empty recordings (< ~0.5 s) instead of a scary ⚠️.
                guard samples.count >= 8_000 else { self.setIcon("🎤"); return }
                guard let ctx else { self.setIcon("⚠️"); Log.error("no model loaded"); return }
                let text = try await ctx.transcribe(samples: samples, language: lang)
                self.deliver(text)
            } catch {
                self.setIcon("⚠️")
                Log.error("transcription failed", error)
            }
        }
    }

    /// Type the transcription into the focused app, off the main thread (chunked
    /// injection takes a few ms). Nothing is auto-copied to the clipboard — the
    /// transcript never leaves the machine implicitly (ADR 007); if injection is
    /// blocked the user copies it explicitly via the menu.
    private func deliver(_ rawText: String) {
        // Strip Whisper's trailing period/ellipsis before typing (ADR 006) so
        // dictated URLs/paths aren't broken. Faithful transcript stays in WisperCore.
        let text = TextCleanup.forInjection(rawText)
        guard !text.isEmpty else { setIcon("🎤"); return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = TextInjector.inject(text)
            await MainActor.run { self?.handleInjection(result) }
        }
    }

    private func handleInjection(_ result: InjectionResult) {
        switch result {
        case .injected:
            setIcon("🎤")
        case .secureField:
            setIcon("🔒")  // refused to type into a password field
            notify("Password field", "Not typing into a secure field, for your safety.")
        case .notTrusted:
            setIcon("🔐")
            notify("Accessibility needed", "Enable WisperLocal in Accessibility, then dictate again.")
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

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            try LoginItem.toggle()
        } catch {
            Log.error("launch-at-login toggle failed", error)
            notify("Launch at Login", "Couldn't change the setting — try System Settings → General → Login Items.")
        }
        sender.state = LoginItem.isEnabled ? .on : .off
        if LoginItem.needsApproval { LoginItem.openSystemSettings() }
    }

    // NSMenuDelegate: keep the Launch-at-Login checkmark in sync if the user
    // changed it from System Settings while the app was running.
    func menuNeedsUpdate(_ menu: NSMenu) {
        loginMenuItem?.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

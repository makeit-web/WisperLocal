import AppKit
import AVFoundation
import Carbon.HIToolbox
import UserNotifications
import WisperCore

/// WisperLocal menu-bar app. Global hotkey (double-tap Ctrl, or ⌃⌥D) toggles
/// push-to-talk dictation: record → transcribe → inject into the focused app
/// via Accessibility. The transcript never touches the clipboard (ADR 007).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// The single dictation state — the icon is derived from it in one place
    /// (`didSet`), never set ad hoc. A bool + icon-as-state let the mic stay
    /// hot behind an idle 🎤 (QA 2026-07-08, HIGH); this enum is the fix.
    private enum DictationState: Equatable {
        case loading        // model load in flight
        case idle           // ready to dictate
        case recording      // mic hot
        case transcribing   // whisper running; toggles are ignored
        case notice(String) // idle-equivalent, showing a persistent glyph (🚫 ⚠️ 🔒 🔐)

        var icon: String {
            switch self {
            case .loading, .transcribing: return "⏳"
            case .idle: return "🎤"
            case .recording: return "🔴"
            case .notice(let glyph): return glyph
            }
        }
    }

    private var statusItem: NSStatusItem?
    private var titleMenuItem: NSMenuItem?
    private var loginMenuItem: NSMenuItem?
    private var hotKey: HotKey?
    private var doubleTap: DoubleTapCtrl?
    private let splash = SplashWindow()
    private let capture = AudioCapture()
    private var context: WhisperContext?
    private var language = "hr"  // default Croatian (best accuracy); switch via the menu
    private static let menuTitle = "WisperLocal — double-tap Ctrl (or ⌃⌥D)"

    private var state: DictationState = .loading {
        didSet { statusItem?.button?.title = state.icon }
    }

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
                if !granted { self.state = .notice("🚫") }
                self.installHotKey()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = state.icon
        let menu = NSMenu()
        menu.delegate = self  // refresh the checkmark + Accessibility hint on open
        let title = NSMenuItem(title: Self.menuTitle, action: nil, keyEquivalent: "")
        menu.addItem(title)
        titleMenuItem = title
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

    /// Load the whisper model off the main actor — it is a multi-second read of
    /// an 834 MB–1.7 GB file, and doing it synchronously froze the splash and
    /// menu for exactly the window the splash exists to cover (QA 2026-07-08).
    private func loadModel() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try WhisperContext(modelPath: ModelStore.defaultModelPath()) }
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let ctx):
                    self.context = ctx
                    Log.event("model loaded")
                    // Only leave .loading if nothing (e.g. mic denial) got there first.
                    if self.state == .loading { self.state = .idle }
                case .failure(let error):
                    Log.error("model load failed", error)
                    if self.state == .loading { self.state = .notice("⚠️") }
                }
            }
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
        if hotKey?.isRegistered == false {
            // Both triggers dead would look like a dead app — say so visibly.
            // Don't promise the double-tap works: it needs Accessibility too.
            notify(
                "Hotkey unavailable",
                TextInjector.isTrusted()
                    ? "⌃⌥D is taken by another app. Double-tap Ctrl still works."
                    : "⌃⌥D is taken by another app — grant Accessibility so double-tap Ctrl can work."
            )
        }
    }

    private func toggle() {
        switch state {
        case .idle, .notice:
            startRecording()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break  // ignore toggles until the pipeline finishes — no second hot mic
        case .loading:
            notify("Model still loading", "One moment — dictation starts once the model is ready.")
        }
    }

    private func startRecording() {
        do {
            try capture.start()
            state = .recording
        } catch {
            state = .notice("🚫")
            Log.error("capture start failed", error)
        }
    }

    private func stopAndTranscribe() {
        state = .transcribing  // gates toggle() until every path below resolves
        let ctx = context
        let lang = language
        let cap = capture
        Task { @MainActor in
            do {
                // Resample off the main actor so long recordings don't stall the UI.
                let recording = try await Task.detached(priority: .userInitiated) {
                    try cap.stop()
                }.value
                if recording.truncated {
                    notify(
                        "Recording cut at 10 minutes",
                        "Dictation stopped accumulating at the cap — the tail was not recorded."
                    )
                }
                // Ignore accidental near-empty recordings (< ~0.5 s) instead of a scary ⚠️.
                guard recording.samples.count >= 8_000 else { self.state = .idle; return }
                guard let ctx else { self.state = .notice("⚠️"); Log.error("no model loaded"); return }
                let text = try await ctx.transcribe(samples: recording.samples, language: lang)
                self.deliver(text)
            } catch {
                self.state = .notice("⚠️")
                Log.error("transcription failed", error)
            }
        }
    }

    /// Type the transcription into the focused app (TextInjector runs the
    /// chunked posting on its own serial queue, off the main thread). Nothing
    /// is ever copied to the clipboard — the transcript never leaves the
    /// machine (ADR 007); if injection is blocked the dictation is NOT
    /// delivered (🔐/🔒 icon + notification) and the user re-dictates after
    /// granting Accessibility.
    private func deliver(_ rawText: String) {
        // Strip Whisper's trailing period/ellipsis before typing (ADR 006) so
        // dictated URLs/paths aren't broken. Faithful transcript stays in WisperCore.
        let text = TextCleanup.forInjection(rawText)
        guard !text.isEmpty else { state = .idle; return }
        Task { [weak self] in
            let result = await TextInjector.inject(text)
            self?.handleInjection(result)
        }
    }

    private func handleInjection(_ result: InjectionResult) {
        switch result {
        case .injected:
            state = .idle
        case .secureField:
            state = .notice("🔒")  // refused to type into a password field
            notify("Password field", "Not typing into a secure field, for your safety.")
        case .notTrusted:
            state = .notice("🔐")
            notify("Accessibility needed", "Enable WisperLocal in Accessibility, then dictate again.")
            _ = TextInjector.requestTrustPrompt()
        }
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
    // changed it from System Settings while the app was running, and flag the
    // double-tap trigger as inactive while Accessibility is not granted (the
    // global flags monitor silently never fires without it).
    func menuNeedsUpdate(_ menu: NSMenu) {
        loginMenuItem?.state = LoginItem.isEnabled ? .on : .off
        titleMenuItem?.title = TextInjector.isTrusted()
            ? Self.menuTitle
            : Self.menuTitle + "  — grant Accessibility first"
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

import AppKit

/// A small, non-interactive splash shown near the top of the screen on launch:
/// confirms the app is running and points the eye to the menu-bar 🎤. Auto-dismisses.
@MainActor
final class SplashWindow {
    private var window: NSWindow?

    func show(for seconds: TimeInterval = 3) {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 400, height: 132)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 56  // just under the menu bar
        )
        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.ignoresMouseEvents = true
        win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true

        let iconView = NSImageView(frame: NSRect(x: 22, y: size.height - 70, width: 48, height: 48))
        iconView.image = NSApp.applicationIconImage
        blur.addSubview(iconView)

        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { " v\($0)" } ?? ""
        blur.addSubview(label("WisperLocal\(version)", x: 82, y: size.height - 54, w: 300, size: 19, weight: .bold))
        blur.addSubview(label("Running — look for 🎤 at the top-right of your screen ↗",
                              x: 22, y: 46, w: size.width - 44, size: 12.5, weight: .regular))
        blur.addSubview(label("Built by Ante Kujundžić", x: 22, y: 16, w: size.width - 44,
                              size: 11.5, weight: .medium, color: .secondaryLabelColor))

        win.contentView = blur
        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; win.animator().alphaValue = 1 }
        window = win

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.45; win.animator().alphaValue = 0 },
                                                 completionHandler: { [weak self] in
                self?.window?.close()
                self?.window = nil
            })
        }
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat,
                       size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = NSRect(x: x, y: y, width: w, height: size + 10)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isBezeled = false
        field.isEditable = false
        field.drawsBackground = false
        return field
    }
}

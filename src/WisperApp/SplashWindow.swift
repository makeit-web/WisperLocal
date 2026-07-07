import AppKit

/// A small, non-interactive splash shown near the top of the screen on launch:
/// confirms the app is running and points the eye to the menu-bar 🎤. Auto-dismisses.
@MainActor
final class SplashWindow {
    private var window: NSWindow?

    func show(for seconds: TimeInterval = 3) {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 448, height: 112)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 56  // just under the menu bar
        )
        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        win.isReleasedWhenClosed = false  // ARC owns it; close() must not also release (would crash)
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

        // Icon: vertically centred on the left.
        let iconSize: CGFloat = 54
        let iconView = NSImageView(frame: NSRect(
            x: 22, y: (size.height - iconSize) / 2, width: iconSize, height: iconSize))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        blur.addSubview(iconView)

        // Text block: three lines to the right of the icon, evenly spaced and
        // vertically centred as a group. Line baselines at y = 62 / 40 / 18.
        let textX: CGFloat = 92
        let textW = size.width - textX - 20
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { " v\($0)" } ?? ""
        blur.addSubview(label("WisperLocal\(version)", x: textX, y: 62, w: textW,
                              size: 18, weight: .bold, color: .labelColor))
        blur.addSubview(label("Running — 🎤 is at the top-right of your screen ↗", x: textX, y: 39, w: textW,
                              size: 12.5, weight: .regular, color: .secondaryLabelColor))
        blur.addSubview(label("Built by Ante Kujundžić", x: textX, y: 17, w: textW,
                              size: 11.5, weight: .medium, color: .tertiaryLabelColor))

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
                       size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = NSRect(x: x, y: y, width: w, height: size + 8)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.isBezeled = false
        field.isEditable = false
        field.drawsBackground = false
        return field
    }
}

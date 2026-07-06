import AppKit

/// Fires `onDoubleTap` when the Control key is pressed twice within `interval`.
/// Uses a global modifier-flags monitor, which requires Accessibility permission
/// (the same permission text injection needs). Runs on the main thread.
final class DoubleTapCtrl {
    private var monitor: Any?
    private var lastCtrlDown: TimeInterval = 0
    private var ctrlHeld = false
    private let interval: TimeInterval
    private let onDoubleTap: () -> Void

    init(interval: TimeInterval = 0.4, onDoubleTap: @escaping () -> Void) {
        self.interval = interval
        self.onDoubleTap = onDoubleTap
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let ctrlNow = flags.contains(.control)

        if ctrlNow, !ctrlHeld {
            ctrlHeld = true
            guard flags == .control else {  // Control alone, no other modifiers
                lastCtrlDown = 0
                return
            }
            let now = event.timestamp
            if now - lastCtrlDown <= interval {
                lastCtrlDown = 0
                onDoubleTap()
            } else {
                lastCtrlDown = now
            }
        } else if !ctrlNow {
            ctrlHeld = false
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

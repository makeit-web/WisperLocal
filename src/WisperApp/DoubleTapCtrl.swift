import AppKit
import WisperCore

/// Fires `onDoubleTap` when the Control key is pressed twice within the
/// detector's interval. Thin NSEvent adapter over `DoubleTapDetector` (all
/// timing/chord logic + tests live in WisperCore). Uses a global
/// modifier-flags monitor, which requires Accessibility permission (the same
/// permission text injection needs). Runs on the main thread.
final class DoubleTapCtrl {
    private var monitor: Any?
    private var detector = DoubleTapDetector()
    private let onDoubleTap: () -> Void

    init(onDoubleTap: @escaping () -> Void) {
        self.onDoubleTap = onDoubleTap
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let inputs = DoubleTapDetector.chordInputs(event.modifierFlags)
            if self.detector.register(
                ctrlDown: inputs.ctrlDown, ctrlAlone: inputs.ctrlAlone, at: event.timestamp
            ) {
                self.onDoubleTap()
            }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

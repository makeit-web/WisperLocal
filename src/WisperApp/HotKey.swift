import Carbon.HIToolbox
import Foundation
import WisperCore

/// A global hotkey registered via Carbon. `onFire` runs on the main run loop
/// (Carbon delivers hot-key events there). `self` is passed to the C handler via
/// the `userData` pointer, so the C callback captures nothing.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onFire: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) {
        self.onFire = onFire

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().onFire()
            return noErr
        }
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        if installStatus != noErr {
            Log.error("hotkey handler install failed", code: Int(installStatus))
        }

        let id = EventHotKeyID(signature: OSType(0x5753_5052), id: 1)  // 'WSPR'
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref
        )
        if registerStatus != noErr {
            Log.error("hotkey registration failed — may conflict with another app", code: Int(registerStatus))
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

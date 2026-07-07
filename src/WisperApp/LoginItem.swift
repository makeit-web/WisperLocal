import ServiceManagement

/// Login-item registration for the main app bundle via SMAppService (macOS 13+).
/// Registering makes WisperLocal launch automatically at login; because the app
/// is an `LSUIElement` it starts silently into the menu bar. Errors are thrown to
/// the caller and surfaced — never swallowed.
enum LoginItem {
    /// True when the app is registered and enabled as a login item.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// True when macOS is holding the item for the user's approval in
    /// System Settings → General → Login Items (e.g. it was disabled there before).
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Flip the registration: register if currently off, unregister if on.
    static func toggle() throws {
        if isEnabled {
            try SMAppService.mainApp.unregister()
        } else {
            try SMAppService.mainApp.register()
        }
    }

    /// Open System Settings → Login Items so the user can approve or manage it.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

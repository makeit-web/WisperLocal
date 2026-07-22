import AppKit
import Foundation
import IOKit

/// A running application the user can actually see and quit.
///
/// In a shipped build the *only* way to make one is from a live pid, which is
/// what keeps `Log` honest: `Log.event(_:app:)` takes this type rather than a
/// `String`, so a transcript cannot be handed to it — not even from inside this
/// module, where transcripts actually live (see `Log`, and CLAUDE.md "never
/// send transcripts anywhere").
public struct RunningApp: Equatable, Sendable {
    public let name: String

    #if DEBUG
    /// Test-only seam, compiled out of release builds on purpose: an
    /// arbitrary-`String` initializer available to `WisperCore` at large would
    /// let a transcript be wrapped and logged, which is exactly the mistake the
    /// type exists to make impossible (Codex review, 2026-07-22).
    init(name: String) {
        self.name = name
    }
    #endif

    /// Fails when the pid has no application, when the application is a
    /// background/system process (`activationPolicy != .regular`), or when it
    /// has no display name.
    ///
    /// The background filter is not cosmetic: only a `.regular` app has a dock
    /// icon the user can actually find and quit, so naming anything else would
    /// send them hunting a process they cannot act on. An unnameable holder is
    /// reported as "unknown" instead (ADR 009).
    public init?(pid: pid_t) {
        // NSRunningApplication is documented thread-safe and NS_SWIFT_SENDABLE,
        // so this is legal from the injection queue. Its time-varying
        // properties only refresh on main-run-loop turns; the two read here are
        // fixed for a process's lifetime, so that caveat does not apply.
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              let name = app.localizedName,
              !name.isEmpty
        else { return nil }
        self.name = name
    }
}

/// Reads which app is *likely* holding the session-wide secure event input lock.
///
/// `IsSecureEventInputEnabled()` answers whether input is locked; it does not
/// say by whom. The window server publishes a pid in the IORegistry root's
/// `IOConsoleUsers` array under `kCGSSessionSecureInputPID`, present only while
/// a lock is held — the same value `ioreg -l | grep SecureInput` prints.
///
/// **It is a lead, not a fact.** Measured 2026-07-22: a process that takes the
/// lock is *not* the pid reported — the reported pid is the application that
/// was frontmost when the lock was engaged. For the ordinary case (a GUI app
/// opening its own password prompt) those are the same app, which is why the
/// Microsoft Word incident resolved correctly; for a background process taking
/// the lock they are not. Every user-facing use of this must stay hedged, and
/// must never tell the user an app is definitely to blame (ADR 009).
enum SecureInput {
    /// The app most likely holding the lock, or `nil` when there is none or it
    /// cannot be named (see `RunningApp.init(pid:)`).
    static func likelyHolder() -> RunningApp? {
        guard let pid = holderPID() else { return nil }
        return RunningApp(pid: pid)
    }

    /// Raw reported pid, or `nil` when no lock is held. Two IPC round trips —
    /// call only on a path that is already refusing, never per chunk.
    static func holderPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }

        guard let property = IORegistryEntryCreateCFProperty(
            root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
        ), let sessions = property.takeRetainedValue() as? [[String: Any]] else { return nil }

        for session in sessions {
            if let pid = session["kCGSSessionSecureInputPID"] as? pid_t { return pid }
        }
        return nil
    }
}

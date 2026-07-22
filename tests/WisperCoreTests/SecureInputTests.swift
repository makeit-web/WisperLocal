import AppKit
import Carbon.HIToolbox
import Testing

@testable import WisperCore

/// Behaviour spec for identifying the app the OS *reports* against the
/// session-wide secure event input lock — the app that was frontmost when the
/// lock was engaged, which is a likely holder, not a certain one (ADR 009).
/// Origin: 2026-07-22, Microsoft Word held the lock and every dictation was
/// refused with a misleading "password field" message.
///
/// `.serialized` is required, not stylistic: two tests here take the real,
/// process-wide secure input lock, and running them concurrently makes one
/// release the lock out from under the other.
@Suite(.serialized)
struct SecureInputTests {
    @Test func deadPidYieldsNoApp() {
        #expect(RunningApp(pid: -1) == nil)
    }

    @Test func onlyUserVisibleAppsAreNamed() {
        // Verified empirically 2026-07-22: a lock taken by a plain process is
        // reported in the registry against a background helper (Universal
        // Control, .accessory). Naming such a process would send the user
        // chasing something they can neither see nor quit — only .regular apps
        // (dock icon, quittable) may ever be named in a user-facing message.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .regular {
            #expect(
                RunningApp(pid: app.processIdentifier) == nil,
                "background process \(app.localizedName ?? "?") must not be named"
            )
        }
    }

    @Test func regularAppResolvesToItsName() {
        guard let visible = NSWorkspace.shared.runningApplications.first(
            where: { $0.activationPolicy == .regular && $0.localizedName?.isEmpty == false }
        ) else { return }  // no GUI app running (headless) — nothing to assert
        #expect(RunningApp(pid: visible.processIdentifier)?.name == visible.localizedName)
    }

    @Test func holderPidTracksTheSessionLock() {
        // Integration: take the real lock, confirm the IORegistry read sees it,
        // release it. Covers the IOConsoleUsers / kCGSSessionSecureInputPID
        // path that no fake probe can exercise. Written to tolerate a lock
        // already held by some other app while the suite runs.
        let before = SecureInput.holderPID()
        #expect(EnableSecureEventInput() == noErr)

        // Release exactly once, even if a future edit puts a throwing call
        // below: the OS reference-counts the lock per process, so a second
        // Disable must never run (Codex adversarial review, 2026-07-22).
        var releaseStatus: OSStatus?
        defer { if releaseStatus == nil { _ = DisableSecureEventInput() } }

        let underLock = SecureInput.holderPID()
        releaseStatus = DisableSecureEventInput()

        #expect(releaseStatus == noErr)
        #expect(underLock != nil, "the lock must be visible while held")
        #expect(SecureInput.holderPID() == before, "the lock must be released again")
    }

    @Test func liveHolderProbeIsWiredAndSafeUnderLock() {
        // The shipped closure, not a fake — the seam no fake can cover. It runs
        // here off the main thread, as it does in the app (injection has its own
        // serial queue).
        //
        // Deliberately does NOT assert `probes.secureInputActive()`: measured
        // 2026-07-22, `IsSecureEventInputEnabled()` reports false inside this
        // test process even while the registry shows the lock, and true in a
        // process that has an NSApplication and a run loop — which the shipped
        // menu-bar app has and the test runner does not. Asserting it here
        // would test the harness, not the app.
        let probes = InjectionProbes.live()
        #expect(EnableSecureEventInput() == noErr)

        var releaseStatus: OSStatus?
        defer { if releaseStatus == nil { _ = DisableSecureEventInput() } }

        let lockVisibleInRegistry = SecureInput.holderPID() != nil
        _ = probes.secureInputHolder()  // must not trap; the name is env-dependent
        releaseStatus = DisableSecureEventInput()

        #expect(releaseStatus == noErr)
        #expect(lockVisibleInRegistry)
    }
}

import AppKit

/// Locks the Mac down while the bar says you're focusing, and undoes it after.
///
/// - Quits the blocked apps and quits them again if they're reopened.
/// - Optionally runs a Shortcut to turn a macOS Focus on/off (there is no
///   public API for Focus; Shortcuts' "Set Focus" action is the supported way).
/// - Reopens the blocked apps that were running before, once focus ends.
@MainActor
final class FocusGuard {
    private(set) var isActive = false
    private var quitWhileActive = Set<String>()
    private var launchObserver: NSObjectProtocol?

    var settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        active ? engage() : release()
    }

    /// Quits blocked apps that are running now - used when an app is added mid-session.
    func enforceNow() {
        guard isActive else { return }
        quitBlockedApps()
    }

    private func quitBlockedApps() {
        for app in NSWorkspace.shared.runningApplications where isBlocked(app) {
            if let id = app.bundleIdentifier { quitWhileActive.insert(id) }
            app.terminate()
        }
    }

    private func engage() {
        quitWhileActive = []
        quitBlockedApps()
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated {
                guard let self, self.isBlocked(app) else { return }
                app.terminate()
            }
        }
        runShortcut(settings.focusOnShortcut)
    }

    private func release() {
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        runShortcut(settings.focusOffShortcut)
        guard settings.reopenAppsAfter else { return }
        for id in quitWhileActive {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
        quitWhileActive = []
    }

    private func isBlocked(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return settings.blockedBundleIDs.contains(id)
    }

    /// Runs a Shortcut by name, if one is configured. Failures are ignored:
    /// a missing shortcut shouldn't stop app blocking from working.
    private func runShortcut(_ name: String) {
        guard !name.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", name]
        try? task.run()
    }
}

import Foundation

/// Stored in UserDefaults under the app's bundle id (com.busybar.busymacbar).
struct Settings {
    private static let legacyBundleID = "com.busybar.busymac"
    private static let migrationMarker = "didMigrateBusyMacSettingsV1"
    private static let keysToMigrate = [
        "host",
        "token",
        "blockedBundleIDs",
        "focusOnShortcut",
        "focusOffShortcut",
        "reopenAppsAfter",
    ]

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?

    init() {
        self.init(
            defaults: .standard,
            legacyDefaults: UserDefaults(suiteName: Self.legacyBundleID)
        )
    }

    init(defaults: UserDefaults, legacyDefaults: UserDefaults?) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        migrateLegacyDefaultsIfNeeded()
    }

    private func migrateLegacyDefaultsIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationMarker) else { return }
        defer { defaults.set(true, forKey: Self.migrationMarker) }
        guard let legacyDefaults else { return }

        for key in Self.keysToMigrate where defaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    var host: String {
        get { defaults.string(forKey: "host") ?? "busybar.local" }
        set { defaults.set(newValue, forKey: "host") }
    }

    /// Only needed if the bar has local API protection turned on.
    var token: String {
        get { defaults.string(forKey: "token") ?? "" }
        set { defaults.set(newValue, forKey: "token") }
    }

    /// Apps quit and kept closed while focusing. Slack by default.
    var blockedBundleIDs: [String] {
        get { defaults.stringArray(forKey: "blockedBundleIDs") ?? ["com.tinyspeck.slackmacgap"] }
        set { defaults.set(newValue, forKey: "blockedBundleIDs") }
    }

    /// Names of Shortcuts to run when focus starts / ends. Skipped if the shortcut doesn't exist.
    var focusOnShortcut: String {
        get { defaults.string(forKey: "focusOnShortcut") ?? "BUSY On" }
        set { defaults.set(newValue, forKey: "focusOnShortcut") }
    }

    var focusOffShortcut: String {
        get { defaults.string(forKey: "focusOffShortcut") ?? "BUSY Off" }
        set { defaults.set(newValue, forKey: "focusOffShortcut") }
    }

    /// Reopen blocked apps (in the background) that were running when focus ends.
    var reopenAppsAfter: Bool {
        get { defaults.object(forKey: "reopenAppsAfter") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "reopenAppsAfter") }
    }
}

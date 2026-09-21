import Foundation

/// Stored in UserDefaults under the app's bundle id (com.busybar.busymac).
struct Settings {
    private static let defaults = UserDefaults.standard

    var host: String {
        get { Self.defaults.string(forKey: "host") ?? "busybar.local" }
        set { Self.defaults.set(newValue, forKey: "host") }
    }

    /// Only needed if the bar has local API protection turned on.
    var token: String {
        get { Self.defaults.string(forKey: "token") ?? "" }
        set { Self.defaults.set(newValue, forKey: "token") }
    }

    /// Apps quit and kept closed while focusing. Slack by default.
    var blockedBundleIDs: [String] {
        get { Self.defaults.stringArray(forKey: "blockedBundleIDs") ?? ["com.tinyspeck.slackmacgap"] }
        set { Self.defaults.set(newValue, forKey: "blockedBundleIDs") }
    }

    /// Names of Shortcuts to run when focus starts / ends. Skipped if the shortcut doesn't exist.
    var focusOnShortcut: String {
        get { Self.defaults.string(forKey: "focusOnShortcut") ?? "BUSY On" }
        set { Self.defaults.set(newValue, forKey: "focusOnShortcut") }
    }

    var focusOffShortcut: String {
        get { Self.defaults.string(forKey: "focusOffShortcut") ?? "BUSY Off" }
        set { Self.defaults.set(newValue, forKey: "focusOffShortcut") }
    }

    /// Reopen blocked apps (in the background) that were running when focus began.
    var reopenAppsAfter: Bool {
        get { Self.defaults.object(forKey: "reopenAppsAfter") as? Bool ?? true }
        set { Self.defaults.set(newValue, forKey: "reopenAppsAfter") }
    }
}

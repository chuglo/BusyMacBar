import Foundation

@main
struct SettingsMigrationTests {
    static func main() {
        let migrationKey = "didMigrateBusyMacSettingsV1"
        let suiteRoot = "com.busybar.busymacbar.tests.\(UUID().uuidString)"
        let legacySuite = "\(suiteRoot).legacy"
        let currentSuite = "\(suiteRoot).current"
        let legacy = UserDefaults(suiteName: legacySuite)!
        let current = UserDefaults(suiteName: currentSuite)!

        defer {
            legacy.removePersistentDomain(forName: legacySuite)
            current.removePersistentDomain(forName: currentSuite)
        }

        legacy.set("legacy-busybar.local", forKey: "host")
        legacy.set("legacy-token", forKey: "token")
        legacy.set(["com.example.blocked"], forKey: "blockedBundleIDs")
        legacy.set("Legacy Focus On", forKey: "focusOnShortcut")
        legacy.set("Legacy Focus Off", forKey: "focusOffShortcut")
        legacy.set(false, forKey: "reopenAppsAfter")

        var migrated = Settings(defaults: current, legacyDefaults: legacy)
        precondition(migrated.host == "legacy-busybar.local")
        precondition(migrated.token == "legacy-token")
        precondition(migrated.blockedBundleIDs == ["com.example.blocked"])
        precondition(migrated.focusOnShortcut == "Legacy Focus On")
        precondition(migrated.focusOffShortcut == "Legacy Focus Off")
        precondition(migrated.reopenAppsAfter == false)
        precondition(current.bool(forKey: migrationKey))

        migrated.host = "new-busybar.local"
        legacy.set("changed-after-migration.local", forKey: "host")
        precondition(Settings(defaults: current, legacyDefaults: legacy).host == "new-busybar.local")

        let preservedSuiteRoot = "com.busybar.busymacbar.tests.\(UUID().uuidString)"
        let preservedLegacySuite = "\(preservedSuiteRoot).legacy"
        let preservedCurrentSuite = "\(preservedSuiteRoot).current"
        let preservedLegacy = UserDefaults(suiteName: preservedLegacySuite)!
        let preservedCurrent = UserDefaults(suiteName: preservedCurrentSuite)!
        defer {
            preservedLegacy.removePersistentDomain(forName: preservedLegacySuite)
            preservedCurrent.removePersistentDomain(forName: preservedCurrentSuite)
        }
        preservedLegacy.set("legacy-host.local", forKey: "host")
        preservedCurrent.set("already-configured.local", forKey: "host")
        precondition(
            Settings(defaults: preservedCurrent, legacyDefaults: preservedLegacy).host == "already-configured.local"
        )

        print("settings migration checks passed")
    }
}

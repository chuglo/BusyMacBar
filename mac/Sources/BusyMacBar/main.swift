import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var settings = Settings()
    private lazy var guardian = FocusGuard(settings: settings)

    private var state: SessionState?
    private var reachable = false
    private var lastError: String?
    /// card_id -> "Busy" / "Custom", so the menu can say which card is running.
    private var cardNames: [String: String] = [:]
    /// "busy"/"custom" -> the card's title, e.g. "BUSY", "ZEN".
    private var slotTitles: [String: String] = [:]
    private var cardNamesFetched = Date.distantPast

    private var client: BusyBarClient { BusyBarClient(host: settings.host, token: settings.token) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        render()

        // The local snapshot API has no push, so poll. Two seconds keeps
        // Slack's shutdown close to when you hit Start, and is cheap on the LAN.
        Task { [weak self] in
            while let self {
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        // Tick the countdown between polls.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    // MARK: Polling

    private func refresh() async {
        do {
            let snapshot = try await client.snapshot()
            reachable = true
            lastError = nil
            state = SessionState(snapshot: snapshot)
            lastPoll = Date()
            if Date().timeIntervalSince(cardNamesFetched) > 60 { await refreshCardNames() }
        } catch {
            reachable = false
            lastError = error.localizedDescription
            // Leave the guard as it was: a Wi-Fi blip shouldn't reopen Slack mid-session.
        }
        if reachable { guardian.setActive(state?.isFocusing ?? false) }
        render()
    }

    private func refreshCardNames() async {
        cardNamesFetched = Date()
        for slot in ["busy", "custom"] {
            guard let card = try? await client.profile(slot), let id = card["id"] as? String else { continue }
            let title = (card["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? slot.capitalized
            cardNames[id] = title
            slotTitles[slot] = title
        }
    }

    // MARK: Menu bar

    private func render() {
        guard let button = statusItem.button else { return }
        guard reachable else {
            button.title = "BUSY ⚠︎"
            return
        }
        guard let state else {
            button.title = "BUSY"
            return
        }
        let icon = state.isPaused ? "⏸" : (state.phase == .rest ? "☕" : "●")
        button.title = "\(icon) \(countdown(state))"
    }

    private func countdown(_ state: SessionState) -> String {
        guard let left = state.timeLeftMs else { return "Busy" }
        // Between polls, count down locally so the clock doesn't jump.
        let secs = max(0, (left - (state.isPaused ? 0 : sinceLastPollMs)) / 1000)
        return secs >= 3600
            ? String(format: "%d:%02d:%02d", secs / 3600, secs / 60 % 60, secs % 60)
            : String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private var lastPoll = Date()
    private var sinceLastPollMs: Int { Int(Date().timeIntervalSince(lastPoll) * 1000) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !reachable {
            menu.addItem(disabled("Can't reach bar at \(settings.host)"))
            if let lastError { menu.addItem(disabled(lastError)) }
        } else if let state {
            let card = cardNames[state.cardID] ?? "Session"
            let phase = state.isPaused ? "paused" : (state.phase == .rest ? "on a break" : "focusing")
            menu.addItem(disabled("\(card) — \(phase)"))
            menu.addItem(item(state.isPaused ? "Resume" : "Pause", #selector(togglePause)))
            menu.addItem(item("Stop", #selector(stop)))
        } else {
            menu.addItem(disabled("Nothing running"))
            menu.addItem(item("Start \(slotTitles["busy"] ?? "Busy")", #selector(startBusy)))
            menu.addItem(item("Start \(slotTitles["custom"] ?? "Custom")", #selector(startCustom)))
        }

        menu.addItem(.separator())
        let blocked = settings.blockedBundleIDs
        let apps = NSMenuItem(title: guardian.isActive ? "Blocking \(blocked.count) App(s)" : "Blocked Apps",
                              action: nil, keyEquivalent: "")
        let appsMenu = NSMenu()
        if blocked.isEmpty { appsMenu.addItem(disabled("None")) }
        for id in blocked {
            let entry = item(appName(id), #selector(unblockApp(_:)))
            entry.representedObject = id
            entry.image = appIcon(id)
            entry.toolTip = "Click to stop blocking"
            appsMenu.addItem(entry)
        }
        if !blocked.isEmpty { appsMenu.addItem(disabled("Click an app to unblock it")) }
        appsMenu.addItem(.separator())
        appsMenu.addItem(item("Add App…", #selector(addBlockedApp)))
        apps.submenu = appsMenu
        menu.addItem(apps)

        menu.addItem(.separator())
        menu.addItem(item("Bar Address…", #selector(editHost)))
        menu.addItem(item("API Token…", #selector(editToken)))
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit BusyMacBar", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func appIcon(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    // MARK: Blocked apps

    @objc private func addBlockedApp() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose apps to block while focusing"
        panel.prompt = "Block"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        var blocked = settings.blockedBundleIDs
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, !blocked.contains(id)
            else { continue }
            blocked.append(id)
        }
        settings.blockedBundleIDs = blocked
        guardian.enforceNow()
    }

    @objc private func unblockApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.blockedBundleIDs.removeAll { $0 == id }
    }

    // MARK: Actions

    @objc private func startBusy() { act { try await $0.start(slot: "busy") } }
    @objc private func startCustom() { act { try await $0.start(slot: "custom") } }
    @objc private func stop() { act { try await $0.stop() } }
    @objc private func togglePause() {
        let pause = !(state?.isPaused ?? false)
        act { try await $0.setPaused(pause) }
    }

    private func act(_ work: @escaping (BusyBarClient) async throws -> Void) {
        let client = client
        Task {
            do { try await work(client) } catch { showError(error) }
            await refresh()
        }
    }

    @objc private func editHost() {
        if let value = prompt("Bar address", "The bar's name or IP on your network, e.g. busybar.local or 192.168.1.50.", settings.host) {
            settings.host = value
            cardNames = [:]
            slotTitles = [:]
            cardNamesFetched = .distantPast
            Task { await refresh() }
        }
    }

    @objc private func editToken() {
        if let value = prompt("API token", "Only needed if you turned on API protection in the bar's settings. Leave empty otherwise.", settings.token) {
            settings.token = value
            Task { await refresh() }
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch { showError(error) }
    }

    @objc private func quit() {
        guardian.setActive(false)
        NSApp.terminate(nil)
    }

    private func prompt(_ title: String, _ info: String, _ value: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespaces)
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

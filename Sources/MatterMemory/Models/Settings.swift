import Foundation

/// UserDefaults-backed settings. Every value has a sane default so nothing
/// needs to be written on first launch.
enum Settings {
    static let changed = Notification.Name("MatterMemory.SettingsChanged")
    private static let d = UserDefaults.standard

    /// Minutes a background server may sit idle before its web view is torn
    /// down. 0 = never unload.
    static var idleUnloadMinutes: Int {
        get { d.object(forKey: "idleUnloadMinutes") as? Int ?? 20 }
        set { d.set(newValue, forKey: "idleUnloadMinutes"); post() }
    }
    static let idleUnloadChoices = [0, 5, 10, 20, 30, 60, 120]

    /// Minutes after the window is closed/minimised before *every* server is
    /// unloaded (the poller keeps mention notifications flowing). 0 = never.
    static var hiddenUnloadMinutes: Int {
        get { d.object(forKey: "hiddenUnloadMinutes") as? Int ?? 10 }
        set { d.set(newValue, forKey: "hiddenUnloadMinutes"); post() }
    }
    static let hiddenUnloadChoices = [0, 2, 5, 10, 30, 60]

    /// WebKit lockdown mode: no JIT, no WebAssembly, no web fonts. Much smaller
    /// JavaScript heap for the Mattermost bundle at the cost of some polish.
    static var lowMemoryMode: Bool {
        get { bool("lowMemoryMode", true) }
        set { d.set(newValue, forKey: "lowMemoryMode"); post() }
    }

    /// Flat sidebar (unread first, then recent) instead of the web app's categories.
    static var compactSidebar: Bool {
        get { bool("compactSidebar", true) }
        set { d.set(newValue, forKey: "compactSidebar"); post() }
    }

    /// Keep the server tab bar even with a single native server.
    static var alwaysShowServerBar: Bool {
        get { bool("alwaysShowServerBar", false) }
        set { d.set(newValue, forKey: "alwaysShowServerBar"); post() }
    }

    static var showMenuBarIcon: Bool {
        get { bool("showMenuBarIcon", true) }
        set { d.set(newValue, forKey: "showMenuBarIcon"); post() }
    }

    /// Menu-bar-only mode: no Dock icon, the app lives in the status bar.
    static var hideDockIcon: Bool {
        get { bool("hideDockIcon", false) }
        set { d.set(newValue, forKey: "hideDockIcon"); post() }
    }

    static var notificationsEnabled: Bool {
        get { bool("notificationsEnabled", true) }
        set { d.set(newValue, forKey: "notificationsEnabled"); post() }
    }

    /// Show a dot on the dock icon when there are unread channels but no mentions.
    static var showUnreadBadge: Bool {
        get { bool("showUnreadBadge", true) }
        set { d.set(newValue, forKey: "showUnreadBadge"); post() }
    }

    /// Poll the REST API for unread counts of servers whose web view was unloaded.
    static var backgroundUnreadPolling: Bool {
        get { bool("backgroundUnreadPolling", true) }
        set { d.set(newValue, forKey: "backgroundUnreadPolling"); post() }
    }

    static var unloadOnMemoryPressure: Bool {
        get { bool("unloadOnMemoryPressure", true) }
        set { d.set(newValue, forKey: "unloadOnMemoryPressure"); post() }
    }

    static var webInspectorEnabled: Bool {
        get { bool("webInspectorEnabled", false) }
        set { d.set(newValue, forKey: "webInspectorEnabled"); post() }
    }

    static var showMemoryReadout: Bool {
        get { bool("showMemoryReadout", true) }
        set { d.set(newValue, forKey: "showMemoryReadout"); post() }
    }

    enum ServerMode: String { case native, web }

    /// Native (REST + WebSocket, ~10 MB) or the full Mattermost web app (~300 MB) per server.
    static func mode(for id: UUID) -> ServerMode {
        ServerMode(rawValue: d.string(forKey: "mode.\(id.uuidString)") ?? "") ?? .native
    }
    static func setMode(_ mode: ServerMode, for id: UUID) {
        d.set(mode.rawValue, forKey: "mode.\(id.uuidString)")
        post()
    }

    static var lastActiveServerID: UUID? {
        get { d.string(forKey: "lastActiveServerID").flatMap(UUID.init(uuidString:)) }
        set { d.set(newValue?.uuidString, forKey: "lastActiveServerID") }
    }

    static var pageZoom: Double {
        get { d.object(forKey: "pageZoom") as? Double ?? 1.0 }
        set { d.set(newValue, forKey: "pageZoom"); post() }
    }

    private static func bool(_ key: String, _ def: Bool) -> Bool {
        d.object(forKey: key) as? Bool ?? def
    }

    private static func post() {
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

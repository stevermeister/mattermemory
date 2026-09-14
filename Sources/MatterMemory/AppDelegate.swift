import AppKit
import ServiceManagement
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static var shared: AppDelegate!
    private(set) var main: MainWindowController!
    private var prefs: PreferencesWindowController?
    private var statusBar: StatusBarController?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(delegate: self)
        main = MainWindowController()
        NotificationManager.shared.setup()
        NotificationManager.shared.onClick = { [weak self] serverID, webID, channelID, _ in
            guard let self else { return }
            self.main.showWindow()
            self.main.manager.activate(serverID)
            if let webID { self.main.manager.views[serverID]?.handleNotificationClick(id: webID) }
            if let channelID { self.main.manager.sessions[serverID]?.selectChannel(channelID) }
        }
        statusBar = StatusBarController()
        // A login item is launched in the background, so the app is not active yet; a launch
        // from Finder, Spotlight or the Dock already is. That is the difference between
        // "come up quietly at login" and "the user asked for the window".
        if NSApp.isActive || !Settings.startHidden {
            main.showWindow()
        }
        bootstrapFromEnvironment()
        if ServerStore.shared.servers.isEmpty { main.addServer() }
        if let path = ProcessInfo.processInfo.environment["MM_SNAPSHOT"] { installDebugSignals(snapshotPath: path) }
    }

    /// MATTERMOST_URL + MATTERMOST_ACCESS_TOKEN in the environment add that server
    /// (once) and log it in with the token. Handy for scripted setups and testing.
    private func bootstrapFromEnvironment() {
        let env = ProcessInfo.processInfo.environment
        guard !AppPaths.isDemo, let raw = env["MATTERMOST_URL"], let url = Server.normalize(raw) else { return }
        let token = env["MATTERMOST_ACCESS_TOKEN"]
        let server = ServerStore.shared.server(for: url) ?? {
            let s = Server(name: url.host ?? "Mattermost", url: url)
            ServerStore.shared.add(s)
            return s
        }()
        Task { @MainActor in
            // Only inject when there is no session yet; re-injecting would restart a working session.
            let hasSession = await ServerSession.cookieToken(for: server) != nil
            self.main.activate(server, token: hasSession ? nil : token, reload: !hasSession && token != nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        main.showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        main?.manager.activeView?.touch()
    }

    /// mattermost://chat.example.com/team/channels/town-square → https://…
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            if comps.scheme == "mattermost" { comps.scheme = "https" }
            guard let target = comps.url else { continue }
            main.showWindow()
            if let server = ServerStore.shared.server(for: target) {
                main.manager.activate(server.id)
                main.manager.views[server.id]?.navigate(to: target)
            } else {
                NSWorkspace.shared.open(target)
            }
        }
    }

    func updateDockBadge() {
        guard let m = main?.manager else { return }
        let label: String
        if m.totalMentions > 0 { label = "\(m.totalMentions)" }
        else if m.anyUnread && Settings.showUnreadBadge { label = "•" }
        else { label = "" }
        if NSApp.dockTile.badgeLabel != label { NSApp.dockTile.badgeLabel = label }
        statusBar?.update()
    }

    // MARK: Debug hooks (only when MM_SNAPSHOT is set)
    // SIGUSR1: write a window snapshot. SIGUSR2: evaluate "<MM_SNAPSHOT>.js" in the
    // active page and write the result to "<MM_SNAPSHOT>.out".
    private var debugSources: [DispatchSourceSignal] = []
    private func installDebugSignals(snapshotPath: String) {
        let handlers: [(Int32, () -> Void)] = [
            (SIGUSR1, { [weak self] in self?.main.debugSnapshot(to: snapshotPath) }),
            (SIGUSR2, { [weak self] in
                guard let self, let js = try? String(contentsOfFile: snapshotPath + ".js", encoding: .utf8) else { return }
                if js.hasPrefix("//native:") {
                    // Drive the memory policy from a script: unload / reload / switch, then report.
                    let cmd = js.dropFirst(9).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
                    let before = MemoryStats.snapshot()
                    switch cmd.first {
                    case "unloadCurrent": self.main.manager.activeView?.unload()
                    case "unloadInactive": self.main.manager.unloadInactive()
                    case "reloadCurrent": self.main.manager.activeView?.reload()
                    case "activate": self.main.manager.activate(index: Int(cmd.dropFirst().first ?? "0") ?? 0)
                    case "tick": self.main.manager.debugTick()
                    case "state":
                        let text = self.main.manager.sessions.values.map { s in
                            "\(s.server.name): state=\(s.state) connected=\(s.connected) teams=\(s.teams.count) channels=\(s.channels.count) categories=\(s.categories.map { "\($0.displayName):\($0.channelIds.count)" }) current=\(s.currentChannelID.flatMap { s.channels[$0] }.map { s.title(for: $0) } ?? "-") thread=\(s.openThreadID ?? "-") search=\(s.searchResults?.count ?? -1) posts=\(s.currentChannelID.flatMap { s.posts[$0]?.order.count } ?? 0) users=\(s.users.count) mentions=\(s.totalMentions) unread=\(s.anyUnread) crt=\(s.crt) err=\(s.lastError ?? "-")"
                        }.joined(separator: "\n")
                        try? text.write(toFile: snapshotPath + ".out", atomically: true, encoding: .utf8)
                        return
                    case "send":
                        if let s = self.main.manager.activeSession {
                            let text = cmd.dropFirst().joined(separator: " ")
                            Task { await s.send(message: text) }
                        }
                    case "reply":
                        if let s = self.main.manager.activeSession, let rid = s.openThreadID {
                            let text = cmd.dropFirst().joined(separator: " ")
                            Task { await s.send(message: text, rootID: rid); NSLog("reply done err=\(s.lastError ?? "-") thread=\(s.threads[rid]?.count ?? -1)") }
                        }
                    case "openthread":
                        if let s = self.main.manager.activeSession, let rid = cmd.dropFirst().first { s.openThread(rootID: String(rid)) }
                    case "dump":
                        NotificationCenter.default.post(name: NativeCommands.debugDump, object: snapshotPath + ".out")
                        return
                    case "click":
                        if let window = self.main.window, cmd.count >= 3, let x = Double(cmd[1]), let y = Double(cmd[2]) {
                            for (type, clicks) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 1)] {
                                if let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) {
                                    NSApp.sendEvent(e)
                                }
                            }
                        }
                    case "windows":
                        let titles = NSApp.windows.filter(\.isVisible).map(\.title)
                        try? "visible windows: \(titles)".write(toFile: snapshotPath + ".out", atomically: true, encoding: .utf8)
                        return
                    case "loginitem":
                        let arg = cmd.dropFirst().first.map(String.init) ?? "status"
                        var text = ""
                        if arg == "on" || arg == "off" { text = LoginItem.set(arg == "on") ?? "ok" }
                        text += " | status=\(SMAppService.mainApp.status.rawValue) enabled=\(LoginItem.isEnabled) needsApproval=\(LoginItem.needsApproval) path=\(Bundle.main.bundlePath)"
                        try? text.write(toFile: snapshotPath + ".out", atomically: true, encoding: .utf8)
                        return
                    case "focus":
                        let fr = self.main.window?.firstResponder
                        let text = "firstResponder=\(fr.map { String(describing: type(of: $0)) } ?? "nil") key=\(self.main.window?.isKeyWindow ?? false) active=\(NSApp.isActive)"
                        try? text.write(toFile: snapshotPath + ".out", atomically: true, encoding: .utf8)
                        return
                    case "type":
                        let text = cmd.dropFirst().joined(separator: " ")
                        for ch in text { self.debugKey(String(ch), code: 0, flags: []) }
                    case "key":
                        switch cmd.dropFirst().first.map(String.init) ?? "" {
                        case "return": self.debugKey("\r", code: 36, flags: [])
                        case "shiftreturn": self.debugKey("\r", code: 36, flags: [.shift])
                        case "escape": self.debugKey("\u{1B}", code: 53, flags: [])
                        case "down": self.debugKey("", code: 125, flags: [])
                        case "altdown": self.debugKey("", code: 125, flags: [.option])
                        case "altup": self.debugKey("", code: 126, flags: [.option])
                        case "altshiftdown": self.debugKey("", code: 125, flags: [.option, .shift])
                        case "cmdk": self.debugKey("k", code: 40, flags: [.command])
                        case "cmdf": self.debugKey("f", code: 3, flags: [.command])
                        default: break
                        }
                    case "thread":
                        if let s = self.main.manager.activeSession, let cid = s.currentChannelID,
                           let root = s.posts[cid]?.chronological.last(where: { ($0.replyCount ?? 0) > 0 }) { s.openThread(rootID: root.id) }
                    case "closethread": self.main.manager.activeSession?.openThreadID = nil
                    case "switcher": if let id = self.main.manager.activeServerID { NotificationCenter.default.post(name: NativeCommands.switcher, object: id) }
                    case "search":
                        if let s = self.main.manager.activeSession { Task { await s.search(cmd.dropFirst().joined(separator: " ")) } }
                    case "select":
                        if let name = cmd.dropFirst().first, let s = self.main.manager.activeSession,
                           let ch = s.channels.values.first(where: { $0.name == name || s.title(for: $0).lowercased() == name.lowercased() }) { s.selectChannel(ch.id) }
                    case "cookies":
                        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                            let text = cookies.map { "\($0.name)@\($0.domain) secure=\($0.isSecure) httpOnly=\($0.isHTTPOnly)" }.joined(separator: "\n")
                            try? text.write(toFile: snapshotPath + ".out", atomically: true, encoding: .utf8)
                        }
                        return
                    case "addServer":
                        if let u = cmd.dropFirst().first.flatMap({ Server.normalize(String($0)) }), ServerStore.shared.server(for: u) == nil {
                            ServerStore.shared.add(Server(name: u.host ?? "x", url: u))
                        }
                    default: break
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        let after = MemoryStats.snapshot()
                        let loaded = self.main.manager.orderedViews.map { "\($0.server.name):\($0.isLoaded ? "loaded" : "unloaded") mentions=\($0.mentionCount) unread=\($0.hasUnread)" }
                        let procs = after.details.map { "\($0.name)#\($0.pid)=\(MemoryStats.format($0.bytes))" }.joined(separator: " ")
                        let active = self.main.manager.activeView?.server.name ?? "none"
                        let text = "before=\(MemoryStats.format(before.total)) (\(before.helperCount) helpers) after=\(MemoryStats.format(after.total)) (\(after.helperCount) helpers) active=\(active) views=\(loaded)\nprocs: app=\(MemoryStats.format(after.own)) \(procs)\n\(self.main.debugReadoutState)"
                        try? text.write(toFile: snapshotPath + ".out", atomically: true, encoding: .utf8)
                    }
                    return
                }
                guard let wv = self.main.manager.activeView?.webView else { return }
                wv.evaluateJavaScript(js) { result, error in
                    var text = error.map { "ERROR: \($0)" } ?? String(describing: result ?? "null")
                    if let w = self.main.window {
                        text += "\nwindow: visible=\(w.isVisible) key=\(w.isKeyWindow) occlusion=\(w.occlusionState.rawValue) frame=\(w.frame) screen=\(w.screen?.frame ?? .zero) wvFrame=\(wv.frame) wvWindow=\(wv.window != nil) appActive=\(NSApp.isActive) appHidden=\(NSApp.isHidden) mini=\(w.isMiniaturized) activeSpace=\(w.isOnActiveSpace) displayAsleep=\(CGDisplayIsAsleep(CGMainDisplayID()) != 0) screens=\(NSScreen.screens.count) hiddenAncestor=\(wv.isHiddenOrHasHiddenAncestor)"
                    }
                    NotificationManager.shared.debugStatus { text += "\n" + $0
                        try? text.write(toFile: snapshotPath + ".out", atomically: true, encoding: .utf8) }
                }
            }),
        ]
        for (sig, handler) in handlers {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler(handler: handler)
            src.resume()
            debugSources.append(src)
        }
    }

    /// Synthesises a key press through NSApp.sendEvent so it takes the normal responder path.
    private func debugKey(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags) {
        guard let window = main.window else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                        isARepeat: false, keyCode: code) {
                NSApp.sendEvent(e)
            }
        }
    }

    // MARK: Menu actions

    @objc func showMainWindow(_ sender: Any?) { main.showWindow() }
    @objc func logOutCurrent(_ sender: Any?) {
        guard let id = main.manager.activeServerID, let s = main.manager.sessions[id] else { return }
        let a = NSAlert()
        a.messageText = "Log out of \(s.server.name)?"
        a.informativeText = "Clears the session cookie for this server. You can log in again with password, SSO (web view) or a token."
        a.addButton(withTitle: "Log Out")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        s.logout()
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for c in cookies where s.server.host.hasSuffix(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()) {
                WKWebsiteDataStore.default().httpCookieStore.delete(c)
            }
        }
    }
    @objc func openServerFromMenu(_ sender: NSMenuItem) {
        main.showWindow()
        main.manager.activate(index: sender.tag)
    }
    @objc func showPreferences(_ sender: Any?) {
        if prefs == nil { prefs = PreferencesWindowController(main: main) }
        prefs?.showWindow(nil)
        prefs?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func addServer(_ sender: Any?) { main.showWindow(); main.addServer() }
    @objc func reload(_ sender: Any?) { main.manager.activeView?.reload() }
    @objc func reloadIgnoringCache(_ sender: Any?) { main.manager.activeView?.reload(ignoringCache: true) }
    @objc func goBack(_ sender: Any?) { main.manager.activeView?.goBack() }
    @objc func goForward(_ sender: Any?) { main.manager.activeView?.goForward() }
    @objc func nextServer(_ sender: Any?) { main.manager.activateAdjacent(1) }
    @objc func previousServer(_ sender: Any?) { main.manager.activateAdjacent(-1) }
    @objc func selectServer(_ sender: NSMenuItem) { main.manager.activate(index: sender.tag) }
    @objc func unloadInactive(_ sender: Any?) { main.manager.unloadInactive() }
    @objc func toggleWebView(_ sender: Any?) {
        guard let id = main.manager.activeServerID else { return }
        main.manager.setMode(Settings.mode(for: id) == .native ? .web : .native, for: id)
    }
    @objc func findChannel(_ sender: Any?) {
        guard let id = main.manager.activeServerID, Settings.mode(for: id) == .native else { return }
        NotificationCenter.default.post(name: NativeCommands.switcher, object: id)
    }
    @objc func unloadCurrent(_ sender: Any?) { main.manager.activeView?.unload() }
    @objc func zoomIn(_ sender: Any?) { Settings.pageZoom = min(3, Settings.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { Settings.pageZoom = max(0.5, Settings.pageZoom - 0.1) }
    @objc func zoomReset(_ sender: Any?) { Settings.pageZoom = 1 }
    @objc func showShortcuts(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = "Keyboard Shortcuts"
        a.informativeText = """
        ⌘K  Find channel or person       ⌘F  Search messages
        ⌥↑ / ⌥↓  Previous / next channel   ⌥⇧↑ / ⌥⇧↓  Previous / next unread
        Esc  Close thread, search or finder; cancel edit
        ↩  Send   ⇧↩  New line   ↑ (empty box)  Edit your last message
        +:emoji:  React to the last message   /command  Run a slash command
        ⌘1…⌘9  Switch server   ⌃Tab / ⌃⇧Tab  Next / previous server
        ⌘⇧W  Toggle web view   ⌘N  Add server   ⌘,  Preferences
        ⌘+ / ⌘- / ⌘0  Zoom (web view)   ⌘R  Reload (web view)
        """
        a.addButton(withTitle: "OK")
        a.runModal()
    }
    @objc func openProjectPage(_ sender: Any?) { NSWorkspace.shared.open(URL(string: "https://github.com/mattermost/desktop")!) }
    @objc func copyCurrentURL(_ sender: Any?) {
        guard let url = main.manager.activeView?.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)): return main.manager.activeView?.canGoBack ?? false
        case #selector(goForward(_:)): return main.manager.activeView?.canGoForward ?? false
        case #selector(reload(_:)), #selector(reloadIgnoringCache(_:)), #selector(copyCurrentURL(_:)), #selector(unloadCurrent(_:)):
            return main.manager.activeView != nil
        case #selector(toggleWebView(_:)):
            if let id = main.manager.activeServerID {
                item.title = Settings.mode(for: id) == .native ? "Open in Web View" : "Back to Native View"
                return true
            }
            return false
        case #selector(findChannel(_:)):
            return main.manager.activeServerID.map { Settings.mode(for: $0) == .native } ?? false
        default: return true
        }
    }
}

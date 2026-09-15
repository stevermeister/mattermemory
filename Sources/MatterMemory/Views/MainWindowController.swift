import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let manager = WebViewManager()
    private let tabBar = ServerTabBar()
    private let emptyState = EmptyStateView()
    private var memoryTimer: Timer?
    private var keyMonitor: Any?
    private var tabBarHeight: NSLayoutConstraint!

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "MatterMemory"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 640, height: 400)
        window.backgroundColor = Theme.bar
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("MainWindow")
        if !window.setFrameUsingName("MainWindow") { window.center() }
        super.init(window: window)
        window.delegate = self

        let content = NSView()
        content.wantsLayer = true
        window.contentView = content

        let container = manager.containerView
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabBar)
        content.addSubview(container)
        tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: Theme.barHeight)
        NSLayoutConstraint.activate([
            tabBarHeight,
            tabBar.topAnchor.constraint(equalTo: content.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        emptyState.autoresizingMask = [.width, .height]
        emptyState.onAdd = { [weak self] in self?.addServer() }

        tabBar.onSelect = { [weak self] id in self?.manager.activate(id) }
        tabBar.onAdd = { [weak self] in self?.addServer() }
        tabBar.onBack = { [weak self] in self?.manager.activeView?.goBack() }
        tabBar.onForward = { [weak self] in self?.manager.activeView?.goForward() }
        tabBar.onTabMenu = { [weak self] id, event in self?.showTabMenu(for: id, event: event) }

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: WebViewManager.stateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: ServerStore.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Settings.changed, object: nil)
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.updateMemory() }
        // ⌘K / ⌘F for the native view only; in web mode the page owns those shortcuts.
        // Matched on the Latin letter of the key, so they work on non-Latin layouts too.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let id = self.manager.activeServerID, Settings.mode(for: id) == .native else { return event }
            switch event.shortcutCharacter {
            case "k": NotificationCenter.default.post(name: NativeCommands.switcher, object: id); return nil
            case "f": NotificationCenter.default.post(name: NativeCommands.search, object: id); return nil
            default: return event
            }
        }
        // Option+↑/↓: previous/next channel; Option+Shift+↑/↓: previous/next unread (as in the web app).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, let id = self.manager.activeServerID, Settings.mode(for: id) == .native else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Esc leaves the Threads list (there is no composer there to route it through).
            if event.keyCode == 53, mods.isEmpty, let s = self.manager.sessions[id], s.showingThreads, s.openThreadID == nil {
                s.closeThreads()
                NotificationCenter.default.post(name: NativeCommands.focusComposer, object: id)
                return nil
            }
            guard mods == [.option] || mods == [.option, .shift], event.keyCode == 125 || event.keyCode == 126 else { return event }
            let step = ChannelStep(serverID: id, delta: event.keyCode == 125 ? 1 : -1, unreadOnly: mods.contains(.shift))
            NotificationCenter.default.post(name: NativeCommands.channelStep, object: step)
            return nil
        }
        refresh()
        updateMemory()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: State → UI

    @objc func refresh() {
        let servers = ServerStore.shared.servers
        let items = servers.map { s -> TabItem in
            let v = manager.views[s.id]
            return TabItem(id: s.id, name: s.name,
                           mentions: v?.mentionCount ?? 0, unread: v?.hasUnread ?? false,
                           loading: v?.isLoading ?? false, loaded: v?.isLoaded ?? false,
                           active: s.id == manager.activeServerID)
        }
        tabBar.update(items: items)
        // One server in native view needs no server bar: the sidebar header already names it.
        let showBar = servers.count != 1 || Settings.alwaysShowServerBar
            || (manager.activeServerID.map { !manager.isNative($0) } ?? false)
        if tabBar.isHidden == showBar {
            tabBar.isHidden = !showBar
            tabBarHeight.constant = showBar ? Theme.barHeight : 0
            ChromeState.shared.tabBarVisible = showBar
        }
        let active = manager.activeView
        tabBar.setHistory(canGoBack: active?.canGoBack ?? false, canGoForward: active?.canGoForward ?? false)
        if servers.isEmpty {
            if emptyState.superview == nil {
                emptyState.frame = manager.containerView.bounds
                manager.containerView.addSubview(emptyState)
            }
        } else {
            emptyState.removeFromSuperview()
        }
        window?.title = active.map { "\($0.server.name) — MatterMemory" } ?? "MatterMemory"
        AppDelegate.shared.updateDockBadge()
    }

    private func updateMemory() {
        guard Settings.showMemoryReadout else { tabBar.setMemoryText(""); return }
        guard window?.isVisible == true else { return }          // nothing to show, keep the old text
        let s = MemoryStats.snapshot()
        tabBar.setMemoryText(MemoryStats.format(s.total))
    }

    var debugReadoutState: String { "readout='\(tabBar.memoryText)' hidden=\(tabBar.memoryHidden) timer=\(memoryTimer?.isValid ?? false)" }

    // MARK: Server actions

    func addServer() {
        ServerEditor.present(on: window, existing: nil) { [weak self] server, token in
            guard let server else { return }
            ServerStore.shared.add(server)
            self?.activate(server, token: token)
        }
    }

    /// Activates a server, first injecting a token session if one was supplied.
    func activate(_ server: Server, token: String?, reload: Bool = false) {
        let native = Settings.mode(for: server.id) == .native
        let go = { [weak self] in
            guard let self else { return }
            self.manager.activate(server.id)
            if native {
                if let s = self.manager.sessions[server.id], token != nil { s.logout(); s.start() }
            } else if reload {
                self.manager.views[server.id]?.navigate(to: server.url)
            }
        }
        if let token {
            // Tear down any in-flight page first: an unauthenticated load would answer
            // its 401 with a logout call that clears the cookie we are about to set.
            manager.views[server.id]?.unload()
            SessionInjector.inject(token: token, for: server, completion: go)
        } else {
            go()
        }
    }

    func editServer(id: UUID) {
        guard let s = ServerStore.shared.server(id: id) else { return }
        ServerEditor.present(on: window, existing: s) { [weak self] updated, token in
            guard let updated else { return }
            ServerStore.shared.update(updated)
            if token != nil { self?.activate(updated, token: token, reload: true) }
        }
    }

    func removeServer(id: UUID) {
        guard let s = ServerStore.shared.server(id: id), let window else { return }
        let a = NSAlert()
        a.messageText = "Remove \(s.name)?"
        a.informativeText = "The server is removed from the list. Your login cookies stay in WebKit's storage until you clear website data."
        a.addButton(withTitle: "Remove")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        a.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn { ServerStore.shared.remove(id: id) }
        }
    }

    private func showTabMenu(for id: UUID, event: NSEvent) {
        guard let v = manager.views[id] else { return }
        let menu = NSMenu()
        func item(_ title: String, _ handler: @escaping () -> Void) {
            menu.addItem(MenuAction(title: title, handler: handler))
        }
        let native = Settings.mode(for: id) == .native
        item(native ? "Open in Web View" : "Back to Native View") { [weak self] in self?.manager.setMode(native ? .web : .native, for: id) }
        menu.addItem(.separator())
        if native {
            item("Reconnect") { [weak self] in self?.manager.sessions[id]?.logout(); self?.manager.sessions[id]?.start() }
        } else {
            item("Reload") { v.reload() }
            if v.isLoaded { item("Unload (free memory)") { v.unload() } } else { item("Load") { v.ensureLoaded() } }
        }
        menu.addItem(.separator())
        item("Edit Server…") { [weak self] in self?.editServer(id: id) }
        item("Move Left") { ServerStore.shared.move(id: id, by: -1) }
        item("Move Right") { ServerStore.shared.move(id: id, by: 1) }
        menu.addItem(.separator())
        item("Remove Server…") { [weak self] in self?.removeServer(id: id) }
        NSMenu.popUpContextMenu(menu, with: event, for: tabBar)
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Like the Electron app: closing hides; the app keeps running in the dock.
        sender.orderOut(nil)
        manager.windowHiddenSince = Date()
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) { manager.windowHiddenSince = Date() }
    func windowDidDeminiaturize(_ notification: Notification) { manager.windowHiddenSince = nil }

    func windowDidResignKey(_ notification: Notification) { manager.foregroundChanged() }

    func windowDidBecomeKey(_ notification: Notification) {
        manager.windowHiddenSince = nil
        manager.foregroundChanged()
        manager.activeView?.touch()
        if let wv = manager.activeView?.webView { window?.makeFirstResponder(wv) }
        updateMemory()
    }

    /// Debug aid (MM_SNAPSHOT=/path.png): composites the AppKit chrome and the
    /// out-of-process web content into one PNG without needing screen-recording rights.
    func debugSnapshot(to path: String) {
        guard let window, let content = window.contentView else { return }
        let bounds = content.bounds
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        content.cacheDisplay(in: bounds, to: rep)
        let chrome = NSImage(size: bounds.size)
        chrome.addRepresentation(rep)
        let write: (NSImage?) -> Void = { web in
            let final = NSImage(size: bounds.size)
            final.lockFocus()
            chrome.draw(in: NSRect(origin: .zero, size: bounds.size))
            if let web, let wv = self.manager.activeView?.webView {
                web.draw(in: wv.convert(wv.bounds, to: content))
            }
            final.unlockFocus()
            if let tiff = final.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
        }
        if let wv = manager.activeView?.webView { wv.takeSnapshot(with: nil) { img, _ in write(img) } } else { write(nil) }
    }

    func showWindow() {
        manager.windowHiddenSince = nil
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// NSMenuItem with a closure instead of a target/selector.
final class MenuAction: NSMenuItem {
    private let handler: () -> Void
    init(title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

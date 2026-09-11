import AppKit
import SwiftUI
import WebKit

/// Owns one ServerWebView per configured server, decides which one is on
/// screen, and enforces the memory policy (idle unload, pressure unload,
/// background polling for unloaded servers).
@MainActor
final class WebViewManager: NSObject {
    static let stateChanged = Notification.Name("MatterMemory.WebViewStateChanged")

    private(set) var views: [UUID: ServerWebView] = [:]
    private(set) var sessions: [UUID: ServerSession] = [:]
    private var hostingViews: [UUID: NSHostingView<NativeRootView>] = [:]
    private(set) var activeServerID: UUID?
    /// Servers sent to the web view for an SSO login; they flip back to native once a session cookie shows up.
    private var awaitingWebLogin: Set<UUID> = []
    private var loginWatch: Timer?
    let containerView = NSView()
    private var tickTimer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private let poller = UnreadPoller()
    private var lastPolledMentions: [UUID: Int] = [:]
    /// Set by the window controller while the main window is closed or minimised.
    var windowHiddenSince: Date? {
        didSet {
            guard windowHiddenSince == nil, oldValue != nil, let id = activeServerID, !isNative(id) else { return }
            activeView?.ensureLoaded()
        }
    }

    override init() {
        super.init()
        containerView.wantsLayer = true
        syncWithStore()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: ServerStore.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.changed, object: nil)
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        tickTimer?.tolerance = 10

        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            guard Settings.unloadOnMemoryPressure else { return }
            NSLog("Memory pressure: unloading inactive servers")
            MainActor.assumeIsolated { self?.unloadInactive() }
        }
        src.resume()
        pressureSource = src
    }

    var activeView: ServerWebView? { activeServerID.flatMap { views[$0] } }
    var activeSession: ServerSession? { activeServerID.flatMap { sessions[$0] } }
    func isNative(_ id: UUID) -> Bool { Settings.mode(for: id) == .native }

    func mentions(for id: UUID) -> Int { isNative(id) ? (sessions[id]?.totalMentions ?? 0) : (views[id]?.mentionCount ?? 0) }
    func unread(for id: UUID) -> Bool { isNative(id) ? (sessions[id]?.anyUnread ?? false) : (views[id]?.hasUnread ?? false) }
    func isLoading(_ id: UUID) -> Bool { isNative(id) ? (sessions[id]?.state == .loading) : (views[id]?.isLoading ?? false) }
    func isLoaded(_ id: UUID) -> Bool { isNative(id) ? (sessions[id]?.state == .ready) : (views[id]?.isLoaded ?? false) }
    var orderedViews: [ServerWebView] { ServerStore.shared.servers.compactMap { views[$0.id] } }
    var totalMentions: Int { ServerStore.shared.servers.reduce(0) { $0 + mentions(for: $1.id) } }
    var anyUnread: Bool { ServerStore.shared.servers.contains { unread(for: $0.id) } }

    // MARK: Activation

    func activate(_ id: UUID?) {
        guard id != activeServerID || (id.flatMap { views[$0]?.containerView.superview } == nil) else { return }
        if let old = activeView {
            old.touch()
            old.containerView.removeFromSuperview()
        }
        if let oldID = activeServerID { hostingViews[oldID]?.removeFromSuperview() }
        activeServerID = id
        Settings.lastActiveServerID = id
        if let id { showContent(for: id) }
        broadcast()
    }

    private func showContent(for id: UUID) {
        guard let view = views[id] else { return }
        if isNative(id) {
            let session = self.session(for: view.server)
            let host = hostingViews[id] ?? {
                let h = NSHostingView(rootView: NativeRootView(session: session, onOpenWebView: { [weak self] in
                    self?.awaitingWebLogin.insert(id)
                    self?.setMode(.web, for: id)
                }))
                hostingViews[id] = h
                return h
            }()
            host.frame = containerView.bounds
            host.autoresizingMask = [.width, .height]
            containerView.addSubview(host)
            session.start()
            if view.isLoaded { view.unload() }                  // native mode never keeps a page around
            DispatchQueue.main.async { NotificationCenter.default.post(name: NativeCommands.focusComposer, object: id) }
        } else {
            view.containerView.frame = containerView.bounds
            containerView.addSubview(view.containerView)
            view.ensureLoaded()
            view.touch()
            lastPolledMentions[id] = nil
            if let wv = view.webView { containerView.window?.makeFirstResponder(wv) }
        }
    }

    func setMode(_ mode: Settings.ServerMode, for id: UUID) {
        guard Settings.mode(for: id) != mode else { return }
        Settings.setMode(mode, for: id)
        if mode == .native { awaitingWebLogin.remove(id) }
        if id == activeServerID {
            views[id]?.containerView.removeFromSuperview()
            hostingViews[id]?.removeFromSuperview()
            showContent(for: id)
        } else if mode == .native {
            views[id]?.unload()
        }
        if mode == .web { startLoginWatch() }
        broadcast()
    }

    /// While a server is in the web view to log in, look for the session cookie and flip back to native.
    private func startLoginWatch() {
        guard loginWatch == nil else { return }
        loginWatch = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in MainActor.assumeIsolated {
            guard let self else { t.invalidate(); return }
            guard !self.awaitingWebLogin.isEmpty else { t.invalidate(); self.loginWatch = nil; return }
            for id in self.awaitingWebLogin {
                guard let view = self.views[id] else { self.awaitingWebLogin.remove(id); continue }
                Task { @MainActor in
                    if await ServerSession.cookieToken(for: view.server) != nil, self.awaitingWebLogin.contains(id) {
                        self.awaitingWebLogin.remove(id)
                        self.sessions[id]?.logout()
                        self.setMode(.native, for: id)
                    }
                }
            }
        } }
    }

    private func session(for server: Server) -> ServerSession {
        if let s = sessions[server.id] { return s }
        let s = ServerSession(server: server)
        let id = server.id
        s.onBadgeChange = { [weak self] in self?.broadcast() }
        s.isForeground = { [weak self] in
            guard let self else { return false }
            return self.activeServerID == id && (self.containerView.window?.isKeyWindow ?? false) && NSApp.isActive
        }
        s.onNotification = { title, body, channelID, postID in
            NotificationManager.shared.post(serverID: id, webID: nil, title: title, body: body, silent: false, channelID: channelID, postID: postID)
        }
        sessions[id] = s
        return s
    }

    func foregroundChanged() {
        for s in sessions.values { s.foregroundChanged() }
        broadcast()
    }

    func activateAdjacent(_ delta: Int) {
        let servers = ServerStore.shared.servers
        guard !servers.isEmpty else { return }
        let i = activeServerID.flatMap { id in servers.firstIndex { $0.id == id } } ?? 0
        activate(servers[(i + delta + servers.count) % servers.count].id)
    }

    func activate(index: Int) {
        let servers = ServerStore.shared.servers
        guard index >= 0, index < servers.count else { return }
        activate(servers[index].id)
    }

    // MARK: Memory policy

    func unloadInactive(idleMinutes: Int = 0) {
        let cutoff = Date().addingTimeInterval(-Double(idleMinutes) * 60)
        for v in views.values where v.server.id != activeServerID && v.isLoaded && v.lastActivity < cutoff {
            v.unload()
        }
        broadcast()
    }

    func debugTick() { tick() }

    private func tick() {
        let idle = Settings.idleUnloadMinutes
        if idle > 0 { unloadInactive(idleMinutes: idle) }
        let hidden = Settings.hiddenUnloadMinutes
        if hidden > 0, let since = windowHiddenSince, Date().timeIntervalSince(since) > Double(hidden) * 60 {
            for v in views.values where v.isLoaded { v.unload() }
            if let id = activeServerID, !isNative(id) { awaitingWebLogin.remove(id) }
            broadcast()
        }
        guard Settings.backgroundUnreadPolling else { return }
        for v in views.values where !v.isLoaded && !isNative(v.server.id) {
            let server = v.server
            poller.poll(server) { [weak self] counts in MainActor.assumeIsolated {
                guard let self, let counts, let view = self.views[server.id], !view.isLoaded else { return }
                let previous = self.lastPolledMentions[server.id]
                view.setBackgroundCounts(mentions: counts.mentions, unread: counts.unread)
                if let previous, counts.mentions > previous, Settings.notificationsEnabled {
                    NotificationManager.shared.post(serverID: server.id, webID: nil,
                                                    title: server.name,
                                                    body: "You have \(counts.mentions) unread mention\(counts.mentions == 1 ? "" : "s")",
                                                    silent: false)
                }
                self.lastPolledMentions[server.id] = counts.mentions
            } }
        }
    }

    // MARK: Store sync

    @objc private func storeChanged() {
        syncWithStore()
        broadcast()
    }

    private func syncWithStore() {
        let servers = ServerStore.shared.servers
        let ids = Set(servers.map(\.id))
        for (id, v) in views where !ids.contains(id) {
            v.unload()
            v.containerView.removeFromSuperview()
            views[id] = nil
        }
        for s in servers {
            if let v = views[s.id] { v.update(server: s) } else {
                let v = ServerWebView(server: s)
                v.delegate = self
                views[s.id] = v
            }
            if isNative(s.id) { session(for: s).start() }     // websocket per server: real-time badges without a page
        }
        for (id, sess) in sessions where !ids.contains(id) {
            sess.stop()
            sessions[id] = nil
            hostingViews[id]?.removeFromSuperview()
            hostingViews[id] = nil
        }
        if let active = activeServerID, !ids.contains(active) {
            activeServerID = nil
            activate(servers.first?.id)
        } else if activeServerID == nil, let first = servers.first {
            activate(Settings.lastActiveServerID.flatMap { ids.contains($0) ? $0 : nil } ?? first.id)
        }
    }

    @objc private func settingsChanged() {
        for v in views.values {
            v.setZoom(Settings.pageZoom)
            v.setInspectable(Settings.webInspectorEnabled)
            if v.isLoaded, v.appliedLowMemoryMode != Settings.lowMemoryMode {
                v.unload()                                   // lockdown is fixed at creation
                if v.server.id == activeServerID { v.ensureLoaded() }
            }
        }
    }

    private func broadcast() {
        NotificationCenter.default.post(name: Self.stateChanged, object: self)
    }
}

extension WebViewManager: ServerWebViewDelegate {
    func serverWebViewStateChanged(_ view: ServerWebView) { broadcast() }

    func serverWebView(_ view: ServerWebView, requestNotification id: Int, title: String, body: String, silent: Bool) {
        guard Settings.notificationsEnabled else { return }
        NotificationManager.shared.post(serverID: view.server.id, webID: id, title: title, body: body, silent: silent)
    }

    func serverWebView(_ view: ServerWebView, didFinishDownload url: URL) {
        NSApp.dockTile.display()
        NSApp.requestUserAttention(.informationalRequest)
        NotificationManager.shared.post(serverID: view.server.id, webID: nil,
                                        title: "Download complete", body: url.lastPathComponent,
                                        silent: true, fileURL: url)
    }
}

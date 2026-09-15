import AppKit
import WebKit

struct ChannelPosts {
    var order: [String] = []            // newest first, as the API returns it
    var byID: [String: MMPost] = [:]
    var hasMore = true
    var loading = false
    var loaded = false

    var chronological: [MMPost] { order.reversed().compactMap { byID[$0] } }
}

/// Everything the native UI needs for one server: REST bootstrap, websocket
/// updates, unread bookkeeping, notifications. Lives as long as the app; costs
/// a few MB instead of a WebContent process.
@MainActor
final class ServerSession: ObservableObject {
    enum State: Equatable {
        case idle, loading, needsLogin(String?), ready, error(String)
    }

    let server: Server
    @Published private(set) var state: State = .idle
    @Published private(set) var me: MMUser?
    @Published private(set) var config = MMClientConfig(dict: [:])
    @Published private(set) var teams: [MMTeam] = []
    @Published var currentTeamID: String?
    @Published private(set) var channels: [String: MMChannel] = [:]
    @Published private(set) var members: [String: MMChannelMember] = [:]
    @Published private(set) var categories: [MMSidebarCategory] = []
    @Published private(set) var users: [String: MMUser] = [:]
    @Published private(set) var statuses: [String: String] = [:]
    @Published private(set) var currentChannelID: String?
    @Published private(set) var posts: [String: ChannelPosts] = [:]
    @Published private(set) var threads: [String: [MMPost]] = [:]     // root id → root + replies, chronological
    @Published var openThreadID: String?
    @Published private(set) var typing: [String: [String: Date]] = [:]
    @Published private(set) var connected = false
    @Published private(set) var threadMentions = 0
    @Published private(set) var threadUnread = false
    @Published private(set) var unreadThreadCount = 0
    @Published private(set) var userThreads: [MMUserThread] = []       // the "Threads" view, unread first
    @Published private(set) var threadsLoading = false
    @Published private(set) var showingThreads = false                 // centre pane shows the threads list
    @Published var threadsUnreadOnly = false
    @Published private(set) var customEmoji: [String: String] = [:]   // name → id
    @Published var searchResults: [MMPost]?
    @Published var searchTerms = ""
    @Published private(set) var searching = false
    @Published var lastError: String? { didSet { if let e = lastError { NSLog("MatterMemory[\(server.name)] error: \(e)") } } }

    private(set) var crt = false
    let images: ImageCache
    private(set) var client: MMClient
    private var ws: MMWebSocket?
    private var token: String?
    private var viewDebounce: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastPostAt: [String: Int64] = [:]
    private var retryTask: Task<Void, Never>?
    private var retryDelay: TimeInterval = 5
    private var threadsRefreshTask: Task<Void, Never>?

    /// Fired whenever mention/unread totals may have changed (tab bar, dock badge).
    var onBadgeChange: (() -> Void)?
    /// (title, body, channelID, postID)
    var onNotification: ((String, String, String, String) -> Void)?
    /// Whether the app window is key and this server is the one on screen.
    var isForeground: () -> Bool = { false }

    init(server: Server) {
        self.server = server
        client = MMClient(baseURL: server.url, token: nil)
        images = ImageCache(client: client)
    }

    // MARK: Session lifecycle

    /// Fills the session with fabricated content for MM_DEMO=1. No network, no persistence.
    func startDemo() {
        guard state != .ready else { return }
        me = DemoData.users.first { $0.id == "u-me" }
        config = MMClientConfig(dict: ["SiteName": DemoData.serverName, "TeammateNameDisplay": "full_name", "CollapsedThreads": "always_on"])
        displayFormat = "full_name"
        crt = true
        teams = [MMTeam(id: DemoData.teamID, name: "acme", displayName: DemoData.serverName)]
        currentTeamID = DemoData.teamID
        for u in DemoData.users { users[u.id] = u }
        statuses = DemoData.statuses
        for c in DemoData.channels {
            channels[c.id] = c
            let (unread, mentions) = DemoData.unread[c.id] ?? (0, 0)
            members[c.id] = MMChannelMember(channelId: c.id, userId: me?.id ?? "", msgCount: 40 - unread,
                                            msgCountRoot: 40 - unread, mentionCount: mentions, mentionCountRoot: mentions,
                                            lastViewedAt: 0, notifyProps: nil)
        }
        var general = ChannelPosts()
        let list = DemoData.posts(in: "c-general")
        general.order = list.map(\.id).reversed()
        general.byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        general.hasMore = false
        general.loaded = true
        posts["c-general"] = general
        currentChannelID = "c-general"
        threadUnread = true
        threadMentions = 1
        unreadThreadCount = 1
        connected = true
        state = .ready
        onBadgeChange?()
    }

    /// Resumes the saved session: the token kept in the keychain (survives a
    /// WebKit cookie-jar reset, which is what used to send SSO users back to the
    /// login form), falling back to the cookie the web view left behind.
    func start() {
        if AppPaths.isDemo { startDemo(); return }
        guard state == .idle || state == .needsLogin(nil) || isError else { return }
        retryTask?.cancel()
        state = .loading
        Task {
            var candidates: [String] = []
            if let saved = Keychain.get(tokenAccount) { candidates.append(saved) }
            if let cookie = await Self.cookieToken(for: server), !candidates.contains(cookie) { candidates.append(cookie) }
            guard let first = candidates.first else { state = .needsLogin(nil); return }
            await bootstrap(token: first, fallbacks: Array(candidates.dropFirst()))
        }
    }

    var isError: Bool { if case .error = state { return true }; return false }

    /// Keychain account for this server's session token.
    private var tokenAccount: String { "session-token.\(server.id.uuidString)" }

    /// Keeps the token where both halves of the app expect it: the keychain for
    /// the next launch, WebKit's cookie jar for the web view.
    private func persist(token: String) {
        guard !AppPaths.isDemo else { return }
        Keychain.set(token, account: tokenAccount)
        Task { await withCheckedContinuation { cont in SessionInjector.inject(token: token, for: server) { cont.resume() } } }
    }

    static func cookieToken(for server: Server) async -> String? {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let host = server.host
        return cookies.first {
            $0.name == "MMAUTHTOKEN" && host.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased())
        }?.value
    }

    func login(loginId: String, password: String, mfa: String) {
        state = .loading
        Task {
            do {
                let (token, _) = try await client.login(loginId: loginId, password: password, mfaToken: mfa)
                await withCheckedContinuation { cont in
                    SessionInjector.inject(token: token, for: server) { cont.resume() }
                }
                await bootstrap(token: token)
            } catch {
                state = .needsLogin(error.localizedDescription)
            }
        }
    }

    func stop() {
        ws?.disconnect()
        ws = nil
        connected = false
    }

    func logout() {
        stop()
        token = nil
        client.token = nil
        Keychain.delete(tokenAccount)
        state = .needsLogin(nil)
    }

    private func bootstrap(token: String, fallbacks: [String] = []) async {
        self.token = token
        client.token = token
        do {
            async let meReq = client.me()
            async let cfgReq = client.clientConfig()
            async let teamsReq = client.myTeams()
            async let prefsReq = client.preferences()
            let (me, cfg, teams, prefs) = try await (meReq, cfgReq, teamsReq, prefsReq)
            self.me = me
            self.config = cfg
            self.teams = teams.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            users[me.id] = me
            crt = Self.collapsedThreads(config: cfg, prefs: prefs)
            displayFormat = prefs.first { $0.category == "display_settings" && $0.name == "name_format" }?.value ?? cfg.teammateNameDisplay
            if currentTeamID == nil || !teams.contains(where: { $0.id == currentTeamID }) {
                currentTeamID = prefs.first { $0.category == "last" && $0.name == "team" }?.value.nonEmpty
                    ?? UserDefaults.standard.string(forKey: "team.\(server.id)").flatMap { id in teams.contains { $0.id == id } ? id : nil }
                    ?? teams.first?.id
            }
            for t in teams { try await loadChannels(teamID: t.id) }
            if let tid = currentTeamID { try await loadCategories(teamID: tid) }
            await refreshThreadTotals()
            state = .ready
            connectSocket(token: token)
            if let tid = currentTeamID, currentChannelID == nil {
                let last = UserDefaults.standard.string(forKey: "channel.\(server.id).\(tid)")
                let fallback = channels.values.first { $0.teamId == tid && $0.name == "town-square" }?.id
                    ?? categories.flatMap(\.channelIds).first
                selectChannel(last.flatMap { channels[$0] != nil ? $0 : nil } ?? fallback)
            }
            if cfg.enableCustomEmoji, let list = try? await client.customEmoji() {
                customEmoji = Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0.id) })
            }
            onBadgeChange?()
            retryDelay = 5
            persist(token: token)
        } catch MMError.unauthenticated {
            // A stale saved token: try the next candidate before asking for a password.
            if let next = fallbacks.first {
                await bootstrap(token: next, fallbacks: Array(fallbacks.dropFirst()))
            } else {
                Keychain.delete(tokenAccount)
                state = .needsLogin("Session expired. Please log in again.")
            }
        } catch {
            state = .error(error.localizedDescription)
            scheduleRetry()
        }
    }

    /// Server hiccups (5xx, timeouts) resolve themselves; keep trying with backoff.
    private func scheduleRetry() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 60)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.isError, let token = self.token else { return }
            self.state = .loading
            await self.bootstrap(token: token)
        }
    }

    private static func collapsedThreads(config: MMClientConfig, prefs: [MMPreference]) -> Bool {
        switch config.collapsedThreads {
        case "always_on": return true
        case "disabled": return false
        default:
            if let p = prefs.first(where: { $0.category == "display_settings" && $0.name == "collapsed_reply_threads" }) { return p.value == "on" }
            return config.collapsedThreads == "default_on"
        }
    }

    private(set) var displayFormat = "username"

    /// Markdown rendering context (mentions, custom emoji) for this server.
    var renderContext: RenderContext {
        RenderContext(myUsername: me?.username ?? "", customEmoji: Set(customEmoji.keys)) { [weak self] username in
            self?.users.values.first { $0.username == username }?.displayName(format: self?.displayFormat ?? "username")
        }
    }

    // MARK: Loading

    private func loadChannels(teamID: String) async throws {
        async let chReq = client.myChannels(teamID: teamID)
        async let memReq = client.myChannelMembers(teamID: teamID)
        let (chs, mems) = try await (chReq, memReq)
        for c in chs where c.deleteAt ?? 0 == 0 { channels[c.id] = c }
        for m in mems { members[m.channelId] = m }
        await ensureUsers(for: chs)
    }

    private func loadCategories(teamID: String) async throws {
        guard let me else { return }
        let cats = try await client.sidebarCategories(userID: me.id, teamID: teamID)
        var ordered = cats.order.compactMap { id in cats.categories.first { $0.id == id } }
        if ordered.isEmpty { ordered = cats.categories }
        // Only keep channels we actually know (deleted/archived ones are filtered out)
        categories = ordered.map { c in
            var c = c
            c.channelIds = c.channelIds.filter { channels[$0] != nil }
            if c.type == "direct_messages" {
                c.channelIds = c.channelIds.sorted { (channels[$0]?.lastPostAt ?? 0) > (channels[$1]?.lastPostAt ?? 0) }
                c.channelIds = Array(c.channelIds.prefix(40))
            }
            return c
        }
    }

    /// Fetch users referenced by DMs and posts that we have not seen yet.
    private func ensureUsers(for chs: [MMChannel]) async {
        guard let me else { return }
        let ids = chs.compactMap { $0.otherUserID(me: me.id) }
        await ensureUsers(ids: ids)
    }

    func ensureUsers(ids: [String]) async {
        let missing = Array(Set(ids.filter { users[$0] == nil && !$0.isEmpty }))
        guard !missing.isEmpty else { return }
        for chunk in stride(from: 0, to: missing.count, by: 100).map({ Array(missing[$0..<min($0 + 100, missing.count)]) }) {
            if let fetched = try? await client.users(ids: chunk) {
                for u in fetched { users[u.id] = u }
            }
            if let st = try? await client.statuses(ids: chunk) {
                for s in st { statuses[s.userId] = s.status }
            }
        }
    }

    func selectTeam(_ id: String) {
        guard id != currentTeamID else { return }
        currentTeamID = id
        UserDefaults.standard.set(id, forKey: "team.\(server.id)")
        Task {
            try? await loadCategories(teamID: id)
            let last = UserDefaults.standard.string(forKey: "channel.\(server.id).\(id)")
            selectChannel(last.flatMap { channels[$0] != nil ? $0 : nil } ?? categories.flatMap(\.channelIds).first)
        }
    }

    /// Sidebar order as displayed, used for keyboard navigation.
    var sidebarOrder: [String] {
        if Settings.compactSidebar { let c = compactSidebar(); return c.direct + c.channels }
        return categories.flatMap(\.channelIds).filter { channels[$0] != nil }
    }

    /// Compact sidebar: two sections (people, channels), each unread/mentioned first, then
    /// conversations active in the last few hours. The current channel is always included.
    func compactSidebar(hours: Double = 3) -> (direct: [String], channels: [String]) {
        let cutoff = Int64((Date().timeIntervalSince1970 - hours * 3600) * 1000)
        let visible = channels.values.filter { ($0.teamId.isEmpty || $0.teamId == currentTeamID) && members[$0.id] != nil }
        func section(_ list: [MMChannel]) -> [String] {
            let unread = list.filter { isUnread($0.id) || mentions(in: $0.id) > 0 }
                .sorted { a, b in
                    let ma = mentions(in: a.id), mb = mentions(in: b.id)
                    if (ma > 0) != (mb > 0) { return ma > 0 }
                    return (a.lastPostAt ?? 0) > (b.lastPostAt ?? 0)
                }
            let unreadSet = Set(unread.map(\.id))
            var recent = list.filter { !unreadSet.contains($0.id) && ($0.lastPostAt ?? 0) >= cutoff }
                .sorted { ($0.lastPostAt ?? 0) > ($1.lastPostAt ?? 0) }
            if let cur = currentChannelID, let c = channels[cur], list.contains(where: { $0.id == cur }),
               !unreadSet.contains(cur), !recent.contains(where: { $0.id == cur }) { recent.insert(c, at: 0) }
            return (unread + recent).map(\.id)
        }
        return (section(visible.filter(\.isDirect)), section(visible.filter { !$0.isDirect }))
    }

    func stepChannel(delta: Int, unreadOnly: Bool) {
        let order = sidebarOrder
        guard !order.isEmpty else { return }
        let start = currentChannelID.flatMap { order.firstIndex(of: $0) } ?? (delta > 0 ? -1 : order.count)
        var i = start
        for _ in 0..<order.count {
            i = (i + delta + order.count) % order.count
            let id = order[i]
            if !unreadOnly || isUnread(id) || mentions(in: id) > 0 { selectChannel(id); return }
        }
    }

    func selectChannel(_ id: String?) {
        guard let id, channels[id] != nil else { currentChannelID = nil; return }
        let prev = currentChannelID
        currentChannelID = id
        openThreadID = nil
        searchResults = nil
        showingThreads = false
        if let tid = currentTeamID { UserDefaults.standard.set(id, forKey: "channel.\(server.id).\(tid)") }
        if let c = channels[id], !c.teamId.isEmpty, c.teamId != currentTeamID { currentTeamID = c.teamId }
        markViewed(id, prev: prev)
        Task { await loadPosts(channelID: id) }
    }

    func loadPosts(channelID: String) async {
        var cp = posts[channelID] ?? ChannelPosts()
        guard !cp.loading else { return }
        cp.loading = true
        posts[channelID] = cp
        do {
            let list = try await client.posts(channelID: channelID, crt: crt)
            var fresh = ChannelPosts()
            fresh.order = list.order
            fresh.byID = list.posts
            fresh.hasMore = list.order.count >= 60
            fresh.loaded = true
            posts[channelID] = fresh
            lastPostAt[channelID] = list.posts.values.map(\.createAt).max() ?? 0
            await ensureUsers(ids: list.posts.values.map(\.userId))
        } catch {
            cp.loading = false
            posts[channelID] = cp
            lastError = error.localizedDescription
        }
    }

    func loadOlder(channelID: String) async {
        guard var cp = posts[channelID], cp.hasMore, !cp.loading, let oldest = cp.order.last else { return }
        cp.loading = true
        posts[channelID] = cp
        if let list = try? await client.posts(channelID: channelID, before: oldest, crt: crt) {
            cp.order.append(contentsOf: list.order.filter { cp.byID[$0] == nil })
            cp.byID.merge(list.posts) { old, _ in old }
            cp.hasMore = list.order.count >= 60
            await ensureUsers(ids: list.posts.values.map(\.userId))
        }
        cp.loading = false
        posts[channelID] = cp
    }

    func openThread(rootID: String) {
        openThreadID = rootID
        if AppPaths.isDemo {
            let root = posts.values.compactMap { $0.byID[rootID] }.first
            threads[rootID] = (root.map { [$0] } ?? []) + DemoData.replies(rootID: rootID)
            return
        }
        Task {
            if let list = try? await client.thread(rootID: rootID, crt: crt) {
                threads[rootID] = list.posts.values.sorted { $0.createAt < $1.createAt }
                await ensureUsers(ids: list.posts.values.map(\.userId))
            }
            if crt, let me, let tid = currentTeamID {
                try? await client.markThreadRead(userID: me.id, teamID: tid, threadID: rootID)
                if let i = userThreads.firstIndex(where: { $0.id == rootID }) {
                    userThreads[i].unreadReplies = 0
                    userThreads[i].unreadMentions = 0
                }
                await refreshThreadTotals()
            }
        }
    }

    // MARK: Threads view

    /// Mattermost's global "Threads" item: every followed thread, unread ones first.
    func openThreads() {
        guard crt else { return }
        showingThreads = true
        openThreadID = nil
        searchResults = nil
        Task { await loadUserThreads() }
    }

    func closeThreads() { showingThreads = false }

    func setThreadsFilter(unreadOnly: Bool) {
        guard threadsUnreadOnly != unreadOnly else { return }
        threadsUnreadOnly = unreadOnly
        Task { await loadUserThreads() }
    }

    func loadUserThreads() async {
        if AppPaths.isDemo {
            userThreads = DemoData.threads().filter { !threadsUnreadOnly || $0.isUnread }
            unreadThreadCount = DemoData.threads().filter(\.isUnread).count
            return
        }
        guard crt, let me, let tid = currentTeamID else { return }
        threadsLoading = true
        defer { threadsLoading = false }
        guard let result = try? await client.userThreads(userID: me.id, teamID: tid, unreadOnly: threadsUnreadOnly) else { return }
        let list = result.threads ?? []
        userThreads = list.sorted { a, b in a.isUnread == b.isUnread ? a.sortKey > b.sortKey : a.isUnread }
        unreadThreadCount = Int(result.totalUnreadThreads ?? 0)
        await ensureUsers(ids: list.map { $0.post.userId } + list.flatMap { ($0.participants ?? []).map(\.id) })
    }

    func markAllThreadsRead() {
        guard crt, let me, let tid = currentTeamID else { return }
        for i in userThreads.indices { userThreads[i].unreadReplies = 0; userThreads[i].unreadMentions = 0 }
        unreadThreadCount = 0
        if AppPaths.isDemo { threadUnread = false; threadMentions = 0; onBadgeChange?(); return }
        Task {
            try? await client.markAllThreadsRead(userID: me.id, teamID: tid)
            await refreshThreadTotals()
            await loadUserThreads()
        }
    }

    /// Websocket thread events arrive in bursts; coalesce the refresh.
    private func scheduleThreadsRefresh() {
        threadsRefreshTask?.cancel()
        threadsRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.refreshThreadTotals()
            if self.showingThreads { await self.loadUserThreads() }
        }
    }

    private func refreshThreadTotals() async {
        guard crt, let me else { return }
        var mentions = 0, unread = false, unreadThreads = 0
        for t in teams {
            if let totals = try? await client.threadTotals(userID: me.id, teamID: t.id) {
                mentions += Int(totals.totalUnreadMentions ?? 0)
                unreadThreads += Int(totals.totalUnreadThreads ?? 0)
                if (totals.totalUnreadThreads ?? 0) > 0 { unread = true }
            }
        }
        threadMentions = mentions
        threadUnread = unread
        unreadThreadCount = unreadThreads
        onBadgeChange?()
    }

    // MARK: Unread bookkeeping

    func mentions(in channelID: String) -> Int {
        guard let m = members[channelID] else { return 0 }
        return Int((crt ? m.mentionCountRoot : m.mentionCount) ?? 0)
    }

    func isUnread(_ channelID: String) -> Bool {
        guard let c = channels[channelID], let m = members[channelID], !m.isMuted else { return false }
        let total = (crt ? c.totalMsgCountRoot : c.totalMsgCount) ?? 0
        let seen = (crt ? m.msgCountRoot : m.msgCount) ?? 0
        return total > seen
    }

    var totalMentions: Int { members.keys.reduce(0) { $0 + mentions(in: $1) } + threadMentions }
    var anyUnread: Bool { threadUnread || members.keys.contains { isUnread($0) } }

    private func markViewed(_ id: String, prev: String?) {
        guard var m = members[id], let c = channels[id] else { return }
        m.msgCount = c.totalMsgCount
        m.msgCountRoot = c.totalMsgCountRoot
        m.mentionCount = 0
        m.mentionCountRoot = 0
        m.lastViewedAt = Int64(Date().timeIntervalSince1970 * 1000)
        members[id] = m
        onBadgeChange?()
        viewDebounce?.cancel()
        viewDebounce = Task { [client] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            try? await client.viewChannel(channelID: id, prev: prev)
        }
    }

    /// Call when the window regains focus: the visible channel counts as read.
    func foregroundChanged() {
        if let id = currentChannelID, isForeground(), isUnread(id) || mentions(in: id) > 0 { markViewed(id, prev: nil) }
    }

    // MARK: Actions

    private static let reactionShorthand = try! NSRegularExpression(pattern: "^\\+:([a-z0-9_+\\-]+):$")

    func send(message: String, fileIDs: [String] = [], rootID: String? = nil) async {
        guard let cid = currentChannelID, !(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fileIDs.isEmpty) else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        // "+:thumbsup:" reacts to the last post instead of sending (web app shorthand).
        if fileIDs.isEmpty, let m = Self.reactionShorthand.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)),
           let r = Range(m.range(at: 1), in: trimmed) {
            let source: [MMPost] = rootID.map { threads[$0] ?? [] } ?? (posts[cid]?.chronological ?? [])
            if let last = source.last(where: { !$0.isSystem }) { await toggleReaction(post: last, emoji: String(trimmed[r])) }
            return
        }
        // Slash commands run on the server; the ephemeral reply is shown in the banner.
        if fileIDs.isEmpty, trimmed.hasPrefix("/"), !trimmed.hasPrefix("//") {
            do {
                var body: [String: Any] = ["channel_id": cid, "command": trimmed]
                if let tid = currentTeamID { body["team_id"] = tid }
                if let rootID { body["root_id"] = rootID }
                let resp: [String: JSONValue] = try await client.post("commands/execute", body: body)
                if let text = resp["text"]?.string, !text.isEmpty { lastError = text }
            } catch { lastError = error.localizedDescription }
            return
        }
        do {
            let post = try await client.createPost(channelID: cid, message: message, rootID: rootID, fileIDs: fileIDs)
            insert(post: post)
        } catch { lastError = error.localizedDescription }
    }

    func edit(post: MMPost, message: String) async {
        do { let p = try await client.editPost(id: post.id, message: message); update(post: p) } catch { lastError = error.localizedDescription }
    }

    func delete(post: MMPost) async {
        do { try await client.deletePost(id: post.id); remove(postID: post.id, channelID: post.channelId, rootID: post.rootId) } catch { lastError = error.localizedDescription }
    }

    func toggleReaction(post: MMPost, emoji: String) async {
        guard let me else { return }
        let mine = post.metadata?.reactions?.contains { $0.userId == me.id && $0.emojiName == emoji } ?? false
        do {
            if mine { try await client.removeReaction(userID: me.id, postID: post.id, emoji: emoji) }
            else { try await client.addReaction(userID: me.id, postID: post.id, emoji: emoji) }
        } catch { lastError = error.localizedDescription }
    }

    func upload(fileURL: URL) async -> MMFileInfo? {
        guard let cid = currentChannelID else { return nil }
        do { return try await client.uploadFile(channelID: cid, fileURL: fileURL) } catch { lastError = error.localizedDescription; return nil }
    }

    func search(_ terms: String) async {
        guard let tid = currentTeamID, !terms.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searchTerms = terms
        searching = true
        defer { searching = false }
        let started = Date()
        do {
            let list = try await client.search(teamID: tid, terms: terms)
            guard searchTerms == terms else { return }
            let result = list.order.compactMap { list.posts[$0] }
            await ensureUsers(ids: result.map(\.userId))
            searchResults = result
            // Mattermost's database search gives up after ~30 s and answers with an empty list.
            if result.isEmpty, Date().timeIntervalSince(started) > 25 {
                lastError = "The server's search timed out and returned nothing. Narrow it down with from:user or in:channel and try again."
            }
        } catch { lastError = error.localizedDescription }
    }

    func openDirectMessage(with userID: String) async {
        guard let me else { return }
        if let existing = channels.values.first(where: { $0.isDirect && $0.otherUserID(me: me.id) == userID }) {
            selectChannel(existing.id)
            return
        }
        if let c = try? await client.createDirectChannel(me: me.id, other: userID) {
            channels[c.id] = c
            members[c.id] = try? await client.channelMember(channelID: c.id)
            if let tid = currentTeamID { try? await loadCategories(teamID: tid) }
            selectChannel(c.id)
        }
    }

    func join(channel: MMChannel) async {
        guard let me else { return }
        try? await client.joinChannel(channelID: channel.id, userID: me.id)
        channels[channel.id] = channel
        members[channel.id] = try? await client.channelMember(channelID: channel.id)
        if let tid = currentTeamID { try? await loadCategories(teamID: tid) }
        selectChannel(channel.id)
    }

    func sendTyping() {
        guard let cid = currentChannelID else { return }
        ws?.send(action: "user_typing", data: ["channel_id": cid, "parent_id": openThreadID ?? ""])
    }

    // MARK: Display helpers

    func displayName(userID: String) -> String {
        users[userID]?.displayName(format: displayFormat) ?? "…"
    }

    func author(of post: MMPost) -> String {
        if post.fromWebhook, let o = post.overrideUsername, !o.isEmpty { return o }
        return displayName(userID: post.userId)
    }

    func title(for channel: MMChannel) -> String {
        if channel.isDirect, let me, let other = channel.otherUserID(me: me.id) {
            return other == me.id ? "\(displayName(userID: me.id)) (you)" : displayName(userID: other)
        }
        if channel.isGroup, let me {
            let names = channel.displayName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0 != me.username }
                .map { u in users.values.first { $0.username == u }?.displayName(format: displayFormat) ?? u }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        return channel.displayName
    }

    func status(of userID: String) -> String { statuses[userID] ?? "offline" }

    func typingNames(in channelID: String) -> [String] {
        let now = Date()
        return (typing[channelID] ?? [:]).filter { $0.value > now && $0.key != me?.id }.keys.map { displayName(userID: $0) }.sorted()
    }

    // MARK: Post mutations

    private func insert(post: MMPost) {
        if let rid = post.rootId, !rid.isEmpty {
            if var t = threads[rid], !t.contains(where: { $0.id == post.id }) {
                t.append(post)
                threads[rid] = t
            }
            if crt {
                if var cp = posts[post.channelId], var root = cp.byID[rid] {
                    root.replyCount = (root.replyCount ?? 0) + 1
                    root.lastReplyAt = post.createAt
                    cp.byID[rid] = root
                    posts[post.channelId] = cp
                }
                return
            }
        }
        guard var cp = posts[post.channelId], cp.loaded else { return }
        guard cp.byID[post.id] == nil else { cp.byID[post.id] = post; posts[post.channelId] = cp; return }
        cp.byID[post.id] = post
        cp.order.insert(post.id, at: 0)
        posts[post.channelId] = cp
        lastPostAt[post.channelId] = max(lastPostAt[post.channelId] ?? 0, post.createAt)
    }

    private func update(post: MMPost) {
        if var cp = posts[post.channelId], cp.byID[post.id] != nil {
            var merged = post
            if merged.replyCount == nil { merged.replyCount = cp.byID[post.id]?.replyCount }
            cp.byID[post.id] = merged
            posts[post.channelId] = cp
        }
        let rid = (post.rootId ?? "").isEmpty ? post.id : post.rootId!
        if var t = threads[rid], let i = t.firstIndex(where: { $0.id == post.id }) { t[i] = post; threads[rid] = t }
    }

    private func remove(postID: String, channelID: String, rootID: String?) {
        if var cp = posts[channelID] {
            cp.byID[postID] = nil
            cp.order.removeAll { $0 == postID }
            posts[channelID] = cp
        }
        if let rid = rootID, var t = threads[rid] { t.removeAll { $0.id == postID }; threads[rid] = t }
        if threads[postID] != nil { threads[postID] = nil; if openThreadID == postID { openThreadID = nil } }
    }

    // MARK: Websocket

    private func connectSocket(token: String) {
        ws?.disconnect()
        let socket = MMWebSocket(baseURL: server.url, token: token)
        socket.onConnectionChange = { [weak self] c in
            guard let self else { return }
            let wasDown = !self.connected
            self.connected = c
            if c && wasDown && self.state == .ready { Task { await self.resync() } }
        }
        socket.onEvent = { [weak self] e in self?.handle(e) }
        socket.connect()
        ws = socket
    }

    /// After a reconnect: counts may have moved and posts may be missing.
    private func resync() async {
        for t in teams { try? await loadChannels(teamID: t.id) }
        if let tid = currentTeamID { try? await loadCategories(teamID: tid) }
        if let cid = currentChannelID, let since = lastPostAt[cid], since > 0,
           let list = try? await client.postsSince(channelID: cid, since: since, crt: crt) {
            for id in list.order.reversed() { if let p = list.posts[id] { insert(post: p) } }
        }
        await refreshThreadTotals()
        onBadgeChange?()
    }

    private func handle(_ e: MMWSEvent) {
        switch e.event {
        case "posted":
            guard let post: MMPost = e.json("post") else { return }
            handlePosted(post, event: e)
        case "post_edited":
            if let post: MMPost = e.json("post") { update(post: post) }
        case "post_deleted":
            if let post: MMPost = e.json("post") { remove(postID: post.id, channelID: post.channelId, rootID: post.rootId) }
        case "reaction_added", "reaction_removed":
            if let r: MMReaction = e.json("reaction") { applyReaction(r, added: e.event == "reaction_added") }
        case "channel_viewed", "multiple_channels_viewed":
            var ids: [String] = []
            if let id = e.data["channel_id"]?.string { ids.append(id) }
            if let times = e.data["channel_times"]?.object { ids.append(contentsOf: times.keys) }
            for id in ids { if var m = members[id], let c = channels[id] {
                m.msgCount = c.totalMsgCount; m.msgCountRoot = c.totalMsgCountRoot; m.mentionCount = 0; m.mentionCountRoot = 0
                members[id] = m
            } }
            onBadgeChange?()
        case "typing":
            if let cid = e.channelID, let uid = e.userID {
                var t = typing[cid] ?? [:]
                t[uid] = Date().addingTimeInterval(6)
                typing[cid] = t
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self] in self?.pruneTyping(cid) }
            }
        case "status_change":
            if let uid = e.data["user_id"]?.string, let st = e.data["status"]?.string { statuses[uid] = st }
        case "user_updated":
            if let u: MMUser = e.json("user") { users[u.id] = u }
        case "direct_added", "group_added", "channel_created", "channel_converted", "channel_updated", "user_added", "user_removed",
             "channel_deleted", "channel_member_updated", "channel_unarchived":
            if e.event == "user_removed", e.broadcast["user_id"]?.string == me?.id, let cid = e.data["channel_id"]?.string ?? e.channelID {
                channels[cid] = nil
                members[cid] = nil
                if currentChannelID == cid { selectChannel(categories.flatMap(\.channelIds).first { channels[$0] != nil }) }
            }
            scheduleRefresh()
        case "preferences_changed", "preferences_deleted", "sidebar_category_created", "sidebar_category_updated",
             "sidebar_category_deleted", "sidebar_category_order_updated":
            scheduleRefresh()
        case "thread_updated", "thread_read_changed", "thread_follow_changed":
            scheduleThreadsRefresh()
        default:
            break
        }
    }

    private func handlePosted(_ post: MMPost, event e: MMWSEvent) {
        guard let me else { return }
        if var c = channels[post.channelId] {
            c.lastPostAt = post.createAt
            c.totalMsgCount = (c.totalMsgCount ?? 0) + 1
            if !post.isReply { c.totalMsgCountRoot = (c.totalMsgCountRoot ?? 0) + 1 }
            channels[post.channelId] = c
        } else {
            scheduleRefresh()          // a new DM/GM we haven't seen
        }
        let mentionIDs: [String] = e.json("mentions") ?? []
        let mentioned = mentionIDs.contains(me.id)
        let viewing = post.channelId == currentChannelID && isForeground()
        if var m = members[post.channelId] {
            if post.userId == me.id || viewing {
                m.msgCount = channels[post.channelId]?.totalMsgCount
                m.msgCountRoot = channels[post.channelId]?.totalMsgCountRoot
            } else if mentioned {
                m.mentionCount = (m.mentionCount ?? 0) + 1
                if !post.isReply { m.mentionCountRoot = (m.mentionCountRoot ?? 0) + 1 }
            }
            members[post.channelId] = m
        }
        if post.channelId == currentChannelID {
            var t = typing[post.channelId] ?? [:]
            t[post.userId] = nil
            typing[post.channelId] = t
        }
        Task { await ensureUsers(ids: [post.userId]) }
        insert(post: post)
        if viewing && post.userId != me.id { markViewed(post.channelId, prev: nil) }
        onBadgeChange?()
        maybeNotify(post: post, mentioned: mentioned, viewing: viewing, senderName: e.data["sender_name"]?.string, channelName: e.data["channel_display_name"]?.string)
    }

    private func maybeNotify(post: MMPost, mentioned: Bool, viewing: Bool, senderName: String?, channelName: String?) {
        guard let me, post.userId != me.id, !post.isSystem, !viewing, Settings.notificationsEnabled else { return }
        guard let channel = channels[post.channelId], let member = members[post.channelId] else { return }
        let userDesktop = me.notifyProps?["desktop"]?.string ?? "mention"
        guard userDesktop != "none" else { return }
        let channelDesktop = member.desktopSetting == "default" ? userDesktop : member.desktopSetting
        guard channelDesktop != "none", !member.isMuted else { return }
        let isDM = channel.isDirect || channel.isGroup
        guard mentioned || isDM || channelDesktop == "all" else { return }
        let who = (senderName ?? author(of: post)).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let title = channel.isDirect ? who : "\(who) in \(channelName ?? title(for: channel))"
        var body = post.message
        if body.isEmpty, let n = post.metadata?.files?.count, n > 0 { body = "Sent \(n) file\(n == 1 ? "" : "s")" }
        onNotification?(title, String(body.prefix(240)), post.channelId, post.id)
    }

    private func applyReaction(_ r: MMReaction, added: Bool) {
        func mutate(_ p: inout MMPost) {
            var list = p.metadata?.reactions ?? []
            list.removeAll { $0.userId == r.userId && $0.emojiName == r.emojiName }
            if added { list.append(r) }
            if p.metadata == nil { p.metadata = MMPostMetadata() }
            p.metadata?.reactions = list
        }
        for (cid, var cp) in posts where cp.byID[r.postId] != nil {
            mutate(&cp.byID[r.postId]!)
            posts[cid] = cp
        }
        for (rid, var t) in threads { if let i = t.firstIndex(where: { $0.id == r.postId }) { mutate(&t[i]); threads[rid] = t } }
    }

    private func pruneTyping(_ cid: String) {
        let now = Date()
        typing[cid] = (typing[cid] ?? [:]).filter { $0.value > now }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            for t in teams { try? await loadChannels(teamID: t.id) }
            if let tid = currentTeamID { try? await loadCategories(teamID: tid) }
            onBadgeChange?()
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Small in-memory cache for avatars, thumbnails and custom emoji fetched with the API token.
@MainActor
final class ImageCache {
    private let client: MMClient
    private var images: [String: NSImage] = [:]
    private var order: [String] = []
    private var inflight: [String: Task<Data?, Never>] = [:]
    private let limit = 400

    init(client: MMClient) { self.client = client }

    func cached(_ key: String) -> NSImage? { images[key] }

    func image(path: String, query: [String: String] = [:], maxPixels: CGFloat = 96) async -> NSImage? {
        let key = path + (query.isEmpty ? "" : "?\(query)")
        if let img = images[key] { return img }
        if let t = inflight[key] {
            // Another caller is already fetching these bytes; decode our own copy when they land.
            return (await t.value).flatMap(NSImage.init(data:)).map { Self.downscale($0, maxPixels: maxPixels) }
        }
        // Fetch bytes off the main actor, then decode here: NSImage is not Sendable on macOS 13.
        let task = Task<Data?, Never> { [client] in try? await client.bytes(path, query: query) }
        inflight[key] = task
        let data = await task.value
        inflight[key] = nil
        let img = data.flatMap(NSImage.init(data:)).map { Self.downscale($0, maxPixels: maxPixels) }
        if let img {
            images[key] = img
            order.append(key)
            if order.count > limit, let old = order.first { order.removeFirst(); images[old] = nil }
        }
        return img
    }

    /// Keep bitmaps small: a 40pt avatar does not need a 512px image resident.
    private static func downscale(_ img: NSImage, maxPixels: CGFloat) -> NSImage {
        let size = img.size
        guard size.width > maxPixels * 2 || size.height > maxPixels * 2 else { return img }
        let scale = min(maxPixels * 2 / size.width, maxPixels * 2 / size.height)
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let out = NSImage(size: target)
        out.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

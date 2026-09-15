import SwiftUI

struct SidebarView: View {
    @ObservedObject var session: ServerSession
    @Binding var showSwitcher: Bool
    @EnvironmentObject var chrome: ChromeState
    @Environment(\.mmTheme) var theme
    @State private var collapsed: Set<String> = []
    @State private var compact = Settings.compactSidebar

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    threadsRow
                    if compact { compactList } else { categoryList }
                }
                .padding(.vertical, 6)
            }
        }
        .background(theme.sidebarBg)
        .foregroundColor(theme.sidebarText)
        .onReceive(NotificationCenter.default.publisher(for: Settings.changed)) { _ in compact = Settings.compactSidebar }
    }

    /// Pinned above the channels, as in the web app: unread followed threads live here.
    @ViewBuilder private var threadsRow: some View {
        if session.crt {
            let unread = session.threadUnread
            let mentions = session.threadMentions
            Button { session.openThreads() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble").font(.system(size: 13)).frame(width: 18)
                    Text("Threads")
                        .font(.system(size: 14, weight: unread || mentions > 0 ? .semibold : .regular))
                    Spacer(minLength: 4)
                    if mentions > 0 {
                        Text("\(mentions)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(theme.mentionText)
                            .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(theme.mentionBg))
                    } else if unread {
                        Circle().fill(theme.sidebarText).frame(width: 7, height: 7)
                    }
                }
                .foregroundColor(session.showingThreads || unread || mentions > 0 ? theme.sidebarText : theme.sidebarTextDim)
                .padding(.leading, 14).padding(.trailing, 10)
                .frame(height: 32)
                .background(
                    HStack(spacing: 0) {
                        Rectangle().fill(session.showingThreads ? theme.sidebarActiveBorder : .clear).frame(width: 3)
                        Rectangle().fill(session.showingThreads ? theme.sidebarActive : .clear)
                    }
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHoverBackground(session.showingThreads ? .clear : theme.sidebarHover, cornerRadius: 0)
            .padding(.bottom, 4)
        }
    }

    /// People and channels, each: unread first, then active in the last 3 hours.
    @ViewBuilder private var compactList: some View {
        let lists = session.compactSidebar()
        if !lists.direct.isEmpty {
            sectionLabel("People")
            ForEach(lists.direct, id: \.self) { id in
                if let ch = session.channels[id] { ChannelRow(session: session, channel: ch) }
            }
        }
        if !lists.channels.isEmpty {
            sectionLabel("Channels")
            ForEach(lists.channels, id: \.self) { id in
                if let ch = session.channels[id] { ChannelRow(session: session, channel: ch) }
            }
        }
        if lists.direct.isEmpty && lists.channels.isEmpty {
            Text("Nothing unread or active in the last 3 hours.\n⌘K finds any channel.")
                .font(.system(size: 12)).foregroundColor(theme.sidebarTextDim).padding(14)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.4)
            .foregroundColor(theme.sidebarTextDim)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
    }

    @ViewBuilder private var categoryList: some View {
                    ForEach(session.categories) { cat in
                        categoryHeader(cat)
                        if !collapsed.contains(cat.id) || cat.channelIds.contains(where: { session.isUnread($0) || session.mentions(in: $0) > 0 || $0 == session.currentChannelID }) {
                            ForEach(cat.channelIds, id: \.self) { id in
                                if let ch = session.channels[id], !collapsed.contains(cat.id) || session.isUnread(id) || session.mentions(in: id) > 0 || id == session.currentChannelID {
                                    ChannelRow(session: session, channel: ch)
                                }
                            }
                        }
                    }
    }

    private var header: some View {
        HStack {
            if session.teams.count > 1 {
                Menu {
                    ForEach(session.teams) { t in
                        Button { session.selectTeam(t.id) } label: {
                            HStack { Text(t.displayName); if t.id == session.currentTeamID { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    Text(session.teams.first { $0.id == session.currentTeamID }?.displayName ?? "Team")
                        .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(session.teams.first?.displayName ?? session.server.name)
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            Spacer()
        }
        .padding(.leading, chrome.tabBarVisible ? 14 : 78)   // room for the traffic lights when the tab bar is hidden
        .padding(.trailing, 14)
        .frame(height: 48)
        .background(theme.sidebarHeaderBg)
        .overlay(alignment: .bottom) {
            Button { showSwitcher = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                    Text("Find channel").font(.system(size: 12))
                    Spacer()
                    Text("⌘K").font(.system(size: 10)).opacity(0.6)
                }
                .foregroundColor(theme.sidebarTextDim)
                .padding(.horizontal, 8).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .offset(y: 36)
        }
        .padding(.bottom, 36)
    }

    private func categoryHeader(_ cat: MMSidebarCategory) -> some View {
        Button {
            if collapsed.contains(cat.id) { collapsed.remove(cat.id) } else { collapsed.insert(cat.id) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(collapsed.contains(cat.id) ? -90 : 0))
                Text(cat.displayName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                Spacer()
            }
            .foregroundColor(theme.sidebarTextDim)
            .padding(.horizontal, 14).frame(height: 28)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

struct ChannelRow: View {
    @ObservedObject var session: ServerSession
    let channel: MMChannel
    @Environment(\.mmTheme) var theme

    var body: some View {
        let active = channel.id == session.currentChannelID && !session.showingThreads
        let unread = session.isUnread(channel.id)
        let mentions = session.mentions(in: channel.id)
        let muted = session.members[channel.id]?.isMuted ?? false
        Button { session.selectChannel(channel.id) } label: {
            HStack(spacing: 8) {
                icon
                Text(session.title(for: channel))
                    .font(.system(size: 14, weight: unread || mentions > 0 ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if mentions > 0 {
                    Text("\(mentions)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(theme.mentionText)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(theme.mentionBg))
                }
            }
            .foregroundColor(active || unread || mentions > 0 ? theme.sidebarText : theme.sidebarTextDim)
            .opacity(muted && !active ? 0.5 : 1)
            .padding(.leading, 14).padding(.trailing, 10)
            .frame(height: 32)
            .background(
                HStack(spacing: 0) {
                    Rectangle().fill(active ? theme.sidebarActiveBorder : .clear).frame(width: 3)
                    Rectangle().fill(active ? theme.sidebarActive : .clear)
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHoverBackground(active ? .clear : theme.sidebarHover, cornerRadius: 0)
    }

    @ViewBuilder private var icon: some View {
        if channel.isDirect, let me = session.me, let other = channel.otherUserID(me: me.id) {
            Avatar(userID: other, size: 18, showStatus: true).padding(.trailing, 2)
        } else if channel.isGroup {
            Text("\(max(2, channel.displayName.split(separator: ",").count))")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.16)))
        } else {
            Image(systemName: channel.isPrivate ? "lock.fill" : "globe")
                .font(.system(size: 13)).frame(width: 18)
        }
    }
}

/// ⌘K quick switcher: channels, DMs, and (via search) joinable channels and people.
struct ChannelSwitcher: View {
    @ObservedObject var session: ServerSession
    @Binding var isPresented: Bool
    @Environment(\.mmTheme) var theme
    @State private var query = ""
    @State private var selection = 0
    @State private var remoteChannels: [MMChannel] = []
    @State private var remoteUsers: [MMUser] = []
    @FocusState private var focused: Bool

    private enum Item: Identifiable {
        case channel(MMChannel), user(MMUser), joinable(MMChannel)
        var id: String { switch self { case .channel(let c): return "c" + c.id; case .user(let u): return "u" + u.id; case .joinable(let c): return "j" + c.id } }
    }

    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let mine = session.channels.values.filter { c in
            q.isEmpty || session.title(for: c).lowercased().contains(q) || c.name.lowercased().contains(q)
        }
        .sorted { a, b in
            let ua = session.isUnread(a.id) || session.mentions(in: a.id) > 0, ub = session.isUnread(b.id) || session.mentions(in: b.id) > 0
            if ua != ub { return ua }
            return (a.lastPostAt ?? 0) > (b.lastPostAt ?? 0)
        }
        var out: [Item] = mine.prefix(q.isEmpty ? 30 : 12).map { .channel($0) }
        let known = Set(mine.map(\.id))
        let knownUsers = Set(mine.compactMap { $0.otherUserID(me: session.me?.id ?? "") })
        out += remoteUsers.filter { !knownUsers.contains($0.id) }.prefix(6).map { .user($0) }
        out += remoteChannels.filter { !known.contains($0.id) }.prefix(6).map { .joinable($0) }
        return out
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { dismiss() }
            VStack(spacing: 0) {
                TextField("Find channels, people…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(12)
                    .focused($focused)
                    .onSubmit { open(selection) }
                    .onChange(of: query) { _ in selection = 0; Task { await fetchRemote() } }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                row(item, selected: i == selection)
                                    .onTapGesture { open(i) }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { s in if s < items.count { proxy.scrollTo(items[s].id) } }
                }
            }
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)).shadow(radius: 20))
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(KeyCatcher(onKey: handleKey))
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommands.debugDump)) { n in
            guard let path = n.object as? String else { return }
            let names = items.map { item -> String in
                switch item { case .channel(let c): return session.title(for: c); case .user(let u): return "@" + u.username; case .joinable(let c): return "+" + c.name }
            }
            try? "switcher query='\(query)' selection=\(selection) items=\(names)".write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 8) {
            switch item {
            case .channel(let c):
                if c.isDirect, let me = session.me, let other = c.otherUserID(me: me.id) { Avatar(userID: other, size: 20, showStatus: true) }
                else { Image(systemName: c.isPrivate ? "lock.fill" : (c.isGroup ? "person.2" : "globe")).frame(width: 20) }
                Text(session.title(for: c)).font(.system(size: 14, weight: session.isUnread(c.id) ? .semibold : .regular))
                if !c.isDirect && !c.isGroup { Text("~\(c.name)").foregroundColor(.secondary).font(.system(size: 12)) }
                Spacer()
                if session.mentions(in: c.id) > 0 { Text("\(session.mentions(in: c.id))").font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).background(Capsule().fill(theme.dnd)).foregroundColor(.white) }
            case .user(let u):
                Avatar(userID: u.id, size: 20, showStatus: true)
                Text(u.displayName(format: session.displayFormat)).font(.system(size: 14))
                Text("@\(u.username)").foregroundColor(.secondary).font(.system(size: 12))
                Spacer()
                Text("Message").font(.system(size: 11)).foregroundColor(.secondary)
            case .joinable(let c):
                Image(systemName: "globe").frame(width: 20)
                Text(c.displayName).font(.system(size: 14))
                Spacer()
                Text("Join").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(selected ? theme.buttonBg.opacity(0.85) : .clear)
        .foregroundColor(selected ? .white : .primary)
        .contentShape(Rectangle())
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: selection = min(selection + 1, max(items.count - 1, 0)); return true   // ↓
        case 126: selection = max(selection - 1, 0); return true                            // ↑
        case 53: dismiss(); return true                                                     // esc
        default: return false
        }
    }

    private func dismiss() {
        isPresented = false
        NotificationCenter.default.post(name: NativeCommands.focusComposer, object: session.server.id)
    }

    private func open(_ i: Int) {
        guard i < items.count else { return }
        let item = items[i]
        dismiss()
        Task {
            switch item {
            case .channel(let c): session.selectChannel(c.id)
            case .user(let u): await session.openDirectMessage(with: u.id)
            case .joinable(let c): await session.join(channel: c)
            }
        }
    }

    private func fetchRemote() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let tid = session.currentTeamID else { remoteUsers = []; remoteChannels = []; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard q == query.trimmingCharacters(in: .whitespaces) else { return }
        async let users = session.client.autocompleteUsers(term: q, teamID: tid, channelID: nil)
        async let channels = session.client.joinableChannels(teamID: tid, term: q)
        remoteUsers = (try? await users) ?? []
        remoteChannels = (try? await channels) ?? []
        await session.ensureUsers(ids: remoteUsers.map(\.id))
    }
}

/// Lets an overlay see key presses (arrows/escape) that the text field would otherwise consume.
struct KeyCatcher: NSViewRepresentable {
    var onKey: (NSEvent) -> Bool
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            context.coordinator.onKey(e) ? nil : e
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onKey = onKey }
    func makeCoordinator() -> Coordinator { Coordinator(onKey: onKey) }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }
    final class Coordinator {
        var onKey: (NSEvent) -> Bool
        var monitor: Any?
        init(onKey: @escaping (NSEvent) -> Bool) { self.onKey = onKey }
    }
}

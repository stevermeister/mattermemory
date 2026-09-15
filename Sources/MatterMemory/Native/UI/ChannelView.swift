import SwiftUI

struct ChannelView: View {
    @ObservedObject var session: ServerSession
    @Binding var showSearch: Bool
    var onOpenWebView: () -> Void
    @Environment(\.mmTheme) var theme
    @State private var editing: MMPost?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let cid = session.currentChannelID {
                MessageList(session: session, channelID: cid, rootID: nil, onEdit: { editing = $0 })
                Composer(session: session, rootID: nil, editing: $editing)
            } else {
                Spacer()
                Text("Select a channel").foregroundColor(.secondary)
                Spacer()
            }
        }
        .background(theme.centerBg)
        .foregroundColor(theme.centerText)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let cid = session.currentChannelID, let ch = session.channels[cid] {
                if ch.isDirect, let me = session.me, let other = ch.otherUserID(me: me.id) {
                    Avatar(userID: other, size: 24, showStatus: true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title(for: ch)).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if let h = ch.header, !h.isEmpty {
                        Text(MessageRenderer.inline(h, context: session.renderContext)).font(.system(size: 12)).foregroundColor(theme.centerTextDim).lineLimit(1)
                    } else if ch.isDirect, let me = session.me, let other = ch.otherUserID(me: me.id), let u = session.users[other] {
                        Text("@\(u.username)").font(.system(size: 12)).foregroundColor(theme.centerTextDim)
                    }
                }
            }
            Spacer()
            if !session.connected {
                Label("Reconnecting…", systemImage: "wifi.slash").font(.system(size: 11)).foregroundColor(theme.dnd)
            }
            Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Search messages (⌘F)")
            Button { onOpenWebView() } label: { Image(systemName: "safari") }
                .buttonStyle(.borderless).help("Open this server in the full web view")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

/// Chronological post list for a channel, or a thread when `rootID` is set.
struct MessageList: View {
    @ObservedObject var session: ServerSession
    let channelID: String
    let rootID: String?
    var onEdit: (MMPost) -> Void
    @Environment(\.mmTheme) var theme
    @State private var stickToBottom = true

    private var items: [MMPost] {
        if let rootID { return session.threads[rootID] ?? [] }
        return session.posts[channelID]?.chronological ?? []
    }

    var body: some View {
        let posts = items
        let lastViewed = session.members[channelID]?.lastViewedAt ?? 0
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if rootID == nil, session.posts[channelID]?.hasMore == true {
                        HStack {
                            Spacer()
                            if session.posts[channelID]?.loading == true { ProgressView().controlSize(.small) }
                            else { Button("Load older messages") { Task { await session.loadOlder(channelID: channelID) } }.buttonStyle(.link) }
                            Spacer()
                        }.padding(8)
                    } else if rootID == nil, session.posts[channelID]?.loaded == true, let ch = session.channels[channelID] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Beginning of \(session.title(for: ch))").font(.title3.weight(.semibold))
                            if let p = ch.purpose, !p.isEmpty { Text(p).foregroundColor(theme.centerTextDim) }
                        }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 8)
                    }
                    ForEach(Array(posts.enumerated()), id: \.element.id) { i, post in
                        let prev = i > 0 ? posts[i - 1] : nil
                        if prev == nil || !Calendar.current.isDate(prev!.date, inSameDayAs: post.date) {
                            DaySeparator(date: post.date)
                        }
                        if rootID == nil, let prev, prev.createAt <= lastViewed, post.createAt > lastViewed, post.userId != session.me?.id, i > 0 {
                            NewMessagesSeparator()
                        }
                        PostRow(session: session, post: post,
                                continuation: prev.map { $0.userId == post.userId && !$0.isSystem && !post.isSystem && post.createAt - $0.createAt < 5 * 60_000 && $0.rootId == post.rootId } ?? false,
                                inThread: rootID != nil, onEdit: onEdit)
                            .id(post.id)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
            }
            .onChange(of: posts.last?.id) { _ in if stickToBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: channelID) { _ in stickToBottom = true; DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: session.openThreadID) { _ in
                // The list is re-laid out when the thread panel opens/closes; keep the bottom in view.
                if stickToBottom { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: session.posts[channelID]?.loaded) { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .overlay(alignment: .bottom) {
                let names = session.typingNames(in: channelID)
                if !names.isEmpty {
                    Text("\(names.joined(separator: ", ")) \(names.count == 1 ? "is" : "are") typing…")
                        .font(.system(size: 11)).foregroundColor(theme.centerTextDim)
                        .padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.centerBg.opacity(0.9))
                }
            }
        }
    }
}

struct DaySeparator: View {
    let date: Date
    @Environment(\.mmTheme) var theme
    var body: some View {
        HStack {
            Rectangle().fill(theme.divider).frame(height: 1)
            Text(relativeDay(date)).font(.system(size: 12, weight: .semibold)).foregroundColor(theme.centerTextDim).fixedSize()
            Rectangle().fill(theme.divider).frame(height: 1)
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct NewMessagesSeparator: View {
    @Environment(\.mmTheme) var theme
    var body: some View {
        HStack {
            Rectangle().fill(theme.newMessage).frame(height: 1)
            Text("New Messages").font(.system(size: 12, weight: .semibold)).foregroundColor(theme.newMessage).fixedSize()
            Rectangle().fill(theme.newMessage).frame(height: 1)
        }.padding(.horizontal, 16).padding(.vertical, 6)
    }
}

/// Message input with attachments, edit mode and reply support.
struct Composer: View {
    @ObservedObject var session: ServerSession
    let rootID: String?
    @Binding var editing: MMPost?
    @Environment(\.mmTheme) var theme
    @State private var text = ""
    @State private var files: [MMFileInfo] = []
    @State private var uploading = 0
    @State private var focusToken = 0
    @State private var editorHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let editing {
                HStack {
                    Text("Editing message").font(.system(size: 11, weight: .semibold)).foregroundColor(theme.centerTextDim)
                    Spacer()
                    Button("Cancel") { self.editing = nil; text = "" }.buttonStyle(.link).font(.system(size: 11))
                }
                .onAppear { text = editing.message; focusToken += 1 }
            }
            if !files.isEmpty || uploading > 0 {
                HStack(spacing: 6) {
                    ForEach(files) { f in
                        HStack(spacing: 4) {
                            Image(systemName: "doc").font(.system(size: 11))
                            Text(f.name).font(.system(size: 11)).lineLimit(1)
                            Button { files.removeAll { $0.id == f.id } } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(theme.codeBg))
                    }
                    if uploading > 0 { ProgressView().controlSize(.small); Text("Uploading…").font(.system(size: 11)) }
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ComposerTextView(text: $text, placeholder: placeholder, onSend: send,
                                 onEscape: {
                                     if editing != nil { editing = nil; text = "" }
                                     else { NotificationCenter.default.post(name: NativeCommands.escape, object: session.server.id) }
                                 },
                                 onUpArrowEmpty: editLast,
                                 onTyping: { session.sendTyping() },
                                 onDrop: { urls in Task { await upload(urls) } },
                                 onHeightChange: { editorHeight = $0 },
                                 focusToken: focusToken)
                    .frame(height: editorHeight)
                Button { pickFiles() } label: { Image(systemName: "paperclip") }.buttonStyle(.borderless).padding(.bottom, 8).help("Attach files")
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.borderless).padding(.bottom, 8)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty)
                    .foregroundColor(theme.buttonBg)
            }
            .background(RoundedRectangle(cornerRadius: 6).stroke(theme.divider, lineWidth: 1))
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
        .onChange(of: session.currentChannelID) { _ in if rootID == nil { text = ""; files = []; editing = nil; focusToken += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommands.focusComposer)) { n in
            if (n.object as? UUID) == session.server.id, rootID == nil, session.openThreadID == nil { focusToken += 1 }
        }
    }

    private var placeholder: String {
        if rootID != nil { return "Reply…" }
        if let cid = session.currentChannelID, let ch = session.channels[cid] { return "Write to \(session.title(for: ch))" }
        return "Write a message"
    }

    private func send() {
        let msg = text
        if let editing {
            self.editing = nil
            text = ""
            Task { await session.edit(post: editing, message: msg) }
            return
        }
        guard !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty else { return }
        let ids = files.map(\.id)
        text = ""
        files = []
        Task { await session.send(message: msg, fileIDs: ids, rootID: rootID) }
    }

    private func editLast() {
        guard let me = session.me else { return }
        let source: [MMPost] = rootID.map { session.threads[$0] ?? [] } ?? (session.currentChannelID.flatMap { session.posts[$0]?.chronological } ?? [])
        if let last = source.last(where: { $0.userId == me.id && !$0.isSystem }) { editing = last }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { r in if r == .OK { Task { await upload(panel.urls) } } }
    }

    private func upload(_ urls: [URL]) async {
        for url in urls {
            uploading += 1
            if let info = await session.upload(fileURL: url) { files.append(info) }
            uploading -= 1
        }
    }
}

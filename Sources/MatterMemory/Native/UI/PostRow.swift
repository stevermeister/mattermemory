import SwiftUI

struct PostRow: View {
    @ObservedObject var session: ServerSession
    let post: MMPost
    var continuation: Bool
    var inThread: Bool
    var onEdit: (MMPost) -> Void
    @Environment(\.mmTheme) var theme
    @Environment(\.openURL) var openURL
    @State private var hovering = false
    @State private var showEmojiPicker = false

    private static let quickReactions = ["+1", "heart", "joy", "tada", "eyes", "pray", "white_check_mark", "-1"]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if continuation {
                Text(timeFormatter.string(from: post.date))
                    .font(.system(size: 10)).foregroundColor(theme.centerTextDim)
                    .frame(width: 36, alignment: .trailing)
                    .opacity(hovering ? 1 : 0)
                    .padding(.top, 3)
            } else if post.isSystem {
                Image(systemName: "info.circle").foregroundColor(theme.centerTextDim).frame(width: 36)
            } else {
                Avatar(userID: post.userId, size: 36)
                    .contextMenu { Button("Message \(session.displayName(userID: post.userId))") { Task { await session.openDirectMessage(with: post.userId) } } }
            }
            VStack(alignment: .leading, spacing: 3) {
                if !continuation {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(session.author(of: post)).font(.system(size: 14, weight: .semibold))
                        if post.fromWebhook || session.users[post.userId]?.isBot == true {
                            Text("BOT").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(theme.codeBg))
                        }
                        Text(timeFormatter.string(from: post.date)).font(.system(size: 11)).foregroundColor(theme.centerTextDim)
                    }
                }
                if post.isSystem {
                    Text(MessageRenderer.plainPreview(post.message)).font(.system(size: 13)).foregroundColor(theme.centerTextDim)
                } else {
                    MessageBody(session: session, message: post.message)
                    if (post.editAt ?? 0) > 0 { Text("(edited)").font(.system(size: 11)).foregroundColor(theme.centerTextDim) }
                }
                ForEach(Array(post.attachments.enumerated()), id: \.offset) { _, att in SlackAttachment(session: session, attachment: att) }
                if let files = post.metadata?.files, !files.isEmpty { FileAttachments(session: session, files: files) }
                if let reactions = post.metadata?.reactions, !reactions.isEmpty { ReactionBar(session: session, post: post, reactions: reactions) }
                if !inThread, session.crt, let n = post.replyCount, n > 0 {
                    Button { session.openThread(rootID: post.id) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 11))
                            Text("\(n) \(n == 1 ? "reply" : "replies")").font(.system(size: 12, weight: .semibold))
                            if let t = post.lastReplyAt { Text("Last reply " + relativeTime(Date(timeIntervalSince1970: Double(t) / 1000))).font(.system(size: 11)).foregroundColor(theme.centerTextDim) }
                        }.foregroundColor(theme.link)
                    }.buttonStyle(.plain).padding(.top, 2)
                } else if !inThread, !session.crt, post.isReply, let rid = post.rootId {
                    Button { session.openThread(rootID: rid) } label: {
                        Label("Commented on a thread", systemImage: "arrow.turn.down.right").font(.system(size: 11)).foregroundColor(theme.centerTextDim)
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, continuation ? 2 : 6)
        .background(hovering ? theme.hoverBg : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // Like the web app: clicking a post that has a thread opens it.
            guard !inThread, !post.isSystem, (post.replyCount ?? 0) > 0 || (session.crt == false && post.isReply) else { return }
            session.openThread(rootID: (post.rootId ?? "").isEmpty ? post.id : post.rootId!)
        }
        .overlay(alignment: .topTrailing) { if hovering && !post.isSystem { actions } }
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .popover(isPresented: $showEmojiPicker) { EmojiPicker(session: session) { name in showEmojiPicker = false; Task { await session.toggleReaction(post: post, emoji: name) } } }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            ForEach(Self.quickReactions.prefix(3), id: \.self) { e in
                Button { Task { await session.toggleReaction(post: post, emoji: e) } } label: { EmojiView(name: e, size: 14) }.buttonStyle(.plain).frame(width: 24, height: 24)
            }
            Button { showEmojiPicker = true } label: { Image(systemName: "face.smiling") }.buttonStyle(.plain).frame(width: 24, height: 24).help("Add reaction")
            if !inThread && !post.isReply {
                Button { session.openThread(rootID: post.id) } label: { Image(systemName: "arrowshape.turn.up.left") }.buttonStyle(.plain).frame(width: 24, height: 24).help("Reply in thread")
            }
            Menu { menu } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24, height: 24)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .windowBackgroundColor)).shadow(radius: 2))
        .padding(.trailing, 16).padding(.top, -8)
    }

    @ViewBuilder private var menu: some View {
        if !inThread && !post.isReply { Button("Reply in thread") { session.openThread(rootID: post.id) } }
        Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(post.message, forType: .string) }
        Button("Copy link") {
            let team = session.teams.first { $0.id == session.currentTeamID }?.name ?? ""
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.server.url.appendingPathComponent("\(team)/pl/\(post.id)").absoluteString, forType: .string)
        }
        if post.userId == session.me?.id {
            Divider()
            Button("Edit") { onEdit(post) }
            Button("Delete", role: .destructive) { Task { await session.delete(post: post) } }
        }
    }
}

func relativeTime(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: Date())
}

struct MessageBody: View {
    @ObservedObject var session: ServerSession
    let message: String
    @Environment(\.mmTheme) var theme

    /// Parsing markdown for every body re-evaluation is wasteful; rendered blocks are small.
    private static let cache = NSCache<NSString, BlocksBox>()
    final class BlocksBox { let blocks: [MessageBlock]; init(_ b: [MessageBlock]) { blocks = b } }

    private var blocks: [MessageBlock] {
        let key = (message + "|" + (session.me?.username ?? "")) as NSString
        if let hit = Self.cache.object(forKey: key) { return hit.blocks }
        let ctx = RenderContext(myUsername: session.me?.username ?? "", customEmoji: Set(session.customEmoji.keys)) { username in
            session.users.values.first { $0.username == username }?.displayName(format: session.displayFormat)
        }
        let b = MessageRenderer.blocks(for: message, context: ctx)
        Self.cache.countLimit = 2000
        Self.cache.setObject(BlocksBox(b), forKey: key)
        return b
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in BlockView(block: block) }
        }
    }
}

struct BlockView: View {
    let block: MessageBlock
    @Environment(\.mmTheme) var theme

    var body: some View {
        switch block {
        case .paragraph(let a):
            Text(a).font(.system(size: 13.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case .heading(let a, let level):
            Text(a).font(.system(size: [22, 19, 17, 15, 14, 13][min(level, 6) - 1], weight: .bold)).textSelection(.enabled)
        case .code(let code, _):
            ScrollView(.horizontal) {
                Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 4).fill(theme.codeBg))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.divider))
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(theme.divider).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) { ForEach(blocks) { BlockView(block: $0) } }
            }
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(i + 1)." : "•").font(.system(size: 13.5)).frame(minWidth: 14, alignment: .trailing)
                        Text(item).font(.system(size: 13.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.leading, 4)
        case .table(let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(cell).font(.system(size: 12.5, weight: i == 0 ? .semibold : .regular)) } }
                        if i == 0 { Divider() }
                    }
                }.padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 4).stroke(theme.divider))
        case .rule:
            Divider()
        }
    }
}

/// Slack-style message attachments used by integrations/bots.
struct SlackAttachment: View {
    @ObservedObject var session: ServerSession
    let attachment: JSONValue
    @Environment(\.mmTheme) var theme

    var body: some View {
        let color = attachment["color"]?.string.flatMap { Color(hex: $0) } ?? theme.divider
        VStack(alignment: .leading, spacing: 4) {
            if let pretext = attachment["pretext"]?.string, !pretext.isEmpty { MessageBody(session: session, message: pretext) }
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    if let author = attachment["author_name"]?.string, !author.isEmpty { Text(author).font(.system(size: 12, weight: .semibold)) }
                    if let title = attachment["title"]?.string, !title.isEmpty {
                        if let link = attachment["title_link"]?.string, let url = URL(string: link) { Link(title, destination: url).font(.system(size: 14, weight: .semibold)) }
                        else { Text(title).font(.system(size: 14, weight: .semibold)) }
                    }
                    if let text = attachment["text"]?.string, !text.isEmpty { MessageBody(session: session, message: text) }
                    if let fields = attachment["fields"]?.array, !fields.isEmpty {
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, f in
                            VStack(alignment: .leading, spacing: 1) {
                                if let t = f["title"]?.string, !t.isEmpty { Text(t).font(.system(size: 12, weight: .semibold)) }
                                if let v = f["value"]?.string, !v.isEmpty { MessageBody(session: session, message: v) }
                            }
                        }
                    }
                    if let footer = attachment["footer"]?.string, !footer.isEmpty { Text(footer).font(.system(size: 11)).foregroundColor(theme.centerTextDim) }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            switch hex { case "good": self = Color(red: 0.24, green: 0.72, blue: 0.53); case "warning": self = .orange; case "danger": self = .red; default: return nil }
            return
        }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

struct FileAttachments: View {
    @ObservedObject var session: ServerSession
    let files: [MMFileInfo]
    @Environment(\.mmTheme) var theme
    @State private var preview: MMFileInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let images = files.filter(\.isImage), others = files.filter { !$0.isImage }
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images) { f in
                        Button { preview = f } label: {
                            AuthImage(path: "files/\(f.id)/thumbnail", maxPixels: 240) {
                                RoundedRectangle(cornerRadius: 4).fill(theme.codeBg).overlay(ProgressView().controlSize(.small))
                            }
                            .aspectRatio(contentMode: .fill)
                            .frame(width: thumbWidth(f), height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain).help(f.name)
                    }
                }
            }
            ForEach(others) { f in
                Button { download(f) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill").foregroundColor(theme.link)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("\((f.extension ?? "").uppercased()) \(formatBytes(f.size))").font(.system(size: 11)).foregroundColor(theme.centerTextDim)
                        }
                        Image(systemName: "arrow.down.circle").foregroundColor(theme.centerTextDim)
                    }
                    .padding(8).frame(maxWidth: 320, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(theme.divider))
                }.buttonStyle(.plain)
            }
        }
        .popover(item: $preview) { f in
            AuthImage(path: "files/\(f.id)/preview", maxPixels: 1600) { ProgressView() }
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 900, maxHeight: 700)
                .padding(8)
                .contextMenu { Button("Download") { download(f) } }
        }
    }

    private func thumbWidth(_ f: MMFileInfo) -> CGFloat {
        guard let w = f.width, let h = f.height, h > 0 else { return 160 }
        return min(280, max(80, CGFloat(w) / CGFloat(h) * 120))
    }

    private func download(_ f: MMFileInfo) {
        Task {
            guard let data = try? await session.client.bytes("files/\(f.id)", query: ["download": "1"]) else { return }
            let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            var dest = dir.appendingPathComponent(f.name)
            var n = 2
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = dir.appendingPathComponent("\((f.name as NSString).deletingPathExtension) (\(n)).\((f.name as NSString).pathExtension)")
                n += 1
            }
            try? data.write(to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }
}

struct ReactionBar: View {
    @ObservedObject var session: ServerSession
    let post: MMPost
    let reactions: [MMReaction]
    @Environment(\.mmTheme) var theme

    var body: some View {
        let grouped = Dictionary(grouping: reactions, by: \.emojiName).sorted { $0.value.count > $1.value.count || ($0.value.count == $1.value.count && $0.key < $1.key) }
        HStack(spacing: 4) {
            ForEach(grouped, id: \.key) { name, list in
                let mine = list.contains { $0.userId == session.me?.id }
                Button { Task { await session.toggleReaction(post: post, emoji: name) } } label: {
                    HStack(spacing: 3) {
                        EmojiView(name: name, size: 14)
                        Text("\(list.count)").font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(mine ? theme.buttonBg.opacity(0.15) : theme.codeBg))
                    .overlay(Capsule().stroke(mine ? theme.buttonBg : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(list.map { session.displayName(userID: $0.userId) }.joined(separator: ", "))
            }
        }.padding(.top, 2)
    }
}

struct EmojiPicker: View {
    @ObservedObject var session: ServerSession
    var onPick: (String) -> Void
    @State private var query = ""

    private var names: [String] {
        let all = Array(Emoji.map.keys) + Array(session.customEmoji.keys)
        let q = query.lowercased()
        let filtered = q.isEmpty ? all : all.filter { $0.contains(q) }
        return filtered.sorted().prefix(240).map { $0 }
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField("Search emoji", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 9), spacing: 2) {
                    ForEach(names, id: \.self) { n in
                        Button { onPick(n) } label: { EmojiView(name: n, size: 18).frame(width: 28, height: 28) }.buttonStyle(.plain).help(n)
                    }
                }
            }.frame(height: 220)
        }
        .padding(8).frame(width: 300)
    }
}

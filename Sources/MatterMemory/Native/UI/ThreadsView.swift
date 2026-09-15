import SwiftUI

/// Mattermost's global "Threads" list: every thread you follow, unread first.
struct ThreadsView: View {
    @ObservedObject var session: ServerSession
    @Environment(\.mmTheme) var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if session.threadsLoading && session.userThreads.isEmpty {
                Spacer(); ProgressView(); Spacer()
            } else if session.userThreads.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble").font(.system(size: 28)).foregroundColor(theme.centerTextDim)
                    Text(session.threadsUnreadOnly ? "No unread threads" : "No followed threads yet")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Threads you start, reply to or follow show up here.")
                        .font(.system(size: 12)).foregroundColor(theme.centerTextDim)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.userThreads) { thread in
                            ThreadListRow(session: session, thread: thread)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(theme.centerBg)
        .foregroundColor(theme.centerText)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Threads").font(.system(size: 16, weight: .semibold))
            Picker("", selection: Binding(get: { session.threadsUnreadOnly }, set: { session.setThreadsFilter(unreadOnly: $0) })) {
                Text("All").tag(false)
                Text("Unreads").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            if session.threadsLoading { ProgressView().controlSize(.small) }
            Button("Mark all read") { session.markAllThreadsRead() }
                .buttonStyle(.link).font(.system(size: 12))
                .disabled(session.unreadThreadCount == 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

private struct ThreadListRow: View {
    @ObservedObject var session: ServerSession
    let thread: MMUserThread
    @Environment(\.mmTheme) var theme
    @State private var hovering = false

    var body: some View {
        let selected = session.openThreadID == thread.id
        let mentions = thread.unreadMentions ?? 0
        Button { session.openThread(rootID: thread.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                Avatar(userID: thread.post.userId, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.author(of: thread.post)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if let ch = session.channels[thread.post.channelId] {
                            Text("in \(session.title(for: ch))").font(.system(size: 12)).foregroundColor(theme.centerTextDim).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(relativeTime(thread.date)).font(.system(size: 11)).foregroundColor(theme.centerTextDim)
                    }
                    Text(MessageRenderer.inline(thread.post.message.replacingOccurrences(of: "\n", with: "  "), context: session.renderContext))
                        .font(.system(size: 13))
                        .foregroundColor(thread.isUnread ? theme.centerText : theme.centerTextDim)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        participants
                        Text(replyLabel).font(.system(size: 12, weight: thread.isUnread ? .semibold : .regular))
                            .foregroundColor(thread.isUnread ? theme.link : theme.centerTextDim)
                        if mentions > 0 {
                            Text("\(mentions)")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(theme.dnd))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.hoverBg : (hovering ? theme.hoverBg.opacity(0.6) : .clear))
            .overlay(alignment: .leading) {
                Rectangle().fill(thread.isUnread ? theme.link : .clear).frame(width: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var replyLabel: String {
        let n = thread.replyCount ?? 0
        if let unread = thread.unreadReplies, unread > 0 { return "\(unread) new \(unread == 1 ? "reply" : "replies")" }
        return "\(n) \(n == 1 ? "reply" : "replies")"
    }

    private var participants: some View {
        HStack(spacing: -6) {
            ForEach((thread.participants ?? []).prefix(5), id: \.id) { p in
                Avatar(userID: p.id, size: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.centerBg, lineWidth: 1.5))
            }
        }
    }
}

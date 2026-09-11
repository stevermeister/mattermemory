import SwiftUI

struct ThreadPanel: View {
    @ObservedObject var session: ServerSession
    let rootID: String
    @Environment(\.mmTheme) var theme
    @State private var editing: MMPost?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Thread").font(.system(size: 15, weight: .semibold))
                if let root = session.threads[rootID]?.first, let ch = session.channels[root.channelId] {
                    Text(session.title(for: ch)).font(.system(size: 12)).foregroundColor(theme.centerTextDim).lineLimit(1)
                }
                Spacer()
                Button { session.openThreadID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14).frame(height: 52)
            Divider()
            if let root = session.threads[rootID]?.first {
                MessageList(session: session, channelID: root.channelId, rootID: rootID, onEdit: { editing = $0 })
                Composer(session: session, rootID: rootID, editing: $editing)
            } else {
                Spacer(); ProgressView(); Spacer()
            }
        }
        .background(theme.centerBg)
        .foregroundColor(theme.centerText)
    }
}

struct SearchPanel: View {
    @ObservedObject var session: ServerSession
    @Binding var isPresented: Bool
    @Environment(\.mmTheme) var theme
    @State private var terms = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(theme.centerTextDim)
                TextField("Search messages  (from:user in:channel \"phrase\")", text: $terms)
                    .textFieldStyle(.plain).focused($focused)
                    .onSubmit { Task { await session.search(terms) } }
                    .onExitCommand { close() }
                Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 14).frame(height: 52)
            Divider()
            if session.searching {
                Spacer(); ProgressView(); Text("Searching… (the server can take up to 30 s)").font(.system(size: 12)).foregroundColor(theme.centerTextDim).padding(.top, 8); Spacer()
            } else if let results = session.searchResults {
                if results.isEmpty {
                    Spacer(); Text("No results for “\(session.searchTerms)”").foregroundColor(theme.centerTextDim); Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { post in
                                Button { jump(to: post) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            if let ch = session.channels[post.channelId] { Text(session.title(for: ch)).font(.system(size: 11, weight: .semibold)).foregroundColor(theme.centerTextDim) }
                                            Spacer()
                                            Text(relativeDay(post.date) + " " + timeFormatter.string(from: post.date)).font(.system(size: 11)).foregroundColor(theme.centerTextDim)
                                        }
                                        PostRow(session: session, post: post, continuation: false, inThread: true, onEdit: { _ in })
                                    }
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
            } else {
                Spacer(); Text("Type a query and press Return").foregroundColor(theme.centerTextDim); Spacer()
            }
        }
        .background(theme.centerBg)
        .foregroundColor(theme.centerText)
        .onAppear {
            terms = session.searchTerms
            // The composer's NSTextView is first responder; ask for focus once the field exists.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommands.search)) { n in
            if (n.object as? UUID) == session.server.id { focused = true }
        }
    }

    private func close() {
        isPresented = false
        session.searchResults = nil
        NotificationCenter.default.post(name: NativeCommands.focusComposer, object: session.server.id)
    }

    private func jump(to post: MMPost) {
        let results = session.searchResults
        session.selectChannel(post.channelId)
        session.searchResults = results
        if let rid = post.rootId, !rid.isEmpty { session.openThread(rootID: rid) }
    }
}

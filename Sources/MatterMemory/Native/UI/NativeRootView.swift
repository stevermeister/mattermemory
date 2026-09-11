import SwiftUI

/// Root of the native mode for one server: login → loading → sidebar + channel (+ thread).
struct NativeRootView: View {
    @ObservedObject var session: ServerSession
    @Environment(\.colorScheme) var scheme
    @State private var showSwitcher = false
    @State private var showSearch = false
    var onOpenWebView: () -> Void

    var body: some View {
        let theme = MMTheme.current(scheme)
        Group {
            switch session.state {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to \(session.server.name)…").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.centerBg)
            case .needsLogin(let message):
                LoginView(session: session, message: message, onOpenWebView: onOpenWebView)
            case .error(let message):
                VStack(spacing: 12) {
                    Text("Can't reach \(session.server.name)").font(.title3.weight(.semibold))
                    Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Text("Retrying automatically…").font(.caption).foregroundColor(.secondary)
                    HStack {
                        Button("Retry now") { session.start() }.keyboardShortcut(.defaultAction)
                        Button("Open in web view") { onOpenWebView() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.centerBg)
            case .ready:
                HStack(spacing: 0) {
                    SidebarView(session: session, showSwitcher: $showSwitcher)
                        .frame(width: 240)
                    Divider()
                    ChannelView(session: session, showSearch: $showSearch, onOpenWebView: onOpenWebView)
                    if let rootID = session.openThreadID {
                        Divider()
                        ThreadPanel(session: session, rootID: rootID).frame(width: 380)
                    } else if showSearch || session.searchResults != nil {
                        Divider()
                        SearchPanel(session: session, isPresented: $showSearch).frame(width: 380)
                    }
                }
                .ignoresSafeArea(.container, edges: .top)   // the sidebar header runs under the (transparent) title bar
                .overlay {
                    if showSwitcher { ChannelSwitcher(session: session, isPresented: $showSwitcher) }
                }
                .overlay(alignment: .top) {
                    if let err = session.lastError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err).lineLimit(2)
                            Spacer()
                            Button { session.lastError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                        }
                        .font(.system(size: 12))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.dnd))
                        .foregroundColor(.white)
                        .padding(.top, 8).padding(.horizontal, 260)
                        .task(id: err) { try? await Task.sleep(nanoseconds: 8_000_000_000); if session.lastError == err { session.lastError = nil } }
                    }
                }
            }
        }
        .environmentObject(session)
        .environmentObject(ChromeState.shared)
        .environment(\.mmTheme, theme)
        .onReceive(NotificationCenter.default.publisher(for: NativeCommands.switcher)) { n in
            guard (n.object as? UUID) == session.server.id, session.state == .ready else { return }
            showSwitcher.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommands.search)) { n in
            guard (n.object as? UUID) == session.server.id, session.state == .ready else { return }
            showSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommands.escape)) { n in
            guard (n.object as? UUID) == session.server.id else { return }
            if showSwitcher { showSwitcher = false }
            else if session.openThreadID != nil { session.openThreadID = nil }
            else if showSearch || session.searchResults != nil { showSearch = false; session.searchResults = nil }
            NotificationCenter.default.post(name: NativeCommands.focusComposer, object: session.server.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: NativeCommands.channelStep)) { n in
            guard let step = n.object as? ChannelStep, step.serverID == session.server.id else { return }
            session.stepChannel(delta: step.delta, unreadOnly: step.unreadOnly)
        }
    }
}

/// What the AppKit shell is showing around the native view (SwiftUI adapts its header to it).
@MainActor
final class ChromeState: ObservableObject {
    static let shared = ChromeState()
    /// False when the server tab bar is hidden; the sidebar then leaves room for the traffic lights.
    @Published var tabBarVisible = true
}

/// AppKit → SwiftUI commands (menu items, ⌘K interception).
enum NativeCommands {
    static let switcher = Notification.Name("MatterMemory.Native.Switcher")
    static let search = Notification.Name("MatterMemory.Native.Search")
    static let focusComposer = Notification.Name("MatterMemory.Native.FocusComposer")
    static let debugDump = Notification.Name("MatterMemory.Native.DebugDump")
    static let escape = Notification.Name("MatterMemory.Native.Escape")
    static let channelStep = Notification.Name("MatterMemory.Native.ChannelStep")
}

struct ChannelStep {
    let serverID: UUID
    let delta: Int
    let unreadOnly: Bool
}

struct LoginView: View {
    @ObservedObject var session: ServerSession
    let message: String?
    var onOpenWebView: () -> Void
    @Environment(\.mmTheme) var theme
    @State private var loginId = ""
    @State private var password = ""
    @State private var mfa = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Log in to \(session.server.name)").font(.title2.weight(.semibold))
            Text(session.server.url.absoluteString).foregroundColor(.secondary).font(.callout)
            if let message { Text(message).foregroundColor(theme.dnd).font(.callout) }
            TextField("Email or username", text: $loginId).textFieldStyle(.roundedBorder).frame(width: 300)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder).frame(width: 300)
                .onSubmit(submit)
            TextField("MFA code (if enabled)", text: $mfa).textFieldStyle(.roundedBorder).frame(width: 300)
            Button("Log in", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(loginId.isEmpty || password.isEmpty)
            Divider().frame(width: 300).padding(.vertical, 4)
            Button("Log in with SSO / in the web view…") { onOpenWebView() }
                .buttonStyle(.link)
            Text("After a web login the native view picks the session up automatically.")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.centerBg)
    }

    private func submit() {
        guard !loginId.isEmpty, !password.isEmpty else { return }
        session.login(loginId: loginId, password: password, mfa: mfa)
    }
}

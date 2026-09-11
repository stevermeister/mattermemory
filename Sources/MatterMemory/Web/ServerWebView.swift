import AppKit
import WebKit

@MainActor
protocol ServerWebViewDelegate: AnyObject {
    func serverWebViewStateChanged(_ view: ServerWebView)
    func serverWebView(_ view: ServerWebView, requestNotification id: Int, title: String, body: String, silent: Bool)
    func serverWebView(_ view: ServerWebView, didFinishDownload url: URL)
}

/// One Mattermost server. Owns an optional WKWebView that is created on first
/// use and can be torn down while idle; everything the tab bar needs (unread
/// state, loading state, last URL) survives an unload.
@MainActor
final class ServerWebView: NSObject {
    nonisolated static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"

    private(set) var server: Server
    weak var delegate: ServerWebViewDelegate?

    /// Hosts the web view or the error overlay. Stays alive across unloads.
    let containerView = NSView()
    private(set) var webView: WKWebView?
    private var errorView: ErrorOverlayView?

    private(set) var mentionCount = 0
    private(set) var hasUnread = false
    private(set) var isLoading = false
    private(set) var lastActivity = Date()
    private var lastURL: URL?
    private var observations: [NSKeyValueObservation] = []
    private var popups: [PopupWindowController] = []
    private var downloads: [ObjectIdentifier: (WKDownload, URL)] = [:]

    var isLoaded: Bool { webView != nil }
    /// Lockdown setting the current web view was created with.
    private(set) var appliedLowMemoryMode = false
    var canGoBack: Bool { webView?.canGoBack ?? false }
    var canGoForward: Bool { webView?.canGoForward ?? false }
    var currentURL: URL? { webView?.url ?? lastURL }

    init(server: Server) {
        self.server = server
        super.init()
        containerView.autoresizingMask = [.width, .height]
    }


    func update(server: Server) {
        let urlChanged = self.server.url != server.url
        self.server = server
        if urlChanged, isLoaded { lastURL = nil; unload(); ensureLoaded() }
    }

    func touch() { lastActivity = Date() }

    // MARK: Lifecycle

    func ensureLoaded() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 12.3, *) { config.preferences.isElementFullscreenEnabled = true }
        appliedLowMemoryMode = Settings.lowMemoryMode
        if appliedLowMemoryMode { config.defaultWebpagePreferences.isLockdownModeEnabled = true }
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Scripts.notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        ucc.add(WeakScriptHandler(self), name: "mmNotify")
        config.userContentController = ucc

        let wv = WKWebView(frame: containerView.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.customUserAgent = Self.userAgent
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.pageZoom = Settings.pageZoom
        if #available(macOS 13.3, *) { wv.isInspectable = Settings.webInspectorEnabled }
        if #available(macOS 12.0, *) { wv.underPageBackgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1) }

        // WebKit delivers these on the main thread; the closures are typed as nonisolated.
        observations = [
            wv.observe(\.title, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.parseTitle(wv.title) }
            },
            wv.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLoading = wv.isLoading
                    self.delegate?.serverWebViewStateChanged(self)
                }
            },
            wv.observe(\.url, options: [.new]) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let u = wv.url, u.scheme?.hasPrefix("http") == true { self.lastURL = u }
                    self.delegate?.serverWebViewStateChanged(self)
                }
            },
        ]

        hideError()
        containerView.addSubview(wv)
        webView = wv
        wv.load(URLRequest(url: lastURL ?? server.url))
        touch()
        delegate?.serverWebViewStateChanged(self)
    }

    /// Tears the WKWebView down. WebKit terminates the content process once
    /// nothing references it, which returns the memory to the system.
    func unload() {
        guard let wv = webView else { return }
        lastURL = wv.url ?? lastURL
        observations.removeAll()
        wv.stopLoading()
        wv.configuration.userContentController.removeAllUserScripts()
        wv.configuration.userContentController.removeScriptMessageHandler(forName: "mmNotify")
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        wv.removeFromSuperview()
        webView = nil
        isLoading = false
        popups.forEach { $0.close() }
        popups.removeAll()
        delegate?.serverWebViewStateChanged(self)
    }

    func reload(ignoringCache: Bool = false) {
        guard let wv = webView else { ensureLoaded(); return }
        hideError()
        if wv.url == nil { wv.load(URLRequest(url: lastURL ?? server.url)); return }
        if ignoringCache { wv.reloadFromOrigin() } else { wv.reload() }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func navigate(to url: URL) {
        lastURL = url
        if let wv = webView { wv.load(URLRequest(url: url)) } else { ensureLoaded() }
    }

    func setZoom(_ zoom: Double) { webView?.pageZoom = zoom }

    func setInspectable(_ on: Bool) {
        if #available(macOS 13.3, *) { webView?.isInspectable = on }
    }

    func handleNotificationClick(id: Int) {
        ensureLoaded()
        webView?.evaluateJavaScript("window.__mmNotificationClicked && window.__mmNotificationClicked(\(id));", completionHandler: nil)
    }

    /// Counts discovered by the background REST poller while unloaded.
    func setBackgroundCounts(mentions: Int, unread: Bool) {
        guard !isLoaded else { return }
        guard mentions != mentionCount || unread != hasUnread else { return }
        mentionCount = mentions
        hasUnread = unread
        delegate?.serverWebViewStateChanged(self)
    }

    // MARK: Title → unread state
    // The webapp writes "(3) * channel - team siteName" in browser mode.

    private func parseTitle(_ title: String?) {
        guard let title else { return }
        var rest = Substring(title)
        var mentions = 0
        if rest.hasPrefix("("), let close = rest.firstIndex(of: ")"),
           let n = Int(rest[rest.index(after: rest.startIndex)..<close]) {
            mentions = n
            rest = rest[rest.index(after: close)...].drop { $0 == " " }
        }
        let unread = rest.hasPrefix("*")
        guard mentions != mentionCount || unread != hasUnread else { return }
        mentionCount = mentions
        hasUnread = unread
        delegate?.serverWebViewStateChanged(self)
    }

    // MARK: Errors

    private func showError(_ error: Error) {
        let ev = errorView ?? ErrorOverlayView(frame: containerView.bounds)
        ev.autoresizingMask = [.width, .height]
        ev.frame = containerView.bounds
        ev.onRetry = { [weak self] in self?.reload() }
        ev.show(server: server, error: error)
        if ev.superview == nil { containerView.addSubview(ev, positioned: .above, relativeTo: webView) }
        errorView = ev
    }

    private func hideError() {
        errorView?.removeFromSuperview()
        errorView = nil
    }

    private func isInternal(_ url: URL?) -> Bool { server.owns(url) }
}

// MARK: - Script messages

extension ServerWebView: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mmNotify", let dict = message.body as? [String: Any],
              let id = dict["id"] as? Int else { return }
        delegate?.serverWebView(self,
                                requestNotification: id,
                                title: dict["title"] as? String ?? server.name,
                                body: dict["body"] as? String ?? "",
                                silent: dict["silent"] as? Bool ?? false)
    }
}

/// WKUserContentController retains its handlers; this proxy breaks the cycle.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

// MARK: - Navigation

extension ServerWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        let webScheme = ["http", "https", "about", "blob", "data", "javascript"].contains(scheme)
        if !webScheme {
            // mailto:, tel:, zoommtg:, etc. belong to other apps.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if navigationAction.navigationType == .linkActivated, isMainFrame, scheme.hasPrefix("http"),
           !isInternal(url), isInternal(webView.url) {
            // Link out of the server from a server page → default browser.
            // Redirect chains (SSO) are not link clicks and stay in the view.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType { decisionHandler(.download); return }
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           let cd = http.value(forHTTPHeaderField: "Content-Disposition"),
           cd.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hideError()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error, in: webView)
    }

    private func handle(_ error: Error, in webView: WKWebView) {
        let ns = error as NSError
        // -999 cancelled, 102 frame load interrupted by policy (downloads / external links)
        if ns.code == NSURLErrorCancelled || (ns.domain == "WebKitErrorDomain" && ns.code == 102) { return }
        showError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Content process was killed (jetsam or crash): reload lazily on next activation.
        showError(NSError(domain: "MatterMemory", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The page process was terminated to free memory."]))
    }
}

// MARK: - UI delegate (popups, dialogs, file pickers, media)

extension ServerWebView: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        let isBlank = url == nil || url?.absoluteString.isEmpty == true || url?.scheme == "about"
        if isBlank {
            // OAuth-style popup: opened blank, navigated by script, closed by script.
            let popup = PopupWindowController(configuration: configuration, userAgent: Self.userAgent)
            popup.onClose = { [weak self] p in self?.popups.removeAll { $0 === p } }
            popups.append(popup)
            return popup.webView
        }
        if let url, isInternal(url) {
            webView.load(URLRequest(url: url))
        } else if let url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = server.name
        a.informativeText = message
        a.addButton(withTitle: "OK")
        present(a, in: webView) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = server.name
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        present(a, in: webView) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert()
        a.messageText = server.name
        a.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        present(a, in: webView) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    private func present(_ alert: NSAlert, in webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let done: (NSApplication.ModalResponse) -> Void = { completionHandler($0 == .OK ? panel.urls : nil) }
        if let window = webView.window { panel.beginSheetModal(for: window, completionHandler: done) } else { done(panel.runModal()) }
    }

    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.lowercased() == server.host ? .grant : .prompt)
    }
}

// MARK: - Downloads (straight to ~/Downloads, no in-app downloads panel)

extension ServerWebView: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var dest = dir.appendingPathComponent(suggestedFilename)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            dest = dir.appendingPathComponent(name)
            n += 1
        }
        downloads[ObjectIdentifier(download)] = (download, dest)
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let (_, dest) = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        delegate?.serverWebView(self, didFinishDownload: dest)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        NSLog("Download failed: \(error.localizedDescription)")
    }
}

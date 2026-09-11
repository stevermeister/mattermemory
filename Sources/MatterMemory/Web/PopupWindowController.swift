import AppKit
import WebKit

/// Minimal window for `window.open` targets that must stay inside the app
/// (about:blank popups used by OAuth / plugin auth flows, in-server popouts).
final class PopupWindowController: NSWindowController, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    var onClose: ((PopupWindowController) -> Void)?

    init(configuration: WKWebViewConfiguration, userAgent: String) {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 860, height: 680), configuration: configuration)
        webView.customUserAgent = userAgent
        let window = NSWindow(contentRect: webView.frame,
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.contentView = webView
        window.title = "MatterMemory"
        window.center()
        super.init(window: window)
        window.delegate = self
        webView.uiDelegate = self
        webView.navigationDelegate = self
        window.makeKeyAndOrderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        onClose?(self)
    }

    func webViewDidClose(_ webView: WKWebView) { close() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let t = webView.title, !t.isEmpty { window?.title = t }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Popups exist for auth round-trips; let them go wherever the provider sends them.
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
}

import Foundation
import WebKit

/// Logs a server in without the login page: Mattermost accepts a personal
/// access token as the MMAUTHTOKEN cookie, so we drop it into WebKit's cookie
/// store and the web app comes up already authenticated. The token is never
/// written to disk by us; only WebKit's cookie jar keeps it.
enum SessionInjector {
    static func inject(token: String, for server: Server, completion: @escaping () -> Void) {
        guard let host = server.url.host, !token.isEmpty else { completion(); return }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: "MMAUTHTOKEN",
            .value: token,
            .domain: host,
            .path: "/",
            .expires: Date().addingTimeInterval(365 * 24 * 3600),
            HTTPCookiePropertyKey("HttpOnly"): true,
        ]
        if server.url.scheme?.lowercased() == "https" { props[.secure] = true }
        guard let cookie = HTTPCookie(properties: props) else { completion(); return }
        WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie, completionHandler: completion)
    }
}

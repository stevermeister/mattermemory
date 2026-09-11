import Foundation
import WebKit

/// Matterhorn-style lightweight API client: for servers whose web view has
/// been unloaded, ask the REST API for unread counts using the session
/// cookie WebKit already holds. One small GET per minute instead of a
/// full web page with a websocket.
final class UnreadPoller {
    struct Counts { var mentions: Int; var unread: Bool }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = ["User-Agent": ServerWebView.userAgent]
        return URLSession(configuration: cfg)
    }()

    /// Whether the user sees Collapsed Reply Threads on a server. With CRT the
    /// web app counts only root posts (thread replies live in the Threads view),
    /// so we must read the *_root counters or we over-report. Cached for an hour.
    private var crtCache: [UUID: (crt: Bool, at: Date)] = [:]

    func poll(_ server: Server, completion: @escaping (Counts?) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let mine = cookies.filter { server.url.host?.lowercased().hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()) == true }
            guard mine.contains(where: { $0.name == "MMAUTHTOKEN" }) else { completion(nil); return }
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: mine)
            self.collapsedThreads(server, cookies: cookieHeaders) { crt in
                self.get(server, path: "api/v4/users/me/teams/unread", cookies: cookieHeaders) { json in
                    guard let arr = json as? [[String: Any]] else { completion(nil); return }
                    var mentions = 0, unread = false
                    for team in arr {
                        func n(_ k: String) -> Int { team[k] as? Int ?? 0 }
                        if crt {
                            mentions += n("mention_count_root") + n("thread_mention_count")
                            if n("msg_count_root") > 0 || n("thread_count") > 0 { unread = true }
                        } else {
                            mentions += n("mention_count")
                            if n("msg_count") > 0 { unread = true }
                        }
                    }
                    completion(Counts(mentions: mentions, unread: unread))
                }
            }
        }
    }

    private func collapsedThreads(_ server: Server, cookies: [String: String], completion: @escaping (Bool) -> Void) {
        if let c = crtCache[server.id], Date().timeIntervalSince(c.at) < 3600 { completion(c.crt); return }
        get(server, path: "api/v4/config/client?format=old", cookies: cookies) { json in
            let mode = (json as? [String: Any])?["CollapsedThreads"] as? String ?? "disabled"
            let done: (Bool) -> Void = { crt in self.crtCache[server.id] = (crt, Date()); completion(crt) }
            switch mode {
            case "always_on": done(true)
            case "disabled": done(false)
            default:
                // default_on / default_off: the user preference decides; 404 means "no preference set".
                self.get(server, path: "api/v4/users/me/preferences/display_settings", cookies: cookies) { json in
                    let prefs = json as? [[String: Any]] ?? []
                    if let p = prefs.first(where: { $0["name"] as? String == "collapsed_reply_threads" }), let v = p["value"] as? String {
                        done(v == "on")
                    } else {
                        done(mode == "default_on")
                    }
                }
            }
        }
    }

    private func get(_ server: Server, path: String, cookies: [String: String], completion: @escaping (Any?) -> Void) {
        guard let url = URL(string: path, relativeTo: server.url.appendingPathComponent("/")) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        for (k, v) in cookies { req.setValue(v, forHTTPHeaderField: k) }
        session.dataTask(with: req) { data, resp, _ in
            var json: Any?
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let data { json = try? JSONSerialization.jsonObject(with: data) }
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }
}

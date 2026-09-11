import Foundation

struct MMWSEvent {
    let event: String
    let data: [String: JSONValue]
    let broadcast: [String: JSONValue]

    var channelID: String? { broadcast["channel_id"]?.string ?? data["channel_id"]?.string }
    var teamID: String? { broadcast["team_id"]?.string }
    var userID: String? { broadcast["user_id"]?.string ?? data["user_id"]?.string }

    /// Many payloads carry a JSON document encoded as a string (post, mentions, …).
    func json<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let s = data[key]?.string, let d = s.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try? dec.decode(T.self, from: d)
    }
}

/// Mattermost websocket with auth challenge, ping and exponential reconnect.
/// Everything is delivered on the main queue.
final class MMWebSocket: NSObject, URLSessionWebSocketDelegate {
    var onEvent: ((MMWSEvent) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    private(set) var isConnected = false

    private let url: URL
    private let token: String
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var seq = 1
    private var backoff: TimeInterval = 1
    private var stopped = false
    private var pingTimer: Timer?

    init(baseURL: URL, token: String) {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v4/websocket"), resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "http" ? "ws" : "wss"
        url = comps.url!
        self.token = token
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }

    func connect() {
        stopped = false
        var req = URLRequest(url: url)
        req.setValue(ServerWebView.userAgent, forHTTPHeaderField: "User-Agent")
        let t = session.webSocketTask(with: req)
        task = t
        t.resume()
        receive(on: t)
    }

    func disconnect() {
        stopped = true
        pingTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setConnected(false)
    }

    func send(action: String, data: [String: Any]) {
        seq += 1
        let msg: [String: Any] = ["seq": seq, "action": action, "data": data]
        guard let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        send(action: "authentication_challenge", data: ["token": token])
        backoff = 1
        setConnected(true)
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.task?.sendPing { err in if err != nil { self?.reconnectLater() } }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        reconnectLater()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { reconnectLater() }
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self, self.task === t else { return }
            switch result {
            case .failure:
                self.reconnectLater()
            case .success(let msg):
                if case .string(let s) = msg { self.handle(s) }
                self.receive(on: t)
            }
        }
    }

    private func handle(_ text: String) {
        guard let d = text.data(using: .utf8),
              let obj = try? JSONDecoder().decode([String: JSONValue].self, from: d),
              let event = obj["event"]?.string else { return }
        onEvent?(MMWSEvent(event: event, data: obj["data"]?.object ?? [:], broadcast: obj["broadcast"]?.object ?? [:]))
    }

    private func reconnectLater() {
        guard !stopped else { return }
        let wasConnected = isConnected
        setConnected(false)
        pingTimer?.invalidate()
        task?.cancel()
        task = nil
        let delay = backoff
        backoff = min(backoff * 2, 60)
        if wasConnected { NSLog("WebSocket dropped, reconnecting in \(delay)s") }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped, self.task == nil else { return }
            self.connect()
        }
    }

    private func setConnected(_ c: Bool) {
        guard c != isConnected else { return }
        isConnected = c
        onConnectionChange?(c)
    }
}

import Foundation

enum MMError: LocalizedError {
    case http(Int, String)
    case unauthenticated
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return msg.isEmpty ? "HTTP \(code)" : "\(msg) (HTTP \(code))"
        case .unauthenticated: return "Not logged in"
        case .decoding(let what): return "Unexpected response for \(what)"
        }
    }
}

/// Thin async REST client for Mattermost API v4. One instance per server.
final class MMClient {
    let baseURL: URL
    var token: String?

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil            // token only; never let WebKit's cookies leak in
        cfg.timeoutIntervalForRequest = 30
        cfg.httpAdditionalHeaders = ["User-Agent": ServerWebView.userAgent, "X-Requested-With": "XMLHttpRequest"]
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
    }

    // MARK: Core

    func url(_ path: String, query: [String: String] = [:]) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v4/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return comps.url!
    }

    func request(_ method: String, _ path: String, query: [String: String] = [:], body: Any? = nil) -> URLRequest {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    @discardableResult
    func data(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw MMError.http(0, "no response") }
            if http.statusCode == 401 { throw MMError.unauthenticated }
            if (200..<300).contains(http.statusCode) { return (data, http) }
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
            // Transient server errors on reads: one retry after a short pause.
            if http.statusCode >= 500, req.httpMethod == "GET", attempt == 1 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                continue
            }
            throw MMError.http(http.statusCode, msg)
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await self.data(request("GET", path, query: query))
        do { return try decoder.decode(T.self, from: data) } catch { throw MMError.decoding("\(path): \(error)") }
    }

    func post<T: Decodable>(_ path: String, body: Any, query: [String: String] = [:], as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await self.data(request("POST", path, query: query, body: body))
        do { return try decoder.decode(T.self, from: data) } catch { throw MMError.decoding("\(path): \(error)") }
    }

    func send(_ method: String, _ path: String, body: Any? = nil) async throws {
        _ = try await data(request(method, path, body: body))
    }

    // MARK: Auth

    /// Username/password login. Returns the session token from the Token header.
    func login(loginId: String, password: String, mfaToken: String? = nil) async throws -> (token: String, user: MMUser) {
        var body: [String: Any] = ["login_id": loginId, "password": password]
        if let mfaToken, !mfaToken.isEmpty { body["token"] = mfaToken }
        let (data, http) = try await self.data(request("POST", "users/login", body: body))
        guard let token = http.value(forHTTPHeaderField: "Token") else { throw MMError.http(http.statusCode, "no session token") }
        let user = try decoder.decode(MMUser.self, from: data)
        return (token, user)
    }

    // MARK: Bootstrap

    func me() async throws -> MMUser { try await get("users/me") }
    func clientConfig() async throws -> MMClientConfig {
        let dict: [String: String] = try await get("config/client", query: ["format": "old"])
        return MMClientConfig(dict: dict)
    }
    func myTeams() async throws -> [MMTeam] { try await get("users/me/teams") }
    func myChannels(teamID: String) async throws -> [MMChannel] {
        try await get("users/me/teams/\(teamID)/channels", query: ["include_deleted": "false"])
    }
    func myChannelMembers(teamID: String) async throws -> [MMChannelMember] {
        try await get("users/me/teams/\(teamID)/channels/members")
    }
    func sidebarCategories(userID: String, teamID: String) async throws -> MMSidebarCategories {
        try await get("users/\(userID)/teams/\(teamID)/channels/categories")
    }
    func preferences() async throws -> [MMPreference] { try await get("users/me/preferences") }
    func teamsUnread() async throws -> [MMTeamUnread] { try await get("users/me/teams/unread") }
    func threadTotals(userID: String, teamID: String) async throws -> MMThreadTotals {
        try await get("users/\(userID)/teams/\(teamID)/threads", query: ["totalsOnly": "true", "per_page": "1"])
    }
    func customEmoji() async throws -> [MMEmoji] { try await get("emoji", query: ["per_page": "200", "sort": "name"]) }

    // MARK: Users

    func users(ids: [String]) async throws -> [MMUser] {
        guard !ids.isEmpty else { return [] }
        return try await post("users/ids", body: ids)
    }
    func statuses(ids: [String]) async throws -> [MMStatus] {
        guard !ids.isEmpty else { return [] }
        return try await post("users/status/ids", body: ids)
    }
    func autocompleteUsers(term: String, teamID: String, channelID: String?) async throws -> [MMUser] {
        struct R: Decodable { var users: [MMUser] }
        var q = ["name": term, "team_id": teamID, "limit": "20"]
        if let channelID { q["channel_id"] = channelID }
        let r: R = try await get("users/autocomplete", query: q)
        return r.users
    }

    // MARK: Posts

    func posts(channelID: String, before: String? = nil, perPage: Int = 60, crt: Bool) async throws -> MMPostList {
        var q = ["per_page": "\(perPage)", "collapsedThreads": crt ? "true" : "false", "collapsedThreadsExtended": "true"]
        if let before { q["before"] = before }
        return try await get("channels/\(channelID)/posts", query: q)
    }
    func postsSince(channelID: String, since: Int64, crt: Bool) async throws -> MMPostList {
        try await get("channels/\(channelID)/posts", query: ["since": "\(since)", "collapsedThreads": crt ? "true" : "false"])
    }
    func thread(rootID: String, crt: Bool) async throws -> MMPostList {
        try await get("posts/\(rootID)/thread", query: ["collapsedThreads": crt ? "true" : "false", "collapsedThreadsExtended": "true", "direction": "down", "perPage": "200"])
    }
    func createPost(channelID: String, message: String, rootID: String? = nil, fileIDs: [String] = []) async throws -> MMPost {
        var body: [String: Any] = ["channel_id": channelID, "message": message]
        if let rootID { body["root_id"] = rootID }
        if !fileIDs.isEmpty { body["file_ids"] = fileIDs }
        return try await post("posts", body: body)
    }
    func editPost(id: String, message: String) async throws -> MMPost {
        let (data, _) = try await self.data(request("PUT", "posts/\(id)/patch", body: ["message": message]))
        return try decoder.decode(MMPost.self, from: data)
    }
    func deletePost(id: String) async throws { try await send("DELETE", "posts/\(id)") }
    func viewChannel(channelID: String, prev: String?) async throws {
        var body: [String: Any] = ["channel_id": channelID]
        if let prev { body["prev_channel_id"] = prev }
        try await send("POST", "channels/members/me/view", body: body)
    }
    func addReaction(userID: String, postID: String, emoji: String) async throws {
        try await send("POST", "reactions", body: ["user_id": userID, "post_id": postID, "emoji_name": emoji])
    }
    func removeReaction(userID: String, postID: String, emoji: String) async throws {
        try await send("DELETE", "users/\(userID)/posts/\(postID)/reactions/\(emoji)")
    }
    func search(teamID: String, terms: String) async throws -> MMPostList {
        // Server-side search can take 20-30 s on a database-backed index; give it time.
        var req = request("POST", "teams/\(teamID)/posts/search", body: ["terms": terms, "is_or_search": false, "page": 0, "per_page": 25])
        req.timeoutInterval = 120
        let (data, _) = try await self.data(req)
        return try decoder.decode(MMPostList.self, from: data)
    }
    func markThreadRead(userID: String, teamID: String, threadID: String) async throws {
        try await send("PUT", "users/\(userID)/teams/\(teamID)/threads/\(threadID)/read/\(Int64(Date().timeIntervalSince1970 * 1000))")
    }

    // MARK: Channels

    func channel(id: String) async throws -> MMChannel { try await get("channels/\(id)") }
    func channelMember(channelID: String) async throws -> MMChannelMember { try await get("channels/\(channelID)/members/me") }
    func createDirectChannel(me: String, other: String) async throws -> MMChannel { try await post("channels/direct", body: [me, other]) }
    func joinableChannels(teamID: String, term: String) async throws -> [MMChannel] {
        try await post("teams/\(teamID)/channels/search", body: ["term": term])
    }
    func joinChannel(channelID: String, userID: String) async throws {
        try await send("POST", "channels/\(channelID)/members", body: ["user_id": userID])
    }

    // MARK: Files

    func uploadFile(channelID: String, fileURL: URL) async throws -> MMFileInfo {
        struct R: Decodable { var fileInfos: [MMFileInfo] }
        let boundary = "MatterMemory-\(UUID().uuidString)"
        var req = request("POST", "files", query: ["channel_id": channelID, "filename": fileURL.lastPathComponent])
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, _) = try await self.data(req)
        let r = try decoder.decode(R.self, from: data)
        guard let info = r.fileInfos.first else { throw MMError.decoding("files") }
        return info
    }

    /// Raw bytes behind an authenticated URL (avatars, thumbnails, downloads).
    func bytes(_ path: String, query: [String: String] = [:]) async throws -> Data {
        try await data(request("GET", path, query: query)).0
    }
}

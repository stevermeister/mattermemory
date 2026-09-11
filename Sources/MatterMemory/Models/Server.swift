import Foundation

struct Server: Codable, Equatable {
    var id: UUID
    var name: String
    var url: URL

    init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }

    var host: String { url.host?.lowercased() ?? "" }

    /// True when `other` belongs to this server (same host and port).
    func owns(_ other: URL?) -> Bool {
        guard let other, let h = other.host?.lowercased() else { return false }
        return h == host && (other.port ?? defaultPort(other)) == (url.port ?? defaultPort(url))
    }

    private func defaultPort(_ u: URL) -> Int { u.scheme?.lowercased() == "http" ? 80 : 443 }

    /// Accepts "chat.example.com", "http://chat.example.com:8065/sub" etc.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard var comps = URLComponents(string: s),
              let host = comps.host, !host.isEmpty,
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        comps.query = nil
        comps.fragment = nil
        while comps.path.hasSuffix("/") { comps.path.removeLast() }
        if comps.path.lowercased().hasSuffix("/api/v4") { comps.path.removeLast(7) }   // people paste API base URLs
        return comps.url
    }
}

enum AppPaths {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MatterMemory", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

/// Persists the server list as a tiny JSON file. No database, no migrations.
final class ServerStore {
    static let shared = ServerStore()
    static let changed = Notification.Name("MatterMemory.ServerStoreChanged")

    private(set) var servers: [Server] = []
    private let fileURL = AppPaths.supportDir.appendingPathComponent("servers.json")

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Server].self, from: data) else { return }
        servers = list
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(servers) {
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    func server(id: UUID) -> Server? { servers.first { $0.id == id } }
    func index(of id: UUID) -> Int? { servers.firstIndex { $0.id == id } }

    func add(_ s: Server) { servers.append(s); save() }

    func update(_ s: Server) {
        guard let i = index(of: s.id) else { return }
        servers[i] = s
        save()
    }

    func remove(id: UUID) {
        servers.removeAll { $0.id == id }
        save()
    }

    func move(id: UUID, by delta: Int) {
        guard let i = index(of: id) else { return }
        let j = i + delta
        guard j >= 0, j < servers.count else { return }
        servers.swapAt(i, j)
        save()
    }

    /// Server whose host matches the URL, if any.
    func server(for url: URL) -> Server? { servers.first { $0.owns(url) } }
}

import Foundation

/// Loose JSON for `props`, `notify_props` and other free-form fields.
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? {
        switch self { case .bool(let b): return b; case .string(let s): return s == "true"; default: return nil }
    }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    subscript(key: String) -> JSONValue? { object?[key] }
}

struct MMUser: Codable, Identifiable, Equatable {
    let id: String
    var username: String
    var firstName: String?
    var lastName: String?
    var nickname: String?
    var email: String?
    var lastPictureUpdate: Int64?
    var isBot: Bool?
    var notifyProps: [String: JSONValue]?
    var props: [String: JSONValue]?
    var deleteAt: Int64?

    func displayName(format: String) -> String {
        let full = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        switch format {
        case "nickname_full_name":
            if let n = nickname, !n.isEmpty { return n }
            return full.isEmpty ? username : full
        case "full_name":
            return full.isEmpty ? username : full
        default:
            return username
        }
    }
}

struct MMTeam: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var displayName: String
}

struct MMChannel: Codable, Identifiable, Equatable {
    let id: String
    var teamId: String
    var type: String            // O public, P private, D direct, G group
    var displayName: String
    var name: String
    var header: String?
    var purpose: String?
    var lastPostAt: Int64?
    var totalMsgCount: Int64?
    var totalMsgCountRoot: Int64?
    var deleteAt: Int64?

    var isDirect: Bool { type == "D" }
    var isGroup: Bool { type == "G" }
    var isPrivate: Bool { type == "P" }

    /// For DMs the name is "<id1>__<id2>"; the other participant is the one that isn't me.
    func otherUserID(me: String) -> String? {
        guard isDirect else { return nil }
        let parts = name.components(separatedBy: "__")
        return parts.first { $0 != me } ?? parts.first
    }
}

struct MMChannelMember: Codable, Equatable {
    let channelId: String
    var userId: String
    var msgCount: Int64?
    var msgCountRoot: Int64?
    var mentionCount: Int64?
    var mentionCountRoot: Int64?
    var lastViewedAt: Int64?
    var notifyProps: [String: JSONValue]?

    var isMuted: Bool { notifyProps?["mark_unread"]?.string == "mention" }
    var desktopSetting: String { notifyProps?["desktop"]?.string ?? "default" }
}

struct MMSidebarCategory: Codable, Identifiable, Equatable {
    let id: String
    var type: String            // favorites, channels, direct_messages, custom
    var displayName: String
    var sorting: String?
    var collapsed: Bool?
    var channelIds: [String]
}

struct MMSidebarCategories: Codable {
    var categories: [MMSidebarCategory]
    var order: [String]
}

struct MMFileInfo: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var `extension`: String?
    var size: Int64?
    var mimeType: String?
    var width: Int?
    var height: Int?
    var hasPreviewImage: Bool?

    var isImage: Bool { (mimeType ?? "").hasPrefix("image/") }
}

struct MMReaction: Codable, Equatable {
    var userId: String
    var postId: String
    var emojiName: String
}

struct MMPostMetadata: Codable, Equatable {
    var files: [MMFileInfo]?
    var reactions: [MMReaction]?
}

struct MMPost: Codable, Identifiable, Equatable {
    let id: String
    var createAt: Int64
    var updateAt: Int64?
    var editAt: Int64?
    var deleteAt: Int64?
    var userId: String
    var channelId: String
    var rootId: String?
    var message: String
    var type: String?
    var props: [String: JSONValue]?
    var metadata: MMPostMetadata?
    var replyCount: Int?
    var lastReplyAt: Int64?
    var participants: [MMUser]?

    var isReply: Bool { !(rootId ?? "").isEmpty }
    var isSystem: Bool { (type ?? "").hasPrefix("system_") }
    var overrideUsername: String? { props?["override_username"]?.string }
    var fromWebhook: Bool { props?["from_webhook"]?.bool ?? false }
    var attachments: [JSONValue] { props?["attachments"]?.array ?? [] }
    var date: Date { Date(timeIntervalSince1970: Double(createAt) / 1000) }
}

struct MMPostList: Codable {
    var order: [String]
    var posts: [String: MMPost]
    var nextPostId: String?
    var prevPostId: String?
    var hasNext: Bool?
}

struct MMPreference: Codable, Equatable {
    var userId: String
    var category: String
    var name: String
    var value: String
}

struct MMStatus: Codable, Equatable {
    var userId: String
    var status: String          // online, away, dnd, offline
}

struct MMTeamUnread: Codable {
    var teamId: String
    var msgCount: Int64?
    var mentionCount: Int64?
    var msgCountRoot: Int64?
    var mentionCountRoot: Int64?
    var threadCount: Int64?
    var threadMentionCount: Int64?
}

struct MMThreadTotals: Codable {
    var total: Int64?
    var totalUnreadThreads: Int64?
    var totalUnreadMentions: Int64?
}

struct MMEmoji: Codable, Identifiable, Equatable {
    let id: String
    var name: String
}

struct MMClientConfig {
    var siteName: String
    var teammateNameDisplay: String
    var collapsedThreads: String   // disabled, default_off, default_on, always_on
    var enableCustomEmoji: Bool
    var version: String

    init(dict: [String: String]) {
        siteName = dict["SiteName"] ?? "Mattermost"
        teammateNameDisplay = dict["TeammateNameDisplay"] ?? "username"
        collapsedThreads = dict["CollapsedThreads"] ?? "disabled"
        enableCustomEmoji = dict["EnableCustomEmoji"] == "true"
        version = dict["Version"] ?? ""
    }
}

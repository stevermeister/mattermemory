import Foundation

/// Fabricated content for `MM_DEMO=1`, used to produce documentation screenshots and to
/// work on the UI without a server. Everything here is invented; nothing touches the network.
enum DemoData {
    static let teamID = "demo-team"
    static let serverName = "Acme"

    static let users: [MMUser] = [
        user("u-me", "alice", "Alice", "Nguyen"),
        user("u-bob", "bob", "Bob", "Martins"),
        user("u-carol", "carol", "Carol", "Diaz"),
        user("u-dave", "dave", "Dave", "Okafor"),
        user("u-erin", "erin", "Erin", "Kowalski"),
        user("u-ci", "buildbot", "Build", "Bot", bot: true),
    ]

    private static func user(_ id: String, _ username: String, _ first: String, _ last: String, bot: Bool = false) -> MMUser {
        MMUser(id: id, username: username, firstName: first, lastName: last, nickname: nil, email: nil,
               lastPictureUpdate: nil, isBot: bot, notifyProps: nil, props: nil, deleteAt: 0)
    }

    static let statuses = ["u-me": "online", "u-bob": "online", "u-carol": "away",
                           "u-dave": "online", "u-erin": "dnd", "u-ci": "online"]

    static let channels: [MMChannel] = [
        channel("c-general", "O", "General", "general", header: "Everything and nothing in particular"),
        channel("c-dev", "P", "Engineering", "engineering"),
        channel("c-deploy", "O", "Deploys", "deploys"),
        channel("c-design", "O", "Design", "design"),
        channel("c-dm-bob", "D", "", "u-me__u-bob"),
        channel("c-dm-carol", "D", "", "u-me__u-carol"),
        channel("c-dm-erin", "D", "", "u-me__u-erin"),
    ]

    private static func channel(_ id: String, _ type: String, _ display: String, _ name: String, header: String? = nil) -> MMChannel {
        MMChannel(id: id, teamId: type == "D" ? "" : teamID, type: type, displayName: display, name: name,
                  header: header, purpose: nil, lastPostAt: now, totalMsgCount: 40, totalMsgCountRoot: 40, deleteAt: 0)
    }

    /// Unread counts per channel: (unread messages, mentions).
    static let unread: [String: (Int64, Int64)] = [
        "c-dm-bob": (3, 2), "c-general": (5, 0), "c-dm-erin": (1, 1),
    ]

    private static let now = Int64(Date().timeIntervalSince1970 * 1000)
    private static func minutesAgo(_ m: Int) -> Int64 { now - Int64(m) * 60_000 }

    static func posts(in channelID: String) -> [MMPost] {
        guard channelID == "c-general" else { return [] }
        return [
            post("p1", "u-carol", minutesAgo(224), """
                 Morning! The 4.4 release notes are drafted — **review welcome** before we publish:

                 - Import retries no longer duplicate rows
                 - List counts say what they are counting
                 - Alerts clear only on a real recovery
                 """, replies: 3, reactions: [("eyes", ["u-me", "u-dave"]), ("tada", ["u-bob"])]),
            post("p2", "u-dave", minutesAgo(96), "Anyone else seeing the flaky test in `parseTimestamps`? It passes locally and fails in CI about one run in five."),
            post("p3", "u-me", minutesAgo(92), "Yes — it reads the system clock. Pinned it to a fixed date:\n```swift\nlet clock = Date(timeIntervalSince1970: 1_700_000_000)\n```", reactions: [("+1", ["u-dave", "u-carol", "u-erin"])]),
            post("p4", "u-ci", minutesAgo(88), "Build **#2841** passed on `main` — 412 tests, 0 failures.", webhook: true),
            post("p5", "u-bob", minutesAgo(41), "@alice can you take a look at the sidebar spacing before we cut the release? It's off by a couple of points on the unread rows.", replies: 2, reactions: [("rocket", ["u-me"])]),
            post("p6", "u-erin", minutesAgo(12), "Design review moved to 15:00 — same link. Bring the new empty states 🙂", reactions: [("heart", ["u-carol", "u-bob"]), ("clap", ["u-dave"])]),
        ]
    }

    private static func post(_ id: String, _ user: String, _ at: Int64, _ message: String,
                             replies: Int = 0, reactions: [(String, [String])] = [], webhook: Bool = false) -> MMPost {
        var p = MMPost(id: id, createAt: at, updateAt: at, editAt: 0, deleteAt: 0, userId: user, channelId: "c-general",
                       rootId: "", message: message, type: "", props: webhook ? ["from_webhook": .string("true")] : nil,
                       metadata: nil, replyCount: replies, lastReplyAt: replies > 0 ? at + 600_000 : nil, participants: nil)
        if !reactions.isEmpty {
            p.metadata = MMPostMetadata(files: nil, reactions: reactions.flatMap { emoji, users in
                users.map { MMReaction(userId: $0, postId: id, emojiName: emoji) }
            })
        }
        return p
    }
}

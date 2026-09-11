import AppKit
import SwiftUI

/// Block-level structure of a Mattermost message. Inline formatting inside a
/// block is handled by Foundation's markdown parser; blocks are laid out as
/// separate SwiftUI views because `Text` cannot render lists, quotes or code.
indirect enum MessageBlock: Identifiable, Equatable {
    case paragraph(AttributedString)
    case heading(AttributedString, Int)
    case code(String, String?)
    case quote([MessageBlock])
    case list([AttributedString], ordered: Bool)
    case table([[AttributedString]])
    case rule

    var id: String {
        switch self {
        case .paragraph(let a): return "p" + String(a.characters.prefix(40)) + "\(a.characters.count)"
        case .heading(let a, let l): return "h\(l)" + String(a.characters)
        case .code(let s, _): return "c" + String(s.prefix(60)) + "\(s.count)"
        case .quote(let b): return "q" + b.map(\.id).joined()
        case .list(let items, let o): return "l\(o)" + items.map { String($0.characters.prefix(20)) }.joined()
        case .table(let rows): return "t\(rows.count)" + (rows.first?.map { String($0.characters) }.joined() ?? "")
        case .rule: return "hr"
        }
    }
}

struct RenderContext {
    var myUsername: String
    var customEmoji: Set<String>
    var displayNames: (String) -> String?     // username → display name (for @mentions)
}

enum MessageRenderer {
    static let mentionColor = Color(nsColor: NSColor(srgbRed: 0x1c / 255, green: 0x58 / 255, blue: 0xd9 / 255, alpha: 1))
    static let highlightBg = Color(nsColor: NSColor(srgbRed: 1, green: 0xd4 / 255, blue: 0x70 / 255, alpha: 0.6))
    private static let mentionRegex = try! NSRegularExpression(pattern: "(?<![\\w/])@([a-z0-9][a-z0-9._-]*)", options: [.caseInsensitive])
    private static let channelRegex = try! NSRegularExpression(pattern: "(?<![\\w/])~([a-z0-9][a-z0-9._-]*)")
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func blocks(for message: String, context: RenderContext) -> [MessageBlock] {
        parse(lines: message.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"), context: context)
    }

    private static func parse(lines: [String], context: RenderContext) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: "\n"), context: context)))
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flush()
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                blocks.append(.code(code.joined(separator: "\n"), lang.isEmpty ? nil : lang))
                i += 1
                continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                var quoted: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    if l.hasPrefix(" ") { l = l.dropFirst() }
                    quoted.append(String(l))
                    i += 1
                }
                blocks.append(.quote(parse(lines: quoted, context: context)))
                continue
            }
            if let (level, text) = heading(trimmed) {
                flush()
                blocks.append(.heading(inline(text, context: context), level))
                i += 1
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flush()
                blocks.append(.rule)
                i += 1
                continue
            }
            if let item = listItem(line) {
                flush()
                var items: [String] = []
                var ordered = item.ordered
                var current = item.text
                i += 1
                while i < lines.count {
                    if let next = listItem(lines[i]) { items.append(current); current = next.text; ordered = ordered || next.ordered; i += 1 }
                    else if lines[i].hasPrefix("  "), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { current += "\n" + lines[i].trimmingCharacters(in: .whitespaces); i += 1 }
                    else { break }
                }
                items.append(current)
                blocks.append(.list(items.map { inline($0, context: context) }, ordered: ordered))
                continue
            }
            if trimmed.hasPrefix("|"), i + 1 < lines.count, lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|"),
               lines[i + 1].contains("-") {
                flush()
                var rows: [[AttributedString]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let cells = lines[i].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                        .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if !cells.allSatisfy({ $0.allSatisfy { "-:".contains($0) } && !$0.isEmpty }) {
                        rows.append(cells.map { inline($0, context: context) })
                    }
                    i += 1
                }
                blocks.append(.table(rows))
                continue
            }
            if trimmed.isEmpty { flush() } else { paragraph.append(line) }
            i += 1
        }
        flush()
        return blocks
    }

    private static func heading(_ s: String) -> (Int, String)? {
        guard s.hasPrefix("#") else { return nil }
        let hashes = s.prefix { $0 == "#" }
        guard hashes.count <= 6, s.dropFirst(hashes.count).hasPrefix(" ") else { return nil }
        return (hashes.count, String(s.dropFirst(hashes.count + 1)))
    }

    private static func listItem(_ s: String) -> (text: String, ordered: Bool)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where t.hasPrefix(marker) {
            var body = String(t.dropFirst(2))
            if body.hasPrefix("[ ] ") { body = "☐ " + body.dropFirst(4) } else if body.lowercased().hasPrefix("[x] ") { body = "☑ " + body.dropFirst(4) }
            return (body, false)
        }
        if let dot = t.firstIndex(of: "."), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty, t[t.index(after: dot)...].hasPrefix(" ") {
            return (String(t[t.index(dot, offsetBy: 2)...]), true)
        }
        return nil
    }

    /// Inline markdown → AttributedString, plus emoji, @mentions, ~channels and bare URLs.
    static func inline(_ text: String, context: RenderContext) -> AttributedString {
        let withEmoji = Emoji.replaceShortcodes(in: text, custom: context.customEmoji)
        var attr: AttributedString
        do {
            attr = try AttributedString(markdown: withEmoji, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible))
        } catch {
            attr = AttributedString(withEmoji)
        }
        let plain = String(attr.characters)
        let ns = plain as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Existing markdown links are kept; bare URLs become links.
        if let detector {
            for m in detector.matches(in: plain, range: full) {
                guard let url = m.url, let r = Range(m.range, in: attr) else { continue }
                if attr[r].link == nil { attr[r].link = url; attr[r].foregroundColor = mentionColor }
            }
        }
        for m in mentionRegex.matches(in: plain, range: full) {
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
            guard let r = Range(m.range, in: attr) else { continue }
            let special = ["all", "channel", "here"].contains(name.lowercased())
            let isMe = name.lowercased() == context.myUsername.lowercased() || special
            attr[r].font = .system(size: 13, weight: .semibold)
            attr[r].foregroundColor = mentionColor
            if isMe { attr[r].backgroundColor = highlightBg }
            if !special, let display = context.displayNames(name) {
                attr.replaceSubrange(r, with: {
                    var s = AttributedString("@" + display)
                    s.font = .system(size: 13, weight: .semibold)
                    s.foregroundColor = mentionColor
                    if isMe { s.backgroundColor = highlightBg }
                    return s
                }())
            }
        }
        let plain2 = String(attr.characters)
        for m in channelRegex.matches(in: plain2, range: NSRange(location: 0, length: (plain2 as NSString).length)).reversed() {
            guard let r = Range(m.range, in: attr) else { continue }
            attr[r].foregroundColor = mentionColor
        }
        return attr
    }

    static func plainPreview(_ message: String) -> String {
        Emoji.replaceShortcodes(in: message).replacingOccurrences(of: "\n", with: " ")
    }
}

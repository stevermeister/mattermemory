import SwiftUI
import AppKit

/// Image fetched through the API client with the session token (avatars, thumbnails, custom emoji).
struct AuthImage<Placeholder: View>: View {
    @EnvironmentObject var session: ServerSession
    let path: String
    var query: [String: String] = [:]
    var maxPixels: CGFloat = 96
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable() } else { placeholder() }
        }
        .task(id: path) {
            if let cached = session.images.cached(path + (query.isEmpty ? "" : "?\(query)")) { image = cached; return }
            image = await session.images.image(path: path, query: query, maxPixels: maxPixels)
        }
    }
}

struct Avatar: View {
    @EnvironmentObject var session: ServerSession
    let userID: String
    var size: CGFloat = 32
    var showStatus = false

    var body: some View {
        let user = session.users[userID]
        ZStack(alignment: .bottomTrailing) {
            AuthImage(path: "users/\(userID)/image", query: ["_": "\(user?.lastPictureUpdate ?? 0)"], maxPixels: size) {
                Text(String((user?.username ?? "?").prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .frame(width: size, height: size)
                    .background(Color.gray.opacity(0.3))
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            if showStatus { StatusDot(status: session.status(of: userID), size: max(8, size * 0.32)) }
        }
    }
}

struct StatusDot: View {
    @Environment(\.mmTheme) var theme
    let status: String
    var size: CGFloat = 8
    var body: some View {
        let color: Color = { switch status { case "online": return theme.online; case "away": return theme.away; case "dnd": return theme.dnd; default: return .clear } }()
        Circle()
            .strokeBorder(theme.offline, lineWidth: status == "offline" ? 1.5 : 0)
            .background(Circle().fill(color))
            .frame(width: size, height: size)
    }
}

struct EmojiView: View {
    @EnvironmentObject var session: ServerSession
    let name: String
    var size: CGFloat = 16
    var body: some View {
        if let u = Emoji.unicode(name), session.customEmoji[name] == nil {
            Text(u).font(.system(size: size))
        } else if let id = session.customEmoji[name] {
            AuthImage(path: "emoji/\(id)/image", maxPixels: size) { Text(":\(name):").font(.system(size: size * 0.7)) }
                .frame(width: size, height: size)
        } else {
            Text(":\(name):").font(.system(size: size * 0.7))
        }
    }
}

/// Multi-line editor: Enter sends, Shift+Enter inserts a newline, Escape cancels, ↑ on empty edits last post.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSend: () -> Void
    var onEscape: () -> Void = {}
    var onUpArrowEmpty: () -> Void = {}
    var onTyping: () -> Void = {}
    var onDrop: ([URL]) -> Void = { _ in }
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var focusToken: Int = 0

    func makeNSView(context: Context) -> NSScrollView {
        let tv = DroppableTextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 13)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.drawsBackground = false
        tv.onDrop = onDrop
        tv.onHeightChange = onHeightChange
        tv.coordinator = context.coordinator
        tv.placeholder = placeholder
        let scroll = ComposerScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? DroppableTextView else { return }
        context.coordinator.parent = self
        if tv.string != text { tv.string = text; tv.needsDisplay = true; tv.invalidateIntrinsicContentSize(); tv.reportHeight() }
        tv.placeholder = placeholder
        tv.onHeightChange = onHeightChange
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?
        var lastFocusToken = -1
        private var lastTyping = Date.distantPast
        init(_ p: ComposerTextView) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            tv.needsDisplay = true
            if Date().timeIntervalSince(lastTyping) > 4 { lastTyping = Date(); parent.onTyping() }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { textView.insertNewlineIgnoringFieldEditor(nil); return true }
                parent.onSend()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.moveUp(_:)):
                if textView.string.isEmpty { parent.onUpArrowEmpty(); return true }
                return false
            default:
                return false
            }
        }
    }
}

/// Clicks anywhere inside the composer box focus the text view, even below the last line.
final class ComposerScrollView: NSScrollView {
    override func mouseDown(with event: NSEvent) {
        if let tv = documentView as? NSTextView, window?.firstResponder !== tv {
            window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
            return
        }
        super.mouseDown(with: event)
    }

    override func tile() {
        super.tile()
        // Keep the text view as tall as the visible area so it receives every click.
        if let tv = documentView as? NSTextView {
            tv.minSize = NSSize(width: 0, height: contentSize.height)
        }
    }
}

final class DroppableTextView: NSTextView {
    var onDrop: (([URL]) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    private var lastHeight: CGFloat = 0
    weak var coordinator: ComposerTextView.Coordinator?

    func reportHeight() {
        let h = intrinsicContentSize.height
        guard abs(h - lastHeight) > 0.5 else { return }
        lastHeight = h
        DispatchQueue.main.async { self.onHeightChange?(h) }
    }

    override func layout() {
        super.layout()
        reportHeight()
    }
    var placeholder = "" { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else { return super.intrinsicContentSize }
        lm.ensureLayout(for: tc)
        let h = lm.usedRect(for: tc).height + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: min(max(h, 36), 220))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
        reportHeight()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]
            (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: attrs)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty, urls.allSatisfy(\.isFileURL) {
            onDrop?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func paste(_ sender: Any?) {
        // File/image pastes become uploads; text pastes stay text.
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty, urls.allSatisfy(\.isFileURL), pb.string(forType: .string) == nil {
            onDrop?(urls); return
        }
        if pb.string(forType: .string) == nil, let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pasted-\(Int(Date().timeIntervalSince1970)).png")
            try? png.write(to: url)
            onDrop?([url]); return
        }
        pasteAsPlainText(sender)
    }
}

extension View {
    func onHoverBackground(_ color: Color, cornerRadius: CGFloat = 4) -> some View { modifier(HoverBackground(color: color, radius: cornerRadius)) }
}

private struct HoverBackground: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(hovering ? color : .clear))
            .onHover { hovering = $0 }
    }
}

func relativeDay(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let f = DateFormatter()
    f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year) ? "EEEE, MMMM d" : "MMMM d, yyyy"
    return f.string(from: date)
}

let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
}()

func formatBytes(_ n: Int64?) -> String {
    guard let n else { return "" }
    return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

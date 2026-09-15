import SwiftUI
import AppKit

/// Files under a post: images as real previews (the server's 120×100 thumbnail
/// is far too small to be useful), everything else as a download row.
struct FileAttachments: View {
    @ObservedObject var session: ServerSession
    let files: [MMFileInfo]
    @Environment(\.mmTheme) var theme
    @State private var previewIndex: Int?

    private var images: [MMFileInfo] { files.filter(\.isImage) }
    private var others: [MMFileInfo] { files.filter { !$0.isImage } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if images.count == 1 {
                thumb(images[0], index: 0, maxWidth: 440, maxHeight: 320)
            } else if !images.isEmpty {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(row, id: \.id) { f in
                            thumb(f, index: images.firstIndex { $0.id == f.id } ?? 0, maxWidth: 260, maxHeight: 180)
                        }
                    }
                }
            }
            ForEach(others) { f in fileRow(f) }
        }
        .sheet(item: Binding(get: { previewIndex.map { IndexBox(id: $0) } }, set: { previewIndex = $0?.id })) { box in
            ImageLightbox(session: session, files: images, index: box.id) { previewIndex = nil }
        }
    }

    private struct IndexBox: Identifiable { let id: Int }

    /// Three per row keeps a post from taking over the channel.
    private var rows: [[MMFileInfo]] {
        stride(from: 0, to: images.count, by: 3).map { Array(images[$0..<min($0 + 3, images.count)]) }
    }

    private func thumb(_ f: MMFileInfo, index: Int, maxWidth: CGFloat, maxHeight: CGFloat) -> some View {
        Thumbnail(session: session, file: f, maxWidth: maxWidth, maxHeight: maxHeight) { previewIndex = index }
            .contextMenu {
                Button("Open Preview") { previewIndex = index }
                Button("Copy Image") { Task { await copyImage(f) } }
                Button("Save to Downloads") { downloadFile(f, session: session) }
            }
    }

    private func fileRow(_ f: MMFileInfo) -> some View {
        Button { downloadFile(f, session: session) } label: {
            HStack(spacing: 8) {
                Image(systemName: f.iconName).foregroundColor(theme.link)
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\((f.extension ?? "").uppercased()) \(formatBytes(f.size))").font(.system(size: 11)).foregroundColor(theme.centerTextDim)
                }
                Image(systemName: "arrow.down.circle").foregroundColor(theme.centerTextDim)
            }
            .padding(8).frame(maxWidth: 320, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).stroke(theme.divider))
        }.buttonStyle(.plain)
    }

    private func copyImage(_ f: MMFileInfo) async {
        guard let data = try? await session.client.bytes("files/\(f.id)"), let img = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
    }
}

/// One inline image: sized from the file's own dimensions, with an expand hint on hover.
private struct Thumbnail: View {
    @ObservedObject var session: ServerSession
    let file: MMFileInfo
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    var onOpen: () -> Void
    @Environment(\.mmTheme) var theme
    @State private var hovering = false

    var body: some View {
        let size = file.displaySize(maxWidth: maxWidth, maxHeight: maxHeight)
        Button(action: onOpen) {
            ImageContent(session: session, file: file, maxPixels: maxHeight * 2)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.divider, lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .foregroundColor(.white)
                        .padding(6)
                        .opacity(hovering ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .help(file.name)
        .onHover { hovering = $0 }
    }
}

/// Still image (downscaled, cached) or an animating GIF.
struct ImageContent: View {
    @ObservedObject var session: ServerSession
    let file: MMFileInfo
    var maxPixels: CGFloat
    var contentMode: ContentMode = .fill
    @Environment(\.mmTheme) var theme

    var body: some View {
        if file.isAnimated {
            AnimatedImage(session: session, path: "files/\(file.id)")
        } else {
            AuthImage(path: file.previewPath, maxPixels: maxPixels) {
                RoundedRectangle(cornerRadius: 6).fill(theme.codeBg).overlay(ProgressView().controlSize(.small))
            }
            .aspectRatio(contentMode: contentMode)
        }
    }
}

/// GIFs keep animating: NSImageView plays every frame, SwiftUI's Image shows the first one.
struct AnimatedImage: NSViewRepresentable {
    @ObservedObject var session: ServerSession
    let path: String

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let client = session.client
        Task { @MainActor in
            if let data = try? await client.bytes(path) { v.image = NSImage(data: data) }
        }
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}

/// Full-size viewer: fit or 1:1, arrow keys walk the post's images.
struct ImageLightbox: View {
    @ObservedObject var session: ServerSession
    let files: [MMFileInfo]
    @State var index: Int
    var onClose: () -> Void
    @Environment(\.mmTheme) var theme
    @State private var zoomed = false

    private var file: MMFileInfo { files[min(index, files.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                Color.black.opacity(0.9)
                content
                if files.count > 1 {
                    HStack {
                        arrow("chevron.left", enabled: index > 0) { step(-1) }
                        Spacer()
                        arrow("chevron.right", enabled: index < files.count - 1) { step(1) }
                    }.padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 940, height: 680)
        .onExitCommand(perform: onClose)
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-1)
            case .right: step(1)
            default: break
            }
        }
        .background(KeyCatcher { event in
            switch event.keyCode {
            case 123: step(-1); return true          // ←
            case 124: step(1); return true           // →
            case 53: onClose(); return true          // esc
            default: return false
            }
        })
    }

    @ViewBuilder private var content: some View {
        if zoomed && !file.isAnimated {
            ScrollView([.horizontal, .vertical]) {
                AuthImage(path: file.previewPath, maxPixels: 1600) { ProgressView().controlSize(.large) }
                    .aspectRatio(contentMode: .fit)
                    .frame(width: CGFloat(file.width ?? 900), height: CGFloat(file.height ?? 700))
            }
            .onTapGesture { zoomed = false }
        } else {
            ImageContent(session: session, file: file, maxPixels: 1200, contentMode: .fit)
                .padding(12)
                .onTapGesture { zoomed = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundColor(theme.centerTextDim)
            }
            Spacer()
            Button { zoomed.toggle() } label: { Image(systemName: zoomed ? "minus.magnifyingglass" : "plus.magnifyingglass") }
                .buttonStyle(.borderless).help(zoomed ? "Fit to window" : "Actual size")
            Button { Task { await copy() } } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy image")
            Button { downloadFile(file, session: session) } label: { Image(systemName: "arrow.down.circle") }.buttonStyle(.borderless).help("Save to Downloads")
            Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.borderless).keyboardShortcut(.cancelAction).help("Close (Esc)")
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(theme.centerBg)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let w = file.width, let h = file.height { parts.append("\(w)×\(h)") }
        if let s = file.size { parts.append(formatBytes(s)) }
        if files.count > 1 { parts.append("\(index + 1) of \(files.count)") }
        return parts.joined(separator: " · ")
    }

    private func arrow(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                .padding(10).background(Circle().fill(Color.black.opacity(0.5))).foregroundColor(.white)
        }
        .buttonStyle(.plain).opacity(enabled ? 0.9 : 0.2).disabled(!enabled)
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard next >= 0, next < files.count else { return }
        index = next
        zoomed = false
    }

    private func copy() async {
        guard let data = try? await session.client.bytes("files/\(file.id)"), let img = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
    }
}

/// Saves the original file to ~/Downloads and reveals it in the Finder.
func downloadFile(_ f: MMFileInfo, session: ServerSession) {
    Task {
        guard let data = try? await session.client.bytes("files/\(f.id)", query: ["download": "1"]) else { return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = dir.appendingPathComponent(f.name)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\((f.name as NSString).deletingPathExtension) (\(n)).\((f.name as NSString).pathExtension)")
            n += 1
        }
        try? data.write(to: dest)
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }
}

extension MMFileInfo {
    var isAnimated: Bool { (mimeType ?? "") == "image/gif" || (`extension` ?? "").lowercased() == "gif" }

    /// The server's thumbnail is 120×100; use the 1024px preview, or the original
    /// when it is small enough that no preview was generated.
    var previewPath: String { hasPreviewImage == true ? "files/\(id)/preview" : "files/\(id)" }

    func displaySize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        guard let w = width, let h = height, w > 0, h > 0 else { return CGSize(width: maxWidth * 0.6, height: maxHeight * 0.6) }
        let scale = min(maxWidth / CGFloat(w), maxHeight / CGFloat(h), 1)
        return CGSize(width: max(60, CGFloat(w) * scale), height: max(60, CGFloat(h) * scale))
    }

    var iconName: String {
        switch (`extension` ?? "").lowercased() {
        case "pdf": return "doc.richtext"
        case "zip", "gz", "tar", "7z": return "doc.zipper"
        case "mp4", "mov", "avi", "mkv", "webm": return "film"
        case "mp3", "wav", "m4a", "ogg": return "waveform"
        case "csv", "xls", "xlsx": return "tablecells"
        case "doc", "docx", "txt", "md": return "doc.text"
        default: return "doc.fill"
        }
    }
}

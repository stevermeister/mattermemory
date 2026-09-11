import AppKit

/// Native "could not reach server" screen. Replaces Electron's loading-screen
/// and error-page renderers with ~40 lines of AppKit.
final class ErrorOverlayView: NSView {
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    var onRetry: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.alignment = .center
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.preferredMaxLayoutWidth = 420

        let button = NSButton(title: "Retry", target: self, action: #selector(retry))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, detail, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(server: Server, error: Error) {
        title.stringValue = "Can't reach \(server.name)"
        detail.stringValue = "\(server.url.absoluteString)\n\(error.localizedDescription)"
    }

    @objc private func retry() { onRetry?() }
}

import AppKit

enum Theme {
    static let bar = NSColor(srgbRed: 0x1E / 255, green: 0x32 / 255, blue: 0x5C / 255, alpha: 1)   // Mattermost "Denim"
    static let activeTab = NSColor(white: 1, alpha: 0.16)
    static let hoverTab = NSColor(white: 1, alpha: 0.08)
    static let text = NSColor.white
    static let dimText = NSColor(white: 1, alpha: 0.64)
    static let faintText = NSColor(white: 1, alpha: 0.4)
    static let mention = NSColor(srgbRed: 0xD2 / 255, green: 0x4B / 255, blue: 0x4E / 255, alpha: 1)
    static let barHeight: CGFloat = 40
}

struct TabItem: Equatable {
    var id: UUID
    var name: String
    var mentions: Int
    var unread: Bool
    var loading: Bool
    var loaded: Bool
    var active: Bool
}

/// Top bar modelled on the Electron app's server bar: traffic-light gap,
/// back/forward, one tab per server with mention/unread badges, "+" and a
/// live memory readout on the right.
final class ServerTabBar: NSView {
    var onSelect: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onTabMenu: ((UUID, NSEvent) -> Void)?

    private let tabStack = NSStackView()
    private let backButton = ServerTabBar.iconButton("chevron.left", "Back")
    private let forwardButton = ServerTabBar.iconButton("chevron.right", "Forward")
    private let addButton = ServerTabBar.iconButton("plus", "Add server")
    private let memoryLabel = NSTextField(labelWithString: "")
    private var items: [TabItem] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.bar.cgColor

        backButton.target = self; backButton.action = #selector(back)
        forwardButton.target = self; forwardButton.action = #selector(forward)
        addButton.target = self; addButton.action = #selector(add)

        tabStack.orientation = .horizontal
        tabStack.spacing = 4
        tabStack.alignment = .centerY

        memoryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        memoryLabel.textColor = Theme.faintText
        memoryLabel.alignment = .right
        memoryLabel.toolTip = "Memory used by MatterMemory and its WebKit processes"

        let nav = NSStackView(views: [backButton, forwardButton])
        nav.spacing = 0
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.documentView = tabStack
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            tabStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            tabStack.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
        ])

        let root = NSStackView(views: [nav, scroll, addButton, memoryLabel])
        root.orientation = .horizontal
        root.spacing = 6
        root.alignment = .centerY
        root.edgeInsets = NSEdgeInsets(top: 0, left: 80, bottom: 0, right: 12)   // 80 = traffic lights
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    private static func iconButton(_ symbol: String, _ tip: String) -> NSButton {
        let b = NSButton()
        b.bezelStyle = .texturedRounded
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        b.contentTintColor = Theme.dimText
        b.toolTip = tip
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    func update(items new: [TabItem]) {
        guard new != items else { return }
        items = new
        tabStack.arrangedSubviews.forEach { tabStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for item in new {
            let tab = ServerTabView(item: item)
            tab.onClick = { [weak self] in self?.onSelect?(item.id) }
            tab.onMenu = { [weak self] e in self?.onTabMenu?(item.id, e) }
            tabStack.addArrangedSubview(tab)
        }
    }

    func setHistory(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        backButton.contentTintColor = canGoBack ? Theme.dimText : Theme.faintText.withAlphaComponent(0.25)
        forwardButton.contentTintColor = canGoForward ? Theme.dimText : Theme.faintText.withAlphaComponent(0.25)
    }

    var memoryText: String { memoryLabel.stringValue }
    var memoryHidden: Bool { memoryLabel.isHidden }

    func setMemoryText(_ text: String) {
        memoryLabel.stringValue = text
        memoryLabel.isHidden = text.isEmpty
    }

    @objc private func back() { onBack?() }
    @objc private func forward() { onForward?() }
    @objc private func add() { onAdd?() }
}

/// A single server tab, drawn by hand — no NSButton styling to fight.
final class ServerTabView: NSView {
    let item: TabItem
    var onClick: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?
    private var hovering = false
    private var spinner: NSProgressIndicator?

    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let badgeFont = NSFont.systemFont(ofSize: 10, weight: .bold)

    init(item: TabItem) {
        self.item = item
        super.init(frame: .zero)
        toolTip = item.loaded ? item.name : "\(item.name) — unloaded to save memory; click to load"
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        if item.loading {
            let s = NSProgressIndicator()
            s.style = .spinning
            s.controlSize = .small
            s.isIndeterminate = true
            s.appearance = NSAppearance(named: .darkAqua)
            s.startAnimation(nil)
            addSubview(s)
            spinner = s
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    private var textWidth: CGFloat {
        (item.name as NSString).size(withAttributes: [.font: Self.font]).width.rounded(.up)
    }

    private var badgeWidth: CGFloat {
        if item.mentions > 0 { return max(18, badgeText.size(withAttributes: [.font: Self.badgeFont]).width + 10) }
        return item.unread ? 8 : 0
    }

    private var badgeText: NSString { (item.mentions > 99 ? "99+" : "\(item.mentions)") as NSString }

    override var intrinsicContentSize: NSSize {
        let extra = badgeWidth > 0 ? badgeWidth + 6 : 0
        let spin: CGFloat = item.loading ? 18 : 0
        return NSSize(width: min(220, 12 + textWidth + extra + spin + 12), height: 28)
    }

    override func layout() {
        super.layout()
        spinner?.frame = NSRect(x: bounds.width - 12 - 14, y: (bounds.height - 14) / 2, width: 14, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = item.active ? Theme.activeTab : (hovering ? Theme.hoverTab : nil)
        if let bg {
            bg.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let color: NSColor = item.active ? Theme.text : (item.loaded ? Theme.dimText : Theme.faintText)
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: color]
        let extra = badgeWidth > 0 ? badgeWidth + 6 : 0
        let spin: CGFloat = item.loading ? 18 : 0
        let availableText = bounds.width - 24 - extra - spin
        let textRect = NSRect(x: 12, y: (bounds.height - 17) / 2, width: availableText, height: 17)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        var a = attrs; a[.paragraphStyle] = para
        (item.name as NSString).draw(in: textRect, withAttributes: a)

        if badgeWidth > 0 {
            let x = 12 + min(textWidth, availableText) + 6
            if item.mentions > 0 {
                let r = NSRect(x: x, y: (bounds.height - 16) / 2, width: badgeWidth, height: 16)
                Theme.mention.setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
                let ba: [NSAttributedString.Key: Any] = [.font: Self.badgeFont, .foregroundColor: NSColor.white]
                let ts = badgeText.size(withAttributes: ba)
                badgeText.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2), withAttributes: ba)
            } else {
                let r = NSRect(x: x, y: (bounds.height - 8) / 2, width: 8, height: 8)
                Theme.text.setFill()
                NSBezierPath(ovalIn: r).fill()
            }
        }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
}

/// Shown when no server is configured.
final class EmptyStateView: NSView {
    var onAdd: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let title = NSTextField(labelWithString: "No servers yet")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let sub = NSTextField(labelWithString: "Add a Mattermost server to get started.")
        sub.textColor = .secondaryLabelColor
        let button = NSButton(title: "Add Server…", target: self, action: #selector(add))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        let stack = NSStackView(views: [title, sub, button])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func add() { onAdd?() }
}

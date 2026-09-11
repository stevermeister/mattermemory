import AppKit

/// Menu bar icon: template glyph that follows the menu bar appearance, red badge with the
/// mention count, dot for unread, and a menu with one entry per server.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let menu = NSMenu()
    private var lastKey = ""

    override init() {
        super.init()
        menu.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.changed, object: nil)
        apply()
    }

    @objc private func settingsChanged() { apply() }

    private func apply() {
        if Settings.showMenuBarIcon {
            if item == nil {
                let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                i.menu = menu
                i.button?.imagePosition = .imageOnly
                item = i
                lastKey = ""
            }
            update()
        } else if let i = item {
            NSStatusBar.system.removeStatusItem(i)
            item = nil
        }
        NSApp.setActivationPolicy(Settings.hideDockIcon && Settings.showMenuBarIcon ? .accessory : .regular)
    }

    func update() {
        guard let button = item?.button, let m = AppDelegate.shared.main?.manager else { return }
        let mentions = m.totalMentions
        let unread = m.anyUnread
        let key = "\(mentions)-\(unread)"
        guard key != lastKey else { return }
        lastKey = key
        button.image = Self.icon(mentions: mentions, unread: unread)
        button.toolTip = mentions > 0 ? "MatterMemory — \(mentions) mention\(mentions == 1 ? "" : "s")" : (unread ? "MatterMemory — unread messages" : "MatterMemory")
    }

    /// Drawn lazily via a drawing handler so label colours resolve against the current appearance.
    static func icon(mentions: Int, unread: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let color: NSColor = mentions > 0 ? .labelColor : .black
            let bubble = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4.5, width: 15, height: 11.5), xRadius: 3.5, yRadius: 3.5)
            bubble.move(to: NSPoint(x: 5, y: 4.8))
            bubble.line(to: NSPoint(x: 4, y: 1.5))
            bubble.line(to: NSPoint(x: 8.5, y: 4.8))
            bubble.lineWidth = 1.6
            color.setStroke()
            bubble.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .heavy), .foregroundColor: color]
            let s = "M" as NSString
            let ts = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: 9 - ts.width / 2, y: 10.2 - ts.height / 2), withAttributes: attrs)
            if mentions > 0 {
                let r = NSRect(x: 10, y: 10, width: 8, height: 8)
                NSColor(srgbRed: 0xD2 / 255, green: 0x4B / 255, blue: 0x4E / 255, alpha: 1).setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: -1, dy: -1)).fill()
                if mentions < 10 {
                    let ba: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6.5, weight: .bold), .foregroundColor: NSColor.white]
                    let t = "\(mentions)" as NSString
                    let bs = t.size(withAttributes: ba)
                    t.draw(at: NSPoint(x: r.midX - bs.width / 2, y: r.midY - bs.height / 2 + 0.3), withAttributes: ba)
                }
            } else if unread {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12, y: 12, width: 5, height: 5)).fill()
            }
            return true
        }
        // A template image is recoloured by the system (works on any menu bar); the badge needs real colour.
        image.isTemplate = mentions == 0
        return image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Open MatterMemory", action: #selector(AppDelegate.showMainWindow(_:)), keyEquivalent: "")
        open.target = AppDelegate.shared
        menu.addItem(open)
        menu.addItem(.separator())
        if let m = AppDelegate.shared.main?.manager {
            for (i, s) in ServerStore.shared.servers.enumerated() {
                let mentions = m.mentions(for: s.id), unread = m.unread(for: s.id)
                var title = s.name
                if mentions > 0 { title += "   \(mentions) mention\(mentions == 1 ? "" : "s")" } else if unread { title += "   •" }
                let it = NSMenuItem(title: title, action: #selector(AppDelegate.openServerFromMenu(_:)), keyEquivalent: "")
                it.target = AppDelegate.shared
                it.tag = i
                it.state = s.id == m.activeServerID ? .on : .off
                if mentions > 0 { it.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0).withWeight(.semibold)]) }
                menu.addItem(it)
            }
            if !ServerStore.shared.servers.isEmpty { menu.addItem(.separator()) }
        }
        let snap = MemoryStats.snapshot()
        let mem = NSMenuItem(title: "Memory: \(MemoryStats.format(snap.total))", action: nil, keyEquivalent: "")
        mem.isEnabled = false
        menu.addItem(mem)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: "")
        prefs.target = AppDelegate.shared
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MatterMemory", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }
}

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: pointSize, weight: weight)
    }
}

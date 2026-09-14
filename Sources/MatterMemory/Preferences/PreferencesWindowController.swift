import AppKit

final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let memoryLabel = NSTextField(labelWithString: "")
    private let idlePopup = NSPopUpButton()
    private let hiddenPopup = NSPopUpButton()
    private weak var loginItemCheckbox: NSButton?
    private var checks: [NSButton] = []
    private var memoryTimer: Timer?
    private weak var main: MainWindowController?

    init(main: MainWindowController) {
        self.main = main
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "MatterMemory Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: ServerStore.changed, object: nil)
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.updateMemory() }
        updateMemory()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // Servers
        let nameCol = NSTableColumn(identifier: .init("name")); nameCol.title = "Name"; nameCol.width = 160
        let urlCol = NSTableColumn(identifier: .init("url")); urlCol.title = "URL"; urlCol.width = 320
        table.addTableColumn(nameCol)
        table.addTableColumn(urlCol)
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(editSelected)
        table.target = self
        table.rowHeight = 22
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let buttons = NSStackView(views: [
            button("Add…", #selector(add)), button("Edit…", #selector(editSelected)), button("Remove", #selector(removeSelected)),
            button("↑", #selector(moveServerUp)), button("↓", #selector(moveServerDown)),
        ])
        buttons.spacing = 6

        // Memory
        idlePopup.removeAllItems()
        for m in Settings.idleUnloadChoices { idlePopup.addItem(withTitle: m == 0 ? "Never" : "after \(m) minutes idle") }
        idlePopup.selectItem(at: Settings.idleUnloadChoices.firstIndex(of: Settings.idleUnloadMinutes) ?? 0)
        idlePopup.target = self; idlePopup.action = #selector(idleChanged)
        let idleRow = NSStackView(views: [NSTextField(labelWithString: "Unload background servers:"), idlePopup])
        idleRow.spacing = 8
        hiddenPopup.removeAllItems()
        for m in Settings.hiddenUnloadChoices { hiddenPopup.addItem(withTitle: m == 0 ? "Never" : "after \(m) minutes") }
        hiddenPopup.selectItem(at: Settings.hiddenUnloadChoices.firstIndex(of: Settings.hiddenUnloadMinutes) ?? 0)
        hiddenPopup.target = self; hiddenPopup.action = #selector(hiddenChanged)
        let hiddenRow = NSStackView(views: [NSTextField(labelWithString: "Unload everything while the window is closed:"), hiddenPopup])
        hiddenRow.spacing = 8

        let memRow = NSStackView(views: [memoryLabel, button("Unload Inactive Now", #selector(unloadNow)), button("Clear Website Data…", #selector(clearData))])
        memRow.spacing = 8
        memoryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        let stack = NSStackView(views: [
            header("Servers"), scroll, buttons,
            header("Memory"), idleRow, hiddenRow,
            check("Low memory mode — no JavaScript JIT or web fonts (WebKit lockdown mode; reloads servers)", { Settings.lowMemoryMode }, { Settings.lowMemoryMode = $0 }),
            check("Poll unread counts for unloaded servers (one small REST call per minute)", { Settings.backgroundUnreadPolling }, { Settings.backgroundUnreadPolling = $0 }),
            check("Unload inactive servers when macOS reports memory pressure", { Settings.unloadOnMemoryPressure }, { Settings.unloadOnMemoryPressure = $0 }),
            check("Show memory readout in the top bar", { Settings.showMemoryReadout }, { Settings.showMemoryReadout = $0 }),
            memRow,
            header("Native view"),
            check("Compact sidebar: people / channels, unread first, then active in the last 3 hours", { Settings.compactSidebar }, { Settings.compactSidebar = $0 }),
            check("Always show the server bar at the top (hidden with a single native server)", { Settings.alwaysShowServerBar }, { Settings.alwaysShowServerBar = $0 }),
            header("Startup"),
            loginItemRow,
            check("When launched at login, start in the background (no window)", { Settings.startHidden }, { Settings.startHidden = $0 }),
            header("Menu bar"),
            check("Show icon in the menu bar (mention badge, server list)", { Settings.showMenuBarIcon }, { Settings.showMenuBarIcon = $0 }),
            check("Menu bar only — hide the Dock icon", { Settings.hideDockIcon }, { Settings.hideDockIcon = $0 }),
            header("Notifications"),
            check("Show desktop notifications", { Settings.notificationsEnabled }, { Settings.notificationsEnabled = $0 }),
            check("Show a dot on the dock icon for unread channels", { Settings.showUnreadBadge }, { Settings.showUnreadBadge = $0 }),
            header("Advanced"),
            check("Enable Web Inspector (right-click → Inspect Element)", { Settings.webInspectorEnabled }, { Settings.webInspectorEnabled = $0 }),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        window!.contentView = NSView()
        window!.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor),
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor),
        ])
    }

    private func header(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        return l
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return b
    }

    private func check(_ title: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        let b = SettingCheckbox(title: title, get: get, set: set)
        checks.append(b)
        return b
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { ServerStore.shared.servers.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = ServerStore.shared.servers[row]
        let text = tableColumn?.identifier.rawValue == "name" ? s.name : s.url.absoluteString
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    @objc private func reloadTable() { table.reloadData() }

    private var selectedID: UUID? {
        let r = table.selectedRow
        return r >= 0 && r < ServerStore.shared.servers.count ? ServerStore.shared.servers[r].id : nil
    }

    @objc private func add() { main?.addServer() }
    @objc private func editSelected() { if let id = selectedID { main?.editServer(id: id) } }
    @objc private func removeSelected() { if let id = selectedID { main?.removeServer(id: id) } }
    @objc private func moveServerUp() { if let id = selectedID { ServerStore.shared.move(id: id, by: -1); reselect(id) } }
    @objc private func moveServerDown() { if let id = selectedID { ServerStore.shared.move(id: id, by: 1); reselect(id) } }

    private func reselect(_ id: UUID) {
        if let i = ServerStore.shared.index(of: id) { table.selectRowIndexes([i], byExtendingSelection: false) }
    }

    // MARK: Memory

    @objc private func idleChanged() {
        Settings.idleUnloadMinutes = Settings.idleUnloadChoices[idlePopup.indexOfSelectedItem]
    }

    /// SMAppService owns the real state, so this checkbox reflects it rather than a setting.
    private var loginItemRow: NSView {
        let box = NSButton(title: "Open MatterMemory at login", target: self, action: #selector(toggleLoginItem))
        box.setButtonType(.switch)
        box.state = LoginItem.isEnabled ? .on : .off
        loginItemCheckbox = box
        let open = NSButton(title: "Open Login Items…", target: self, action: #selector(openLoginItems))
        open.bezelStyle = .rounded
        open.controlSize = .small
        open.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let row = NSStackView(views: [box, open])
        row.spacing = 10
        return row
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        if let message = LoginItem.set(sender.state == .on) {
            sender.state = LoginItem.isEnabled ? .on : .off
            let a = NSAlert()
            a.messageText = "Couldn't change the login item"
            a.informativeText = message
            a.alertStyle = .warning
            a.runModal()
        } else if LoginItem.needsApproval {
            let a = NSAlert()
            a.messageText = "Approve MatterMemory in System Settings"
            a.informativeText = "macOS needs you to allow it under General → Login Items."
            a.addButton(withTitle: "Open System Settings")
            a.addButton(withTitle: "Later")
            if a.runModal() == .alertFirstButtonReturn { LoginItem.openSystemSettings() }
        }
    }

    @objc private func openLoginItems() { LoginItem.openSystemSettings() }

    @objc private func hiddenChanged() {
        Settings.hiddenUnloadMinutes = Settings.hiddenUnloadChoices[hiddenPopup.indexOfSelectedItem]
    }

    @objc private func unloadNow() {
        main?.manager.unloadInactive()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.updateMemory() }
    }

    @objc private func clearData() {
        let a = NSAlert()
        a.messageText = "Clear all website data?"
        a.informativeText = "This logs you out of every server and removes cached files, cookies and local storage."
        a.addButton(withTitle: "Clear")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        a.beginSheetModal(for: window!) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            for v in self?.main?.manager.views.values ?? [:].values { v.unload() }
            WKWebsiteDataStoreHelper.clearAll { self?.main?.manager.activeView?.ensureLoaded() }
        }
    }

    private func updateMemory() {
        guard window?.isVisible == true else { return }
        let s = MemoryStats.snapshot()
        let loaded = main?.manager.views.values.filter(\.isLoaded).count ?? 0
        memoryLabel.stringValue = "\(MemoryStats.format(s.total)) total (app \(MemoryStats.format(s.own)), \(s.helperCount) WebKit processes, \(loaded) loaded)"
    }
}

final class SettingCheckbox: NSButton {
    private let get: () -> Bool
    private let setter: (Bool) -> Void
    init(title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
        self.get = get
        self.setter = set
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        state = get() ? .on : .off
        target = self
        action = #selector(toggled)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func toggled() { setter(state == .on) }
}

import WebKit
enum WKWebsiteDataStoreHelper {
    static func clearAll(completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records, completionHandler: completion)
        }
    }
}

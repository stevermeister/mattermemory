import AppKit

enum MainMenu {
    static func build(delegate: AppDelegate) -> NSMenu {
        let menu = NSMenu()

        // App
        let app = submenu(menu, "MatterMemory")
        app.addItem(withTitle: "About MatterMemory", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(item("Preferences…", #selector(AppDelegate.showPreferences(_:)), ",", delegate))
        app.addItem(.separator())
        app.addItem(withTitle: "Hide MatterMemory", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit MatterMemory", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File
        let file = submenu(menu, "File")
        file.addItem(item("Add Server…", #selector(AppDelegate.addServer(_:)), "n", delegate))
        file.addItem(item("Log Out of Current Server…", #selector(AppDelegate.logOutCurrent(_:)), "", delegate))
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit — standard selectors reach the WKWebView through the responder chain.
        let edit = submenu(menu, "Edit")
        edit.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatch = edit.addItem(withTitle: "Paste and Match Style", action: NSSelectorFromString("pasteAsPlainText:"), keyEquivalent: "v")
        pasteMatch.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: "Find…", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(.separator())
        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.addItem(withTitle: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        spelling.addItem(withTitle: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        spelling.addItem(.separator())
        spelling.addItem(withTitle: "Check Spelling While Typing", action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
        spelling.addItem(withTitle: "Correct Spelling Automatically", action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), keyEquivalent: "")
        let spellingItem = edit.addItem(withTitle: "Spelling and Grammar", action: nil, keyEquivalent: "")
        edit.setSubmenu(spelling, for: spellingItem)
        edit.addItem(withTitle: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "")

        // View
        let view = submenu(menu, "View")
        let toggle = item("Open in Web View", #selector(AppDelegate.toggleWebView(_:)), "w", delegate)
        toggle.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(toggle)
        view.addItem(item("Find Channel…", #selector(AppDelegate.findChannel(_:)), "", delegate))
        view.addItem(.separator())
        view.addItem(item("Reload", #selector(AppDelegate.reload(_:)), "r", delegate))
        let hard = item("Reload Ignoring Cache", #selector(AppDelegate.reloadIgnoringCache(_:)), "r", delegate)
        hard.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(hard)
        view.addItem(.separator())
        view.addItem(item("Actual Size", #selector(AppDelegate.zoomReset(_:)), "0", delegate))
        view.addItem(item("Zoom In", #selector(AppDelegate.zoomIn(_:)), "+", delegate))
        view.addItem(item("Zoom Out", #selector(AppDelegate.zoomOut(_:)), "-", delegate))
        view.addItem(.separator())
        view.addItem(item("Copy Current URL", #selector(AppDelegate.copyCurrentURL(_:)), "", delegate))
        view.addItem(.separator())
        view.addItem(item("Unload Inactive Servers", #selector(AppDelegate.unloadInactive(_:)), "", delegate))
        view.addItem(item("Unload Current Server", #selector(AppDelegate.unloadCurrent(_:)), "", delegate))
        view.addItem(.separator())
        let fs = view.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]

        // History
        let history = submenu(menu, "History")
        history.addItem(item("Back", #selector(AppDelegate.goBack(_:)), "[", delegate))
        history.addItem(item("Forward", #selector(AppDelegate.goForward(_:)), "]", delegate))

        // Window
        let window = submenu(menu, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        let show = item("Show MatterMemory", #selector(AppDelegate.showMainWindow(_:)), "1", delegate)
        show.keyEquivalentModifierMask = [.command, .shift]
        window.addItem(show)
        let next = item("Next Server", #selector(AppDelegate.nextServer(_:)), "\t", delegate)
        next.keyEquivalentModifierMask = [.control]
        window.addItem(next)
        let prev = item("Previous Server", #selector(AppDelegate.previousServer(_:)), "\t", delegate)
        prev.keyEquivalentModifierMask = [.control, .shift]
        window.addItem(prev)
        window.addItem(.separator())
        let serversItem = window.addItem(withTitle: "Servers", action: nil, keyEquivalent: "")
        let servers = ServersMenu(delegate: delegate)
        window.setSubmenu(servers, for: serversItem)
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        // Help
        let help = submenu(menu, "Help")
        help.addItem(item("Keyboard Shortcuts", #selector(AppDelegate.showShortcuts(_:)), "/", delegate))
        help.addItem(item("Mattermost Desktop (upstream project)", #selector(AppDelegate.openProjectPage(_:)), "", delegate))
        NSApp.helpMenu = help
        return menu
    }

    private static func submenu(_ parent: NSMenu, _ title: String) -> NSMenu {
        let item = parent.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title)
        parent.setSubmenu(m, for: item)
        return m
    }

    @discardableResult
    private static func item(_ title: String, _ action: Selector, _ key: String, _ target: AnyObject) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = target
        return i
    }
}

/// "Servers" submenu that rebuilds itself from the store: ⌘1…⌘9 switch servers.
final class ServersMenu: NSMenu, NSMenuDelegate {
    private weak var appDelegate: AppDelegate?
    init(delegate: AppDelegate) {
        appDelegate = delegate
        super.init(title: "Servers")
        self.delegate = self
    }
    required init(coder: NSCoder) { fatalError() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        let active = appDelegate?.main.manager.activeServerID
        for (i, s) in ServerStore.shared.servers.enumerated() {
            let item = NSMenuItem(title: s.name, action: #selector(AppDelegate.selectServer(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            item.target = appDelegate
            item.tag = i
            item.state = s.id == active ? .on : .off
            addItem(item)
        }
    }
}

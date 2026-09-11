import AppKit

/// Add / edit server sheet built on NSAlert — no xib, no custom window.
enum ServerEditor {
    static func present(on window: NSWindow?, existing: Server?, draft: (name: String, url: String)? = nil, completion: @escaping (Server?, String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "Add Server" : "Edit Server"
        alert.informativeText = "Enter the server URL, e.g. https://chat.example.com"
        alert.addButton(withTitle: existing == nil ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: draft?.name ?? existing?.name ?? "")
        nameField.placeholderString = "Display name (optional)"
        let urlField = NSTextField(string: draft?.url ?? existing?.url.absoluteString ?? "")
        urlField.placeholderString = "https://chat.example.com"
        let tokenField = NSSecureTextField(string: "")
        tokenField.placeholderString = "Personal access token (optional, skips the login page)"
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name:"), nameField],
            [NSTextField(labelWithString: "URL:"), urlField],
            [NSTextField(labelWithString: "Token:"), tokenField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(x: 0, y: 0, width: 360, height: 90)
        nameField.widthAnchor.constraint(equalToConstant: 290).isActive = true
        alert.accessoryView = grid
        alert.window.initialFirstResponder = urlField.stringValue.isEmpty ? urlField : nameField

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { completion(nil, nil); return }
            guard let url = Server.normalize(urlField.stringValue) else {
                let err = NSAlert()
                err.alertStyle = .warning
                err.messageText = "Invalid server URL"
                err.informativeText = "Use a full http(s) URL such as https://chat.example.com"
                err.runModal()
                present(on: window, existing: existing, draft: (nameField.stringValue, urlField.stringValue), completion: completion)
                return
            }
            var name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            if name.isEmpty { name = url.host ?? url.absoluteString }
            let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(Server(id: existing?.id ?? UUID(), name: name, url: url), token.isEmpty ? nil : token)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: finish) } else { finish(alert.runModal()) }
    }
}

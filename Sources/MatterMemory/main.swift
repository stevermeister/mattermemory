import AppKit

// Programmatic bootstrap: no storyboard, no nib, nothing to load at startup.
let app = NSApplication.shared
let appDelegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()

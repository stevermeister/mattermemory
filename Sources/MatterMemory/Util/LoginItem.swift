import AppKit
import ServiceManagement

/// "Open at Login" through SMAppService (macOS 13+). macOS owns the real state, so this
/// reads it live rather than caching a copy in UserDefaults.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS has the item but the user has switched it off in System Settings.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Returns nil on success, or a message to show the user.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                guard !isEnabled else { return nil }
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            let ns = error as NSError
            // Registration only works for an app in a stable location macOS trusts.
            if ns.domain == NSOSStatusErrorDomain || ns.code == 1 {
                return "Move MatterMemory to /Applications first (make install), then try again."
            }
            return error.localizedDescription
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

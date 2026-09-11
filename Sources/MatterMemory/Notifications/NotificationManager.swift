import AppKit
import UserNotifications

/// Native banners via UNUserNotificationCenter. Clicking a banner brings the
/// app forward, switches to the right server and replays the click into the
/// webapp's own handler, which navigates to the channel/thread.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var center: UNUserNotificationCenter?
    var onClick: (@MainActor (_ serverID: UUID, _ webID: Int?, _ channelID: String?, _ postID: String?) -> Void)?

    func setup() {
        // UNUserNotificationCenter aborts outside a proper .app bundle (e.g. `swift run`).
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else {
            NSLog("Notifications disabled: not running from an .app bundle")
            return
        }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, err in
            if let err { NSLog("Notification auth error: \(err)") }
        }
        center = c
    }

    func post(serverID: UUID, webID: Int?, title: String, body: String, silent: Bool, fileURL: URL? = nil, channelID: String? = nil, postID: String? = nil) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The webapp plays its own sound in-page; only mark silent ones.
        if !silent, postID != nil { content.sound = .default }   // native mode has no page to play a sound
        var info: [String: Any] = ["server": serverID.uuidString]
        if let webID { info["webID"] = webID }
        if let fileURL { info["file"] = fileURL.path }
        if let channelID { info["channel"] = channelID }
        if let postID { info["post"] = postID }
        content.userInfo = info
        let id = "\(serverID.uuidString)-\(webID ?? Int(Date().timeIntervalSince1970 * 1000))"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { err in
            if let err { NSLog("Notification error: \(err)") }
        }
    }

    func debugStatus(_ completion: @escaping (String) -> Void) {
        guard let center else { completion("notifications: center unavailable"); return }
        center.getNotificationSettings { settings in
            center.getDeliveredNotifications { delivered in
                DispatchQueue.main.async {
                    completion("notifications: auth=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) delivered=\(delivered.map { $0.request.content.title })")
                }
            }
        }
    }

    func clearAll() { center?.removeAllDeliveredNotifications() }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The webapp already suppressed notifications for the focused channel; show the rest.
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let path = info["file"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if let s = info["server"] as? String, let id = UUID(uuidString: s) {
            let webID = info["webID"] as? Int, channel = info["channel"] as? String, post = info["post"] as? String
            Task { @MainActor in self.onClick?(id, webID, channel, post) }
        }
        completionHandler()
    }
}

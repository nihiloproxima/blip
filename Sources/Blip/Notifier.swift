import Foundation
import UserNotifications

/// Bannières macOS pour les nouvelles notifications ; un clic ouvre le fil sur GitHub.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?

    /// Le centre de notifications exige un bundle : inutilisable via `swift run`.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ items: [GHNotification]) {
        guard let center else { return }
        for item in items.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = item.repository.fullName
            content.subtitle = Style.reasonLabel(item.reason)
            content.body = item.subject.title
            content.threadIdentifier = item.repository.fullName
            content.userInfo = ["id": item.id]
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "\(item.id)-\(item.updatedAt.timeIntervalSince1970)", content: content, trigger: nil))
        }
        if items.count > 3 {
            let content = UNMutableNotificationContent()
            content.title = "Et \(items.count - 3) autres notifications"
            content.body = "Ouvre Blip pour les trier."
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["id"] as? String else { return }
        await MainActor.run { onOpen?(id) }
    }
}

import UserNotifications
import AgentsHubCore

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var onSessionTapped: ((String) -> Void)?

    func setup(onSessionTapped: @escaping (String) -> Void) {
        self.onSessionTapped = onSessionTapped
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendNeedsInput(session: Session) {
        guard session.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent needs input"
        content.body = "\(session.name ?? "Session") in \(session.app?.uppercased() ?? "unknown") is waiting for you"
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "needs-input-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let sessionId = response.notification.request.content.userInfo["sessionId"] as? String {
            onSessionTapped?(sessionId)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

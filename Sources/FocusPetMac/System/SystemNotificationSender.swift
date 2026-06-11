import FocusPetCore
import Foundation
import UserNotifications

struct SystemNotificationSender {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ event: NudgeEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.reason.title
        content.body = event.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

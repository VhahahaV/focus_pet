import FocusPetCore
import Foundation
@preconcurrency import UserNotifications

enum SystemNotificationPermissionState: Sendable {
    case allowed
    case denied
    case notDetermined
    case unknown

    var title: String {
        switch self {
        case .allowed: "已允许"
        case .denied: "待开启"
        case .notDetermined: "未请求"
        case .unknown: "未知"
        }
    }

    var isAllowed: Bool {
        self == .allowed
    }
}

enum SystemNotificationDeliveryResult: Sendable {
    case delivered
    case permissionDenied
    case notGranted
    case failed
}

final class SystemNotificationSender: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func authorizationStatus(completion: @escaping @Sendable (SystemNotificationPermissionState) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(Self.permissionState(from: settings.authorizationStatus))
        }
    }

    func requestAuthorization(
        force: Bool = false,
        completion: (@Sendable (SystemNotificationPermissionState) -> Void)? = nil
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let currentState = Self.permissionState(from: settings.authorizationStatus)
            guard force || settings.authorizationStatus == .notDetermined else {
                completion?(currentState)
                return
            }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    completion?(.allowed)
                } else {
                    center.getNotificationSettings { settings in
                        completion?(Self.permissionState(from: settings.authorizationStatus))
                    }
                }
            }
        }
    }

    func deliver(
        _ event: NudgeEvent,
        completion: (@Sendable (SystemNotificationDeliveryResult) -> Void)? = nil
    ) {
        let id = event.id
        let title = event.reason.title
        let body = event.message
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Self.addNotification(id: id, title: title, body: body, completion: completion)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else {
                        completion?(.notGranted)
                        return
                    }
                    Self.addNotification(id: id, title: title, body: body, completion: completion)
                }
            case .denied:
                completion?(.permissionDenied)
            @unknown default:
                completion?(.failed)
            }
        }
    }

    private static func permissionState(from status: UNAuthorizationStatus) -> SystemNotificationPermissionState {
        switch status {
        case .authorized, .provisional:
            .allowed
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }

    private static func addNotification(
        id: String,
        title: String,
        body: String,
        completion: (@Sendable (SystemNotificationDeliveryResult) -> Void)?
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                completion?(.delivered)
            } else {
                completion?(.failed)
            }
        }
    }

    private static func addNotification(id: String, title: String, body: String) {
        addNotification(id: id, title: title, body: body, completion: nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}

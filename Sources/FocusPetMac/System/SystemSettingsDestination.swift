import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

struct SystemPermissionStatus: Equatable, Sendable {
    var title: String
    var isAllowed: Bool
    var detail: String? = nil

    static let checking = SystemPermissionStatus(title: "检查中", isAllowed: false, detail: nil)

    static func permission(_ granted: Bool, detail: String? = nil) -> SystemPermissionStatus {
        SystemPermissionStatus(title: granted ? "已允许" : "待开启", isAllowed: granted, detail: detail)
    }
}

enum SystemSettingsDestination: String, CaseIterable, Identifiable {
    case inputMonitoring
    case notifications
    case privacySecurity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring: "输入监控"
        case .notifications: "通知"
        case .privacySecurity: "隐私与安全"
        }
    }

    var statusTitle: String? {
        currentStatus?.title
    }

    var currentStatus: SystemPermissionStatus? {
        switch self {
        case .inputMonitoring:
            return Self.inputMonitoringStatus()
        case .notifications, .privacySecurity:
            return nil
        }
    }

    var settingsURL: URL {
        let rawValue: String
        switch self {
        case .inputMonitoring:
            rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .notifications:
            rawValue = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .privacySecurity:
            rawValue = "x-apple.systempreferences:com.apple.preference.security"
        }
        return URL(string: rawValue)!
    }

    func open() {
        NSWorkspace.shared.open(settingsURL)
    }

    @discardableResult
    func requestAccessIfAvailable() -> Bool? {
        switch self {
        case .inputMonitoring:
            return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) || CGRequestListenEventAccess()
        case .notifications, .privacySecurity:
            return nil
        }
    }

    private static func inputMonitoringIsGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            || CGPreflightListenEventAccess()
    }

    private static func inputMonitoringStatus() -> SystemPermissionStatus {
        if inputMonitoringIsGranted() {
            return .permission(true)
        }

        if canCreatePassiveInputEventTap() {
            return .permission(true, detail: "已通过输入事件监听确认")
        }

        return .permission(false, detail: currentAppIdentityHint)
    }

    private static var currentAppIdentityHint: String? {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return "当前进程没有 Bundle ID"
        }

        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        return "当前应用：\(name) · \(bundleID)"
    }

    private static func canCreatePassiveInputEventTap() -> Bool {
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask(for: [
                .keyDown,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown
            ]),
            callback: { _, _, event, _ in
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return false
        }

        CFMachPortInvalidate(eventTap)
        return true
    }

    private static func eventMask(for eventTypes: [CGEventType]) -> CGEventMask {
        eventTypes.reduce(CGEventMask(0)) { result, type in
            result | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

}

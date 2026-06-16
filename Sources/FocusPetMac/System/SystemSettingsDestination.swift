import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit.hid

struct SystemPermissionStatus: Equatable, Sendable {
    var title: String
    var isAllowed: Bool

    static let checking = SystemPermissionStatus(title: "检查中", isAllowed: false)

    static func permission(_ granted: Bool) -> SystemPermissionStatus {
        SystemPermissionStatus(title: granted ? "已允许" : "待开启", isAllowed: granted)
    }
}

enum SystemSettingsDestination: String, CaseIterable, Identifiable {
    case inputMonitoring
    case screenRecording
    case notifications
    case accessibility
    case privacySecurity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring: "输入监控"
        case .screenRecording: "屏幕录制"
        case .notifications: "通知"
        case .accessibility: "辅助功能"
        case .privacySecurity: "隐私与安全"
        }
    }

    var statusTitle: String? {
        currentStatus?.title
    }

    var currentStatus: SystemPermissionStatus? {
        switch self {
        case .inputMonitoring:
            return .permission(Self.inputMonitoringIsGranted())
        case .screenRecording:
            return .permission(CGPreflightScreenCaptureAccess())
        case .accessibility:
            return .permission(AXIsProcessTrusted())
        case .notifications, .privacySecurity:
            return nil
        }
    }

    var settingsURL: URL {
        let rawValue: String
        switch self {
        case .inputMonitoring:
            rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .screenRecording:
            rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications:
            rawValue = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .accessibility:
            rawValue = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
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
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        case .accessibility, .notifications, .privacySecurity:
            return nil
        }
    }

    private static func inputMonitoringIsGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
            || CGPreflightListenEventAccess()
    }
}

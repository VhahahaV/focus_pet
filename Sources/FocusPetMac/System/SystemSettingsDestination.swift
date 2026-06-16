import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

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
        switch self {
        case .inputMonitoring:
            return permissionTitle(CGPreflightListenEventAccess())
        case .screenRecording:
            return permissionTitle(CGPreflightScreenCaptureAccess())
        case .accessibility:
            return permissionTitle(AXIsProcessTrusted())
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
            return CGRequestListenEventAccess()
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        case .accessibility, .notifications, .privacySecurity:
            return nil
        }
    }

    private func permissionTitle(_ granted: Bool) -> String {
        granted ? "已允许" : "待开启"
    }
}

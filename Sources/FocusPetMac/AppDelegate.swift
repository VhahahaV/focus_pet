import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            InstallationNoticeCoordinator.showLaunchNoticeIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .focusPetOpenDashboardRequested, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

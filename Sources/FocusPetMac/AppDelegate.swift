import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: FocusPetModel?
    private var didPrepareForTermination = false

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareForTermination()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareForTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .focusPetOpenDashboardRequested, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func prepareForTermination() {
        guard !didPrepareForTermination else { return }
        didPrepareForTermination = true
        model?.prepareForApplicationTermination()
    }
}

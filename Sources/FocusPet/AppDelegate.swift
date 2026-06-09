import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        PetWindowController.shared.show(model: FocusPetModel.shared)
        FocusPetModel.shared.startDemoLoop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FocusPetModel.shared.stopDemoLoop()
    }
}

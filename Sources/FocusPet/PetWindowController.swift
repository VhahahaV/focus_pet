import AppKit
import SwiftUI

@MainActor
final class PetWindowController {
    static let shared = PetWindowController()

    private var panel: NSPanel?
    private var scale = 1.0

    private init() {}

    func show(model: FocusPetModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let rootView = PetWindowView()
            .environmentObject(model)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 220)

        let panel = NSPanel(
            contentRect: NSRect(x: 120, y: 160, width: 220, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func setOpacity(_ opacity: Double) {
        panel?.alphaValue = opacity
    }

    func setScale(_ scale: Double) {
        self.scale = scale
        guard let panel else { return }
        let size = 220 * scale
        var frame = panel.frame
        frame.size = CGSize(width: size, height: size)
        panel.setFrame(frame, display: true, animate: true)
    }

    func moveBy(delta: CGSize) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.x += delta.width
        frame.origin.y -= delta.height
        panel.setFrame(frame, display: true)
    }
}

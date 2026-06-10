import AppKit
import FocusPetCore
import SwiftUI

@MainActor
final class PetWindowController {
    static let shared = PetWindowController()

    private var panel: NSPanel?
    private let anchorController = PetDockAnchorController()
    private let hoverMenuController = PetHoverMenuController()
    private let bubblePanelController = PetBubblePanelController()
    private let minimumSize: CGFloat = 96
    private let maximumSize: CGFloat = 160

    private init() {}

    func show(model: FocusPetModel) {
        guard !model.petHidden else {
            hide()
            return
        }

        if let panel {
            panel.alphaValue = min(max(model.petOpacity, 0.5), 1.0)
            panel.orderFrontRegardless()
            refreshLayout(model: model, animate: false)
            return
        }

        let size = clampedSize(model.petSize)
        let petSize = CGSize(width: size, height: size)
        let frame = anchorController.resolveFrame(
            screen: NSScreen.main ?? NSScreen.screens.first!,
            petSize: petSize,
            placement: model.petPlacementMode,
            manualOrigin: model.petManualOrigin
        )

        let rootView = PetInteractionView()
            .environmentObject(model)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: petSize)
        hostingView.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.alphaValue = min(max(model.petOpacity, 0.5), 1.0)
        panel.orderFrontRegardless()

        self.panel = panel
        updateBubble(model: model)
    }

    func hide() {
        hoverMenuController.hide()
        bubblePanelController.hide()
        panel?.orderOut(nil)
    }

    func setOpacity(_ opacity: Double) {
        panel?.alphaValue = min(max(opacity, 0.5), 1.0)
    }

    func setSize(_ size: Double, model: FocusPetModel) {
        guard let panel else { return }
        resizePanel(panel, to: clampedSize(size), animate: true)
        refreshLayout(model: model, animate: true)
    }

    func refreshLayout(model: FocusPetModel, animate: Bool = true) {
        guard let panel else { return }
        let size = clampedSize(model.petSize)
        let petSize = CGSize(width: size, height: size)
        let screen = panel.screen ?? screen(containing: panel.frame) ?? NSScreen.main ?? NSScreen.screens.first!
        let frame = anchorController.resolveFrame(
            screen: screen,
            petSize: petSize,
            placement: model.petPlacementMode,
            manualOrigin: model.petManualOrigin
        )
        panel.setFrame(frame, display: true, animate: animate)
        panel.contentView?.frame = NSRect(origin: .zero, size: petSize)
        hoverMenuController.reposition(anchorFrame: frame)
        bubblePanelController.reposition(anchorFrame: frame)
    }

    func moveBy(delta: CGSize) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.x += delta.width
        frame.origin.y -= delta.height
        panel.setFrame(frame, display: true)
        hoverMenuController.reposition(anchorFrame: frame)
        bubblePanelController.reposition(anchorFrame: frame)
    }

    func finishDrag(model: FocusPetModel) {
        guard let panel else { return }
        let size = clampedSize(model.petSize)
        let petSize = CGSize(width: size, height: size)
        let screen = panel.screen ?? screen(containing: panel.frame) ?? NSScreen.main ?? NSScreen.screens.first!
        let resolution = anchorController.resolveDrop(
            proposedFrame: panel.frame,
            screen: screen,
            petSize: petSize
        )
        model.handlePetDragEnded(resolution: resolution)
        panel.setFrame(resolution.frame, display: true, animate: true)
        hoverMenuController.reposition(anchorFrame: resolution.frame)
        bubblePanelController.reposition(anchorFrame: resolution.frame)
    }

    func showHoverMenu(model: FocusPetModel) {
        guard let panel else { return }
        hoverMenuController.show(anchorFrame: panel.frame, model: model)
    }

    func scheduleHoverMenuHide() {
        hoverMenuController.scheduleHide()
    }

    func hideHoverMenu() {
        hoverMenuController.hide()
    }

    func updateBubble(model: FocusPetModel) {
        guard let panel else { return }
        if model.currentPetBubble == nil {
            bubblePanelController.hide()
        } else {
            bubblePanelController.show(anchorFrame: panel.frame, model: model)
        }
    }

    private func resizePanel(_ panel: NSPanel, to size: CGFloat, animate: Bool) {
        var frame = panel.frame
        frame.size = CGSize(width: size, height: size)
        panel.setFrame(frame, display: true, animate: animate)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }

    private func clampedSize(_ size: Double) -> CGFloat {
        min(max(CGFloat(size), minimumSize), maximumSize)
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
    }
}

@MainActor
private final class PetBubblePanelController {
    private var panel: NSPanel?
    private let screenMargin: CGFloat = 10
    private let anchorGap: CGFloat = 12
    private let preferredLift: CGFloat = 54

    func show(anchorFrame: NSRect, model: FocusPetModel) {
        if panel == nil {
            let view = PetBubblePanelView()
                .environmentObject(model)
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 112)

            let panel = NSPanel(
                contentRect: hostingView.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }

        reposition(anchorFrame: anchorFrame)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func reposition(anchorFrame: NSRect) {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = screen(containing: anchorFrame) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? anchorFrame
        panel.setFrame(resolvedFrame(anchorFrame: anchorFrame, size: size, visibleFrame: visibleFrame), display: true)
    }

    private func resolvedFrame(anchorFrame: NSRect, size: CGSize, visibleFrame: NSRect) -> NSRect {
        let safeFrame = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let preferredX = anchorFrame.midX - size.width / 2
        let x = clamped(preferredX, min: safeFrame.minX, max: safeFrame.maxX - size.width)

        let aboveY = anchorFrame.maxY + preferredLift
        let belowY = anchorFrame.minY - size.height - anchorGap
        let preferredY = aboveY + size.height <= safeFrame.maxY ? aboveY : belowY
        let y = clamped(preferredY, min: safeFrame.minY, max: safeFrame.maxY - size.height)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let centered = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
            return centered
        }

        return NSScreen.screens
            .map { screen in (screen, screen.frame.intersection(frame).width * screen.frame.intersection(frame).height) }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}

private struct PetBubblePanelView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        if let bubble = model.currentPetBubble {
            VStack(spacing: 8) {
                Text(bubble.message)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: 224)

                HStack(spacing: 10) {
                    if let title = bubble.primaryActionTitle {
                        Button(title) {
                            model.handlePetBubblePrimaryAction()
                        }
                    }
                    if let title = bubble.secondaryActionTitle {
                        Button(title) {
                            model.handlePetBubbleSecondaryAction()
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 260)
            .frame(minHeight: 92)
            .background {
                PetPanelSpeechBubbleShape()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
            }
        }
    }
}

private struct PetPanelSpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bubble = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 10)
        path.addRoundedRect(in: bubble, cornerSize: CGSize(width: 16, height: 16))
        path.move(to: CGPoint(x: bubble.midX - 9, y: bubble.maxY - 1))
        path.addLine(to: CGPoint(x: bubble.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: bubble.midX + 11, y: bubble.maxY - 1))
        path.closeSubpath()
        return path
    }
}

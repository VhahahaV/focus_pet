import AppKit
import FocusPetCore
import FocusPetResources
import SwiftUI

public struct PetHoverContextItem: Hashable, Sendable {
    public var symbol: String
    public var title: String
    public var value: String

    public init(symbol: String, title: String, value: String) {
        self.symbol = symbol
        self.title = title
        self.value = value
    }
}

public struct PetScreenHint: Hashable, Sendable {
    public var screenFrame: CGRect
    public var visibleFrame: CGRect

    public init(screenFrame: CGRect, visibleFrame: CGRect) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
    }
}

public struct PetRenderState: Hashable, Sendable {
    public var focusState: FocusPetCore.FocusState
    public var intent: PetIntentKind
    public var message: String?
    public var hoverMessage: String?
    public var hoverStatusEnabled: Bool
    public var hoverDetails: [PetHoverContextItem]
    public var hoverBreakButtonTitle: String
    public var pauseRemindersTitle: String
    public var activeIntentTitle: String?
    public var mappedActionTitle: String?
    public var breakEndsAt: Date?
    public var size: Double
    public var opacity: Double
    public var animationEnabled: Bool
    public var packName: String
    public var placement: PetPlacementMode
    public var customOriginX: Double?
    public var customOriginY: Double?
    public var frameURLs: [URL]
    public var framesPerSecond: Double
    public var loops: Bool
    public var hoverIntent: PetIntentKind?
    public var hoverFrameURLs: [URL]
    public var hoverFramesPerSecond: Double
    public var hoverLoops: Bool
    public var animationStartedAt: Date
    public var screenHint: PetScreenHint?

    public init(
        focusState: FocusPetCore.FocusState,
        intent: PetIntentKind,
        message: String?,
        hoverMessage: String? = nil,
        hoverStatusEnabled: Bool = true,
        hoverDetails: [PetHoverContextItem] = [],
        hoverBreakButtonTitle: String = "开始休息",
        pauseRemindersTitle: String = "暂停提醒",
        activeIntentTitle: String? = nil,
        mappedActionTitle: String? = nil,
        breakEndsAt: Date? = nil,
        size: Double,
        opacity: Double,
        animationEnabled: Bool,
        packName: String,
        placement: PetPlacementMode = .bottomRight,
        customOriginX: Double? = nil,
        customOriginY: Double? = nil,
        frameURLs: [URL] = [],
        framesPerSecond: Double = 8,
        loops: Bool = true,
        hoverIntent: PetIntentKind? = nil,
        hoverFrameURLs: [URL] = [],
        hoverFramesPerSecond: Double = 8,
        hoverLoops: Bool = true,
        animationStartedAt: Date = Date(),
        screenHint: PetScreenHint? = nil
    ) {
        self.focusState = focusState
        self.intent = intent
        self.message = message
        self.hoverMessage = hoverMessage
        self.hoverStatusEnabled = hoverStatusEnabled
        self.hoverDetails = hoverDetails
        self.hoverBreakButtonTitle = hoverBreakButtonTitle
        self.pauseRemindersTitle = pauseRemindersTitle
        self.activeIntentTitle = activeIntentTitle
        self.mappedActionTitle = mappedActionTitle
        self.breakEndsAt = breakEndsAt
        self.size = size
        self.opacity = opacity
        self.animationEnabled = animationEnabled
        self.packName = packName
        self.placement = placement
        self.customOriginX = customOriginX
        self.customOriginY = customOriginY
        self.frameURLs = frameURLs
        self.framesPerSecond = max(1, framesPerSecond)
        self.loops = loops
        self.hoverIntent = hoverIntent
        self.hoverFrameURLs = hoverFrameURLs
        self.hoverFramesPerSecond = max(1, hoverFramesPerSecond)
        self.hoverLoops = hoverLoops
        self.animationStartedAt = animationStartedAt
        self.screenHint = screenHint
    }

    public init(
        focusState: FocusPetCore.FocusState,
        action: PetAction,
        message: String?,
        hoverMessage: String? = nil,
        hoverStatusEnabled: Bool = true,
        hoverDetails: [PetHoverContextItem] = [],
        hoverBreakButtonTitle: String = "开始休息",
        pauseRemindersTitle: String = "暂停提醒",
        idleActionTitle: String? = nil,
        breakEndsAt: Date? = nil,
        size: Double,
        opacity: Double,
        animationEnabled: Bool,
        packName: String,
        placement: PetPlacementMode = .bottomRight,
        customOriginX: Double? = nil,
        customOriginY: Double? = nil,
        frameURLs: [URL] = [],
        framesPerSecond: Double = 8,
        loops: Bool = true,
        hoverAction: PetAction? = nil,
        hoverFrameURLs: [URL] = [],
        hoverFramesPerSecond: Double = 8,
        hoverLoops: Bool = true,
        animationStartedAt: Date = Date(),
        screenHint: PetScreenHint? = nil
    ) {
        self.init(
            focusState: focusState,
            intent: PetIntentKind(legacyAction: action),
            message: message,
            hoverMessage: hoverMessage,
            hoverStatusEnabled: hoverStatusEnabled,
            hoverDetails: hoverDetails,
            hoverBreakButtonTitle: hoverBreakButtonTitle,
            pauseRemindersTitle: pauseRemindersTitle,
            activeIntentTitle: PetIntentKind(legacyAction: action).title,
            mappedActionTitle: idleActionTitle,
            breakEndsAt: breakEndsAt,
            size: size,
            opacity: opacity,
            animationEnabled: animationEnabled,
            packName: packName,
            placement: placement,
            customOriginX: customOriginX,
            customOriginY: customOriginY,
            frameURLs: frameURLs,
            framesPerSecond: framesPerSecond,
            loops: loops,
            hoverIntent: hoverAction.map(PetIntentKind.init(legacyAction:)),
            hoverFrameURLs: hoverFrameURLs,
            hoverFramesPerSecond: hoverFramesPerSecond,
            hoverLoops: hoverLoops,
            animationStartedAt: animationStartedAt,
            screenHint: screenHint
        )
    }

    public static let initial = PetRenderState(
        focusState: FocusPetCore.FocusState.focus,
        intent: PetIntentKind.quietCompanion,
        message: Optional<String>.none,
        hoverMessage: Optional<String>.none,
        hoverStatusEnabled: true,
        hoverDetails: [],
        hoverBreakButtonTitle: "开始休息",
        pauseRemindersTitle: "暂停提醒",
        activeIntentTitle: nil,
        mappedActionTitle: nil,
        breakEndsAt: nil,
        size: 150,
        opacity: 0.94,
        animationEnabled: true,
        packName: "Focus Pet",
        placement: .bottomRight,
        customOriginX: nil,
        customOriginY: nil,
        frameURLs: [],
        framesPerSecond: 8,
        loops: true,
        hoverIntent: PetIntentKind.welcomeBack,
        hoverFrameURLs: [],
        hoverFramesPerSecond: 8,
        hoverLoops: false,
        animationStartedAt: Date(),
        screenHint: nil
    )

    public func displayIntent(isHovering: Bool) -> PetIntentKind {
        isHovering ? (hoverIntent ?? intent) : intent
    }

    public func displayAction(isHovering: Bool) -> PetAction {
        displayIntent(isHovering: isHovering).legacyPetAction
    }

    public func displayFrameURLs(isHovering: Bool) -> [URL] {
        isHovering && !hoverFrameURLs.isEmpty ? hoverFrameURLs : frameURLs
    }

    public func displayFramesPerSecond(isHovering: Bool) -> Double {
        isHovering && !hoverFrameURLs.isEmpty ? hoverFramesPerSecond : framesPerSecond
    }

    public func displayLoops(isHovering: Bool) -> Bool {
        isHovering && !hoverFrameURLs.isEmpty ? hoverLoops : loops
    }

    public func frameURL(at date: Date, isHovering: Bool) -> URL? {
        let urls = displayFrameURLs(isHovering: isHovering)
        guard !urls.isEmpty else { return nil }
        let elapsed = max(0, date.timeIntervalSince(animationStartedAt))
        let rawIndex = Int((elapsed * displayFramesPerSecond(isHovering: isHovering)).rounded(.down))
        let index = rawIndex % urls.count
        return urls[index]
    }
}

public struct PetPanelInteractions {
    public var showStatusBubble: () -> Void
    public var openDashboard: () -> Void
    public var openSettings: () -> Void
    public var startBreak: () -> Void
    public var pauseReminders: () -> Void
    public var cycleIntentAction: () -> Void
    public var setHovering: (Bool) -> Void
    public var toggleHidden: () -> Void
    public var setPlacement: (PetPlacementMode) -> Void
    public var dragBegan: () -> Void
    public var dragEnded: (CGPoint) -> Void

    public init(
        showStatusBubble: @escaping () -> Void = {},
        openDashboard: @escaping () -> Void = {},
        openSettings: @escaping () -> Void = {},
        startBreak: @escaping () -> Void = {},
        pauseReminders: @escaping () -> Void = {},
        cycleIntentAction: @escaping () -> Void = {},
        setHovering: @escaping (Bool) -> Void = { _ in },
        toggleHidden: @escaping () -> Void = {},
        setPlacement: @escaping (PetPlacementMode) -> Void = { _ in },
        dragBegan: @escaping () -> Void = {},
        dragEnded: @escaping (CGPoint) -> Void = { _ in }
    ) {
        self.showStatusBubble = showStatusBubble
        self.openDashboard = openDashboard
        self.openSettings = openSettings
        self.startBreak = startBreak
        self.pauseReminders = pauseReminders
        self.cycleIntentAction = cycleIntentAction
        self.setHovering = setHovering
        self.toggleHidden = toggleHidden
        self.setPlacement = setPlacement
        self.dragBegan = dragBegan
        self.dragEnded = dragEnded
    }
}

public enum PetPanelAnchorEdge: Hashable, Sendable {
    case left
    case right
    case top
    case bottom
    case bottomLeft
    case insetBottomLeft
}

private enum PetDockEdge {
    case bottom
    case left
    case right
}

private struct PetPanelSafeInsets {
    var top: CGFloat = 12
    var left: CGFloat = 12
    var bottom: CGFloat = 12
    var right: CGFloat = 12
}

@MainActor
public final class PetPanelController {
    private var panel: NSPanel?
    private let model = PetPanelModel()
    private var isDragging = false
    private var lastPlacedFrame: NSRect?
    private var dragStartMouseLocation: CGPoint?
    private var dragStartFrameOrigin: CGPoint?
    private let statusAreaHeight: CGFloat = 128
    private var temporaryFrame: NSRect?
    private var temporaryFrameExpiresAt: Date?

    public init(interactions: PetPanelInteractions = PetPanelInteractions()) {
        model.interactions = interactions
        model.hoverChanged = { [weak self] inside in
            self?.handleHoverChanged(inside)
        }
        model.moveBy = { [weak self] delta in
            self?.moveBy(delta)
        }
        model.finishDrag = { [weak self] in
            self?.finishDrag()
        }
    }

    public func setInteractions(_ interactions: PetPanelInteractions) {
        model.interactions = interactions
    }

    public func show() {
        if panel == nil {
            panel = makePanel()
        }
        if !isDragging && !model.isHovering {
            positionPanel()
        }
        panel?.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    public func update(_ renderState: PetRenderState) {
        let previousRenderState = model.renderState
        let previousScreenHint = model.renderState.screenHint
        let placementChanged = previousRenderState.placement != renderState.placement
            || previousRenderState.customOriginX != renderState.customOriginX
            || previousRenderState.customOriginY != renderState.customOriginY
        model.renderState = renderState
        if placementChanged {
            temporaryFrame = nil
            temporaryFrameExpiresAt = nil
            lastPlacedFrame = nil
        }
        let shouldReposition = !model.isHovering || placementChanged
        if panel?.isVisible == true, !isDragging && shouldReposition && temporaryFrameIsExpired {
            positionPanel(animate: previousScreenHint == renderState.screenHint)
        }
    }

    public func summonNearMouse(duration: TimeInterval = 12) {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        let size = CGFloat(model.renderState.size)
        let width = max(size, min(280, size + 110))
        let height = size + statusAreaHeight
        let mouse = NSEvent.mouseLocation
        var frame = NSRect(
            x: mouse.x + 18,
            y: mouse.y - height * 0.55,
            width: width,
            height: height
        )
        frame = clamped(frame)
        temporaryFrame = frame
        temporaryFrameExpiresAt = Date().addingTimeInterval(max(2, duration))
        lastPlacedFrame = nil
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(2, duration) * 1_000_000_000))
            if self.temporaryFrameIsExpired {
                self.temporaryFrame = nil
                self.temporaryFrameExpiresAt = nil
                self.positionPanel(animate: false)
            }
        }
    }

    public func summon(
        near targetFrame: CGRect,
        preferredEdge: PetPanelAnchorEdge = .right,
        duration: TimeInterval = 10
    ) {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        let panelSize = resolvedPanelSize()
        let target = NSRect(x: targetFrame.origin.x, y: targetFrame.origin.y, width: targetFrame.width, height: targetFrame.height)
        let visibleFrame = visibleFrame(containing: target)
        let frame = clamped(
            NSRect(origin: anchorOrigin(near: target, panelSize: panelSize, preferredEdge: preferredEdge), size: panelSize),
            preferredVisibleFrame: visibleFrame
        )
        temporaryFrame = frame
        temporaryFrameExpiresAt = Date().addingTimeInterval(max(2, duration))
        lastPlacedFrame = nil
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(2, duration) * 1_000_000_000))
            if self.temporaryFrameIsExpired {
                self.temporaryFrame = nil
                self.temporaryFrameExpiresAt = nil
                self.positionPanel(animate: false)
            }
        }
    }

    public func pin(
        near targetFrame: CGRect,
        preferredEdge: PetPanelAnchorEdge = .right,
        duration: TimeInterval? = nil
    ) {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        let panelSize = resolvedPanelSize()
        let target = NSRect(x: targetFrame.origin.x, y: targetFrame.origin.y, width: targetFrame.width, height: targetFrame.height)
        let visibleFrame = visibleFrame(containing: target)
        let frame = clamped(
            NSRect(origin: anchorOrigin(near: target, panelSize: panelSize, preferredEdge: preferredEdge), size: panelSize),
            preferredVisibleFrame: visibleFrame
        )
        temporaryFrame = frame
        let expiresAt = duration.map { Date().addingTimeInterval(max(0.25, $0)) } ?? .distantFuture
        temporaryFrameExpiresAt = expiresAt
        let isAlreadyPinned = framesApproximatelyEqual(temporaryFrame, frame)
            && framesApproximatelyEqual(Optional(panel.frame), frame)
            && panel.isVisible
        if !isAlreadyPinned {
            lastPlacedFrame = nil
            panel.setFrame(frame, display: true, animate: false)
            panel.orderFrontRegardless()
        }
        if duration != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(0.25, duration ?? 0) * 1_000_000_000))
                if self.temporaryFrameExpiresAt == expiresAt, self.temporaryFrameIsExpired {
                    self.temporaryFrame = nil
                    self.temporaryFrameExpiresAt = nil
                    self.positionPanel(animate: false)
                }
            }
        }
    }

    public func clearTemporaryPlacement(reposition: Bool = true) {
        temporaryFrame = nil
        temporaryFrameExpiresAt = nil
        lastPlacedFrame = nil
        if reposition {
            positionPanel(animate: false)
        }
    }

    private func makePanel() -> NSPanel {
        let view = PetRendererView(model: model)
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: resolvedPanelFrame(),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.backgroundColor = NSColor.clear
        panel.isOpaque = false
        panel.level = NSWindow.Level.floating
        panel.collectionBehavior = NSWindow.CollectionBehavior([.canJoinAllSpaces, .fullScreenAuxiliary])
        panel.ignoresMouseEvents = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func positionPanel(animate: Bool = true) {
        guard let panel else { return }
        if let temporaryFrame, !temporaryFrameIsExpired {
            panel.setFrame(temporaryFrame, display: true, animate: false)
            return
        }
        let nextFrame = resolvedPanelFrame()
        if framesApproximatelyEqual(lastPlacedFrame, nextFrame) {
            return
        }
        panel.setFrame(nextFrame, display: true, animate: animate)
        lastPlacedFrame = nextFrame
    }

    private func framesApproximatelyEqual(_ lhs: NSRect?, _ rhs: NSRect) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.origin.x - rhs.origin.x) < 0.6
            && abs(lhs.origin.y - rhs.origin.y) < 0.6
            && abs(lhs.size.width - rhs.size.width) < 0.6
            && abs(lhs.size.height - rhs.size.height) < 0.6
    }

    private func moveBy(_ delta: CGSize) {
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !isDragging {
            isDragging = true
            lastPlacedFrame = nil
            dragStartMouseLocation = mouseLocation
            dragStartFrameOrigin = panel.frame.origin
        }

        guard let dragStartMouseLocation, let dragStartFrameOrigin else { return }
        var frame = panel.frame
        frame.origin.x = dragStartFrameOrigin.x + (mouseLocation.x - dragStartMouseLocation.x)
        frame.origin.y = dragStartFrameOrigin.y + (mouseLocation.y - dragStartMouseLocation.y)
        panel.setFrame(clampedToScreen(frame, containing: mouseLocation), display: true)
    }

    private func finishDrag() {
        guard let panel else { return }
        isDragging = false
        dragStartMouseLocation = nil
        dragStartFrameOrigin = nil
        model.interactions.dragEnded(panel.frame.origin)
    }

    private func handleHoverChanged(_ inside: Bool) {
        guard !isDragging else { return }
        guard model.isHovering != inside else { return }
        model.isHovering = inside
        model.interactions.setHovering(inside)
    }

    private func resolvedPanelFrame() -> NSRect {
        let panelSize = resolvedPanelSize()
        let frames = preferredFrames()
        let screenFrame = frames.screen
        let visibleFrame = frames.visible
        let margin: CGFloat = 24
        let dockMargin: CGFloat = 8

        let origin: CGPoint
        switch model.renderState.placement {
        case .bottomRight:
            origin = CGPoint(x: visibleFrame.maxX - panelSize.width - margin, y: visibleFrame.minY + margin)
        case .bottomLeft:
            origin = CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
        case .topRight:
            origin = CGPoint(x: visibleFrame.maxX - panelSize.width - margin, y: visibleFrame.maxY - panelSize.height - margin)
        case .topLeft:
            origin = CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.maxY - panelSize.height - margin)
        case .dock:
            origin = dockOrigin(screenFrame: screenFrame, visibleFrame: visibleFrame, panelSize: panelSize, margin: dockMargin)
        case .custom:
            origin = CGPoint(
                x: model.renderState.customOriginX ?? visibleFrame.maxX - panelSize.width - margin,
                y: model.renderState.customOriginY ?? visibleFrame.minY + margin
            )
            return clampedToScreen(NSRect(origin: origin, size: panelSize), preferredScreenFrame: screenFrame)
        }

        return clamped(NSRect(origin: origin, size: panelSize), preferredVisibleFrame: visibleFrame)
    }

    private func resolvedPanelSize() -> CGSize {
        let size = CGFloat(model.renderState.size)
        let width = max(size, min(280, size + 110))
        let height = size + statusAreaHeight
        return CGSize(width: width, height: height)
    }

    private var temporaryFrameIsExpired: Bool {
        guard let temporaryFrameExpiresAt else { return true }
        return temporaryFrameExpiresAt <= Date()
    }

    private func preferredFrames() -> (screen: NSRect, visible: NSRect) {
        if let hint = model.renderState.screenHint {
            let screenFrame = NSRect(
                x: hint.screenFrame.origin.x,
                y: hint.screenFrame.origin.y,
                width: hint.screenFrame.width,
                height: hint.screenFrame.height
            )
            let visibleFrame = NSRect(
                x: hint.visibleFrame.origin.x,
                y: hint.visibleFrame.origin.y,
                width: hint.visibleFrame.width,
                height: hint.visibleFrame.height
            )
            return (screenFrame, safeVisibleFrame(screenFrame: screenFrame, visibleFrame: visibleFrame))
        }
        if model.renderState.placement == .custom,
           let x = model.renderState.customOriginX,
           let y = model.renderState.customOriginY,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: x, y: y)) }) {
            return (screen.frame, safeVisibleFrame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame))
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        return (screenFrame, safeVisibleFrame(screenFrame: screenFrame, visibleFrame: visibleFrame))
    }

    private func dockOrigin(screenFrame: NSRect, visibleFrame: NSRect, panelSize: CGSize, margin: CGFloat) -> CGPoint {
        if visibleFrame.minY > screenFrame.minY + 5 {
            return CGPoint(x: visibleFrame.maxX - panelSize.width - 80, y: visibleFrame.minY + margin)
        }
        if visibleFrame.minX > screenFrame.minX + 5 {
            return CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + 80)
        }
        if visibleFrame.maxX < screenFrame.maxX - 5 {
            return CGPoint(x: visibleFrame.maxX - panelSize.width - margin, y: visibleFrame.minY + 80)
        }
        return CGPoint(x: visibleFrame.maxX - panelSize.width - 24, y: visibleFrame.minY + 24)
    }

    private func anchorOrigin(near targetFrame: NSRect, panelSize: CGSize, preferredEdge: PetPanelAnchorEdge) -> CGPoint {
        let gap: CGFloat = 10
        switch preferredEdge {
        case .left:
            return CGPoint(x: targetFrame.minX - panelSize.width + panelSize.width * 0.34, y: targetFrame.midY - panelSize.height * 0.50)
        case .right:
            return CGPoint(x: targetFrame.maxX - panelSize.width * 0.34 - gap, y: targetFrame.midY - panelSize.height * 0.50)
        case .top:
            return CGPoint(x: targetFrame.midX - panelSize.width * 0.50, y: targetFrame.maxY - panelSize.height * 0.30)
        case .bottom:
            return CGPoint(x: targetFrame.midX - panelSize.width * 0.50, y: targetFrame.minY - panelSize.height * 0.70)
        case .bottomLeft:
            return CGPoint(x: targetFrame.minX + 18, y: targetFrame.minY + 18)
        case .insetBottomLeft:
            return CGPoint(x: targetFrame.minX + 8, y: targetFrame.minY + 18)
        }
    }

    private func visibleFrame(containing frame: NSRect) -> NSRect {
        let targetPoint = CGPoint(x: frame.midX, y: frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(targetPoint) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return NSRect(x: 0, y: 0, width: 1280, height: 800) }
        return safeVisibleFrame(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    private func clamped(_ frame: NSRect, preferredVisibleFrame: NSRect? = nil) -> NSRect {
        if let visible = preferredVisibleFrame {
            let x = clampedOrigin(frame.origin.x, lower: visible.minX, upper: visible.maxX - frame.width)
            let y = clampedOrigin(frame.origin.y, lower: visible.minY, upper: visible.maxY - frame.height)
            return NSRect(x: x, y: y, width: frame.width, height: frame.height)
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let rawVisible = screen?.visibleFrame ?? screenFrame
        let visible = safeVisibleFrame(screenFrame: screenFrame, visibleFrame: rawVisible)
        let x = clampedOrigin(frame.origin.x, lower: visible.minX, upper: visible.maxX - frame.width)
        let y = clampedOrigin(frame.origin.y, lower: visible.minY, upper: visible.maxY - frame.height)
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private func clampedToScreen(_ frame: NSRect, containing point: CGPoint? = nil, preferredScreenFrame: NSRect? = nil) -> NSRect {
        let screenFrame: NSRect
        if let preferredScreenFrame {
            screenFrame = preferredScreenFrame
        } else if let point,
                  let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            screenFrame = screen.frame
        } else {
            screenFrame = (NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens.first)?.frame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        }

        let x = clampedOrigin(frame.origin.x, lower: screenFrame.minX, upper: screenFrame.maxX - frame.width)
        let y = clampedOrigin(frame.origin.y, lower: screenFrame.minY, upper: screenFrame.maxY - frame.height)
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    private func clampedOrigin(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }

    private func safeVisibleFrame(screenFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        var insets = PetPanelSafeInsets()
        switch currentDockEdge() {
        case .bottom:
            if visibleFrame.minY - screenFrame.minY < 8 {
                insets.bottom = 96
            }
        case .left:
            if visibleFrame.minX - screenFrame.minX < 8 {
                insets.left = 88
            }
        case .right:
            if screenFrame.maxX - visibleFrame.maxX < 8 {
                insets.right = 88
            }
        }

        return insetFrame(visibleFrame, by: insets)
    }

    private func insetFrame(_ frame: NSRect, by insets: PetPanelSafeInsets) -> NSRect {
        let maxHorizontalInset = max(0, (frame.width - 1) / 2)
        let maxVerticalInset = max(0, (frame.height - 1) / 2)
        let left = min(max(0, insets.left), maxHorizontalInset)
        let right = min(max(0, insets.right), maxHorizontalInset)
        let bottom = min(max(0, insets.bottom), maxVerticalInset)
        let top = min(max(0, insets.top), maxVerticalInset)
        return NSRect(
            x: frame.minX + left,
            y: frame.minY + bottom,
            width: max(1, frame.width - left - right),
            height: max(1, frame.height - top - bottom)
        )
    }

    private func currentDockEdge() -> PetDockEdge {
        let orientation = UserDefaults.standard
            .persistentDomain(forName: "com.apple.dock")?["orientation"] as? String
        switch orientation {
        case "left":
            return .left
        case "right":
            return .right
        default:
            return .bottom
        }
    }
}

private enum PetFrameImageCache {
    private nonisolated(unsafe) static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 240
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: image.cacheCost)
        return image
    }
}

private extension NSImage {
    var cacheCost: Int {
        max(1, Int(size.width * size.height * 4))
    }
}

@MainActor
private final class PetPanelModel: ObservableObject {
    @Published var renderState = PetRenderState.initial
    @Published var isHovering = false
    var interactions = PetPanelInteractions()
    var hoverChanged: (Bool) -> Void = { _ in }
    var moveBy: (CGSize) -> Void = { _ in }
    var finishDrag: () -> Void = {}
}

private struct PetBubbleSurface: View {
    var message: String?
    var hoverTitle: String?
    var hoverDetails: [PetHoverContextItem]
    var breakButtonTitle: String
    var activeIntentTitle: String?
    var mappedActionTitle: String?
    var breakEndsAt: Date?
    var showsHoverContext: Bool
    var startBreak: () -> Void
    var cycleIntentAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsHoverContext {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(hoverTitle ?? "桌宠状态")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                    ForEach(Array(hoverDetails.prefix(4).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 4) {
                            Image(systemName: item.symbol)
                                .font(.caption2)
                                .foregroundStyle(.tint)
                                .frame(width: 11)
                            Text(item.value)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.caption2)
                    }
                }

                HStack(spacing: 6) {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Button(action: startBreak) {
                            HStack(spacing: 6) {
                                Image(systemName: breakEndsAt == nil ? "cup.and.saucer.fill" : "stop.fill")
                                    .font(.caption.weight(.bold))
                                Text(buttonTitle(at: context.date))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.86)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.accentColor.gradient, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                    }

                    if let mappedActionTitle {
                        PetActionSwitchButton(
                            activeIntentTitle: activeIntentTitle,
                            mappedActionTitle: mappedActionTitle,
                            action: cycleIntentAction
                        )
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 1)
                    Text(message ?? "我在。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showsHoverContext, let message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .overlay(alignment: .bottom) {
            BubbleTail()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .frame(width: 18, height: 10)
                .offset(y: 8)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(minimum: 76), spacing: 7), GridItem(.flexible(minimum: 76), spacing: 7)]
    }

    private func buttonTitle(at date: Date) -> String {
        guard let breakEndsAt else { return breakButtonTitle }
        let remaining = max(0, Int(breakEndsAt.timeIntervalSince(date).rounded(.up)))
        guard remaining > 0 else { return "结束休息" }
        return "结束休息 · \(FocusPetFormatters.duration(remaining))"
    }
}

private struct PetActionSwitchButton: View {
    var activeIntentTitle: String?
    var mappedActionTitle: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.bold))
                Text("换动作")
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background {
                Capsule()
                    .fill(Color.accentColor.opacity(isHovered ? 0.18 : 0.13).gradient)
            }
            .overlay {
                Capsule()
                    .stroke(Color.accentColor.opacity(isHovered ? 0.62 : 0.42), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(isHovered ? 0.22 : 0.14), radius: isHovered ? 7 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .help("换一个\(activeIntentTitle ?? "当前")动作，当前：\(mappedActionTitle)")
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX - 5, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.midX + 5, y: rect.midY))
        return path
    }
}

private struct PetRendererView: View {
    @ObservedObject var model: PetPanelModel
    @State private var lastDragTranslation = CGSize.zero
    @State private var isDragging = false

    var body: some View {
        let renderState = model.renderState
        let isHovering = model.isHovering
        let usesHoverPresentation = isHovering && !isDragging
        let displayIntent = renderState.displayIntent(isHovering: usesHoverPresentation)
        let showsHoverContext = usesHoverPresentation && renderState.hoverStatusEnabled
        let hasStatusSurface = renderState.message != nil || showsHoverContext
        let maxFramesPerSecond = usesHoverPresentation ? 8.0 : 6.0
        let displayFramesPerSecond = min(maxFramesPerSecond, max(1, renderState.displayFramesPerSecond(isHovering: usesHoverPresentation)))
        let throttledFramesPerSecond = (!usesHoverPresentation && displayIntent == .quietCompanion)
            ? min(2, displayFramesPerSecond)
            : displayFramesPerSecond
        let frameInterval = 1 / throttledFramesPerSecond
        let bubbleWidth = max(214, min(258, renderState.size + 108))
        let bubbleHeight: CGFloat = showsHoverContext ? 118 : 54
        let panelWidth = max(renderState.size, bubbleWidth)
        let panelHeight = renderState.size + 128
        ZStack(alignment: .bottom) {
            PetBubbleSurface(
                message: renderState.message,
                hoverTitle: renderState.hoverMessage,
                hoverDetails: renderState.hoverDetails,
                breakButtonTitle: renderState.hoverBreakButtonTitle,
                activeIntentTitle: renderState.activeIntentTitle,
                mappedActionTitle: renderState.mappedActionTitle,
                breakEndsAt: renderState.breakEndsAt,
                showsHoverContext: showsHoverContext,
                startBreak: model.interactions.startBreak,
                cycleIntentAction: model.interactions.cycleIntentAction
            )
            .frame(width: bubbleWidth, height: bubbleHeight)
            .opacity(hasStatusSurface ? 1 : 0)
            .scaleEffect(hasStatusSurface ? 1 : 0.92)
            .offset(y: -renderState.size - 8)
            .animation(renderState.animationEnabled ? .easeOut(duration: 0.18) : nil, value: hasStatusSurface)
            .allowsHitTesting(hasStatusSurface)

            petVisual(
                renderState: renderState,
                isHovering: usesHoverPresentation,
                displayIntent: displayIntent,
                frameInterval: frameInterval
            )
            .contentShape(Rectangle())
            .gesture(tapGesture)
            .simultaneousGesture(dragGesture)
            .overlay(alignment: .center) {
                if usesHoverPresentation {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 3)
                        .frame(width: renderState.size * 1.08, height: renderState.size * 1.08)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .bottom)
        .onHover { inside in
            model.hoverChanged(inside)
        }
        .contextMenu {
            Button("显示当前状态") {
                model.interactions.showStatusBubble()
            }
            Button("打开今日") {
                model.interactions.openDashboard()
            }
            Button("宠物设置") {
                model.interactions.openSettings()
            }
            Divider()
            Button(model.renderState.hoverBreakButtonTitle) {
                model.interactions.startBreak()
            }
            if let mappedActionTitle = model.renderState.mappedActionTitle {
                Button("切换\(model.renderState.activeIntentTitle ?? "当前")动作：\(mappedActionTitle)") {
                    model.interactions.cycleIntentAction()
                }
            }
            Button(model.renderState.pauseRemindersTitle) {
                model.interactions.pauseReminders()
            }
            Divider()
            Menu("位置") {
                ForEach(PetPlacementMode.allCases.filter { $0 != .custom }) { placement in
                    Button(placement.title) {
                        model.interactions.setPlacement(placement)
                    }
                }
            }
            Button("隐藏桌宠") {
                model.interactions.toggleHidden()
            }
            Divider()
            Button("退出 Focus Pet", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private func petVisual(
        renderState: PetRenderState,
        isHovering: Bool,
        displayIntent: PetIntentKind,
        frameInterval: TimeInterval
    ) -> some View {
        if renderState.animationEnabled {
            TimelineView(.periodic(from: renderState.animationStartedAt, by: frameInterval)) { context in
                petFrame(
                    renderState: renderState,
                    isHovering: isHovering,
                    displayIntent: displayIntent,
                    date: context.date
                )
            }
        } else {
            petFrame(
                renderState: renderState,
                isHovering: isHovering,
                displayIntent: displayIntent,
                date: renderState.animationStartedAt
            )
        }
    }

    private func petFrame(
        renderState: PetRenderState,
        isHovering: Bool,
        displayIntent: PetIntentKind,
        date: Date
    ) -> some View {
        let actionAge = date.timeIntervalSince(renderState.animationStartedAt)
        return ZStack {
            if let frameURL = renderState.frameURL(at: date, isHovering: isHovering),
               let image = PetFrameImageCache.image(for: frameURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .opacity(renderState.opacity)
                    .frame(width: renderState.size, height: renderState.size)
                    .accessibilityLabel(renderState.packName)
            } else {
                DinoBody(state: renderState.focusState, intent: displayIntent, phase: actionAge)
                    .opacity(renderState.opacity)
                    .frame(width: renderState.size, height: renderState.size)
                    .animation(renderState.animationEnabled ? .easeInOut(duration: 0.28) : nil, value: displayIntent)
            }
        }
        .shadow(color: isHovering ? Color.accentColor.opacity(0.12) : .clear, radius: isHovering ? 3 : 0)
    }

    private var tapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                model.interactions.openDashboard()
            }
            .exclusively(before: TapGesture(count: 1)
                .onEnded {
                    model.interactions.showStatusBubble()
                }
            )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    model.interactions.dragBegan()
                }
                let delta = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                model.moveBy(delta)
                lastDragTranslation = value.translation
            }
            .onEnded { _ in
                isDragging = false
                lastDragTranslation = .zero
                model.finishDrag()
            }
    }
}

private struct DinoBody: View {
    var state: FocusPetCore.FocusState
    var intent: PetIntentKind
    var phase: TimeInterval

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34)
                .fill(bodyColor)
                .frame(width: 112, height: 92)
                .offset(y: 16)
                .scaleEffect(x: 1 + breath * 0.012, y: 1 - breath * 0.010)

            Circle()
                .fill(headColor)
                .frame(width: 96, height: 82)
                .offset(y: -22)
                .rotationEffect(.degrees(headTilt))
                .offset(y: headLift)

            HStack(spacing: 24) {
                eye
                eye
            }
            .offset(y: -30)
            .rotationEffect(.degrees(headTilt))
            .offset(y: headLift)

            Capsule()
                .fill(.white.opacity(0.9))
                .frame(width: mouthWidth, height: state == .away ? 4 : 8)
                .offset(y: -8)
                .rotationEffect(.degrees(headTilt))
                .offset(y: headLift)

            if state == .distracted {
                Text("?")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.orange)
                    .offset(x: 50, y: -62 + bounce * 3)
            }

            if intent == .focusRestHint {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .scaleEffect(1 + abs(breath) * 0.12)
                    .offset(x: -50, y: -58 - abs(bounce) * 5)
            }

            if intent == .welcomeBack || intent == .dashboardGuide {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .rotationEffect(.degrees(sin(phase * 8) * 12))
                    .offset(x: 46, y: -54 + bounce * 3)
            }

            if isMoving || intent == .mouseSummon {
                Image(systemName: isMoving ? "arrow.left.arrow.right.circle.fill" : "cursorarrow.motionlines")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.purple)
                    .scaleEffect(1 + abs(bounce) * 0.08)
                    .offset(x: 48, y: -54 + bounce * 4)
            }

            if intent == .dragged {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.purple)
                    .rotationEffect(.degrees(sin(phase * 9) * 8))
                    .offset(x: 48, y: -54 + bounce * 4)
            }

            if state == .away {
                Text("zZ")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.65 + abs(breath) * 0.25)
                    .offset(x: 44, y: -60 - abs(bounce) * 4)
            }
        }
        .scaleEffect(baseScale)
        .offset(x: bodyOffsetX, y: bodyOffsetY)
    }

    private var eye: some View {
        Capsule()
            .fill(state == .away ? Color.secondary.opacity(0.6) : Color.black.opacity(0.82))
            .frame(width: 11, height: eyeHeight)
    }

    private var breath: CGFloat {
        CGFloat(sin(phase * 2.0))
    }

    private var bounce: CGFloat {
        CGFloat(sin(phase * 5.0))
    }

    private var isBlinking: Bool {
        let cycle = phase.truncatingRemainder(dividingBy: 4.2)
        return cycle > 3.92 || intent == .quietCompanion
    }

    private var eyeHeight: CGFloat {
        if state == .away {
            return 3
        }
        return isBlinking ? 3 : 18
    }

    private var headTilt: Double {
        switch intent {
        case .distractedObserve, .nudgeGentle, .nudgeStrong:
            return sin(phase * 3.0) * 6
        case .focusRestHint:
            return -5
        case .welcomeBack, .dashboardGuide:
            return sin(phase * 6.0) * 4
        case .moveLeft, .moveRight, .moveUp, .moveDown, .mouseSummon:
            return sin(phase * 8.0) * 5
        case .dragged:
            return 8 + sin(phase * 6.0) * 3
        default:
            return 0
        }
    }

    private var headLift: CGFloat {
        switch intent {
        case .focusRestHint:
            return -5 - abs(breath) * 2
        case .welcomeBack, .dashboardGuide:
            return -abs(bounce) * 5
        case .moveLeft, .moveRight, .moveUp, .moveDown, .mouseSummon:
            return -abs(bounce) * 8
        case .dragged:
            return -6 - abs(bounce) * 4
        default:
            return breath * 1.5
        }
    }

    private var mouthWidth: CGFloat {
        switch intent {
        case .welcomeBack, .dashboardGuide:
            return 38
        case .distractedObserve, .nudgeGentle, .nudgeStrong:
            return 20
        case .moveLeft, .moveRight, .moveUp, .moveDown, .mouseSummon:
            return 34
        case .dragged:
            return 22
        default:
            return 30
        }
    }

    private var baseScale: CGFloat {
        switch intent {
        case .welcomeBack, .dashboardGuide:
            return 1.04 + abs(bounce) * 0.02
        case .focusRestHint:
            return 1.03 + abs(breath) * 0.02
        case .sleep:
            return 0.98 + breath * 0.01
        case .moveLeft, .moveRight, .moveUp, .moveDown, .mouseSummon:
            return 1.02 + abs(bounce) * 0.035
        case .dragged:
            return 1.04 + abs(bounce) * 0.025
        default:
            return 1.0 + breath * 0.008
        }
    }

    private var bodyOffsetX: CGFloat {
        switch intent {
        case .moveLeft:
            return -abs(CGFloat(sin(phase * 8.0))) * 8
        case .moveRight:
            return CGFloat(sin(phase * 8.0)) * 8
        case .moveUp, .moveDown:
            return CGFloat(sin(phase * 10.0)) * 12
        case .mouseSummon:
            return CGFloat(sin(phase * 6.0)) * 5
        case .dragged:
            return CGFloat(sin(phase * 8.0)) * 4
        default:
            return 0
        }
    }

    private var bodyOffsetY: CGFloat {
        switch intent {
        case .welcomeBack, .dashboardGuide:
            return -abs(bounce) * 5
        case .sleep:
            return 3
        case .moveUp:
            return -abs(bounce) * 8
        case .moveDown:
            return abs(bounce) * 8
        case .moveLeft, .moveRight, .mouseSummon:
            return -abs(bounce) * 5
        case .dragged:
            return -abs(bounce) * 6
        default:
            return 0
        }
    }

    private var isMoving: Bool {
        switch intent {
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            return true
        default:
            return false
        }
    }

    private var bodyColor: Color {
        switch state {
        case .focus: Color(red: 0.40, green: 0.72, blue: 0.55)
        case .distracted: Color(red: 0.95, green: 0.62, blue: 0.35)
        case .breakTime: Color(red: 0.38, green: 0.64, blue: 0.86)
        case .away: Color(red: 0.52, green: 0.55, blue: 0.64)
        }
    }

    private var headColor: Color {
        switch state {
        case .focus: Color(red: 0.64, green: 0.86, blue: 0.68)
        case .distracted: Color(red: 1.0, green: 0.76, blue: 0.48)
        case .breakTime: Color(red: 0.68, green: 0.84, blue: 0.95)
        case .away: Color(red: 0.66, green: 0.68, blue: 0.75)
        }
    }
}

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
    public var action: PetAction
    public var message: String?
    public var hoverMessage: String?
    public var hoverStatusEnabled: Bool
    public var hoverDetails: [PetHoverContextItem]
    public var hoverBreakButtonTitle: String
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
    public var hoverAction: PetAction?
    public var hoverFrameURLs: [URL]
    public var hoverFramesPerSecond: Double
    public var hoverLoops: Bool
    public var animationStartedAt: Date
    public var screenHint: PetScreenHint?

    public init(
        focusState: FocusPetCore.FocusState,
        action: PetAction,
        message: String?,
        hoverMessage: String? = nil,
        hoverStatusEnabled: Bool = true,
        hoverDetails: [PetHoverContextItem] = [],
        hoverBreakButtonTitle: String = "开始休息",
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
        self.focusState = focusState
        self.action = action
        self.message = message
        self.hoverMessage = hoverMessage
        self.hoverStatusEnabled = hoverStatusEnabled
        self.hoverDetails = hoverDetails
        self.hoverBreakButtonTitle = hoverBreakButtonTitle
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
        self.hoverAction = hoverAction
        self.hoverFrameURLs = hoverFrameURLs
        self.hoverFramesPerSecond = max(1, hoverFramesPerSecond)
        self.hoverLoops = hoverLoops
        self.animationStartedAt = animationStartedAt
        self.screenHint = screenHint
    }

    public static let initial = PetRenderState(
        focusState: FocusPetCore.FocusState.focus,
        action: PetAction.idle,
        message: Optional<String>.none,
        hoverMessage: Optional<String>.none,
        hoverStatusEnabled: true,
        hoverDetails: [],
        hoverBreakButtonTitle: "开始休息",
        breakEndsAt: nil,
        size: 150,
        opacity: 0.94,
        animationEnabled: true,
        packName: "Focus Dino",
        placement: .bottomRight,
        customOriginX: nil,
        customOriginY: nil,
        frameURLs: [],
        framesPerSecond: 8,
        loops: true,
        hoverAction: PetAction.welcomeBack,
        hoverFrameURLs: [],
        hoverFramesPerSecond: 8,
        hoverLoops: false,
        animationStartedAt: Date(),
        screenHint: nil
    )

    public func displayAction(isHovering: Bool) -> PetAction {
        isHovering ? (hoverAction ?? action) : action
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
        self.setHovering = setHovering
        self.toggleHidden = toggleHidden
        self.setPlacement = setPlacement
        self.dragBegan = dragBegan
        self.dragEnded = dragEnded
    }
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
        model.renderState = renderState
        if panel?.isVisible == true, !isDragging && !model.isHovering && temporaryFrameIsExpired {
            positionPanel()
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
                self.positionPanel()
            }
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
        panel.setFrame(clamped(frame), display: true)
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
        let size = CGFloat(model.renderState.size)
        let width = max(size, min(280, size + 110))
        let height = size + statusAreaHeight
        let frames = preferredFrames()
        let screenFrame = frames.screen
        let visibleFrame = frames.visible
        let panelSize = CGSize(width: width, height: height)
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
        }

        return clamped(NSRect(origin: origin, size: panelSize), preferredVisibleFrame: visibleFrame)
    }

    private var temporaryFrameIsExpired: Bool {
        guard let temporaryFrameExpiresAt else { return true }
        return temporaryFrameExpiresAt <= Date()
    }

    private func preferredFrames() -> (screen: NSRect, visible: NSRect) {
        if let hint = model.renderState.screenHint {
            return (
                NSRect(x: hint.screenFrame.origin.x, y: hint.screenFrame.origin.y, width: hint.screenFrame.width, height: hint.screenFrame.height),
                NSRect(x: hint.visibleFrame.origin.x, y: hint.visibleFrame.origin.y, width: hint.visibleFrame.width, height: hint.visibleFrame.height)
            )
        }
        if model.renderState.placement == .custom,
           let x = model.renderState.customOriginX,
           let y = model.renderState.customOriginY,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: x, y: y)) }) {
            return (screen.frame, screen.visibleFrame)
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let visibleFrame = screen?.visibleFrame ?? screenFrame
        return (screenFrame, visibleFrame)
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

    private func clamped(_ frame: NSRect, preferredVisibleFrame: NSRect? = nil) -> NSRect {
        if let visible = preferredVisibleFrame {
            let x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            let y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            return NSRect(x: x, y: y, width: frame.width, height: frame.height)
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        let y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        return NSRect(x: x, y: y, width: frame.width, height: frame.height)
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
    var breakEndsAt: Date?
    var showsHoverContext: Bool
    var startBreak: () -> Void

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

                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Button(action: startBreak) {
                        HStack(spacing: 6) {
                            Image(systemName: breakEndsAt == nil ? "cup.and.saucer.fill" : "stop.fill")
                                .font(.caption.weight(.bold))
                            Text(buttonTitle(at: context.date))
                                .font(.caption.weight(.semibold))
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .overlay(alignment: .bottom) {
            BubbleTail()
                .fill(.ultraThinMaterial)
                .frame(width: 18, height: 10)
                .offset(y: 8)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
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
        let displayAction = renderState.displayAction(isHovering: isHovering)
        let showsHoverContext = isHovering && renderState.hoverStatusEnabled
        let hasStatusSurface = renderState.message != nil || showsHoverContext
        let frameInterval = 1 / max(1, max(renderState.framesPerSecond, renderState.hoverFramesPerSecond))
        let bubbleWidth = max(196, min(236, renderState.size + 86))
        let bubbleHeight: CGFloat = showsHoverContext ? 118 : 54
        let panelWidth = max(renderState.size, bubbleWidth)
        let panelHeight = renderState.size + 128
        ZStack(alignment: .bottom) {
            PetBubbleSurface(
                message: renderState.message,
                hoverTitle: renderState.hoverMessage,
                hoverDetails: renderState.hoverDetails,
                breakButtonTitle: renderState.hoverBreakButtonTitle,
                breakEndsAt: renderState.breakEndsAt,
                showsHoverContext: showsHoverContext,
                startBreak: model.interactions.startBreak
            )
            .frame(width: bubbleWidth, height: bubbleHeight)
            .opacity(hasStatusSurface ? 1 : 0)
            .scaleEffect(hasStatusSurface ? 1 : 0.92)
            .offset(y: -renderState.size - 8)
            .animation(renderState.animationEnabled ? .easeOut(duration: 0.18) : nil, value: hasStatusSurface)
            .allowsHitTesting(hasStatusSurface)

            TimelineView(.periodic(from: renderState.animationStartedAt, by: frameInterval)) { context in
                let actionAge = context.date.timeIntervalSince(renderState.animationStartedAt)
                ZStack {
                    if let frameURL = renderState.frameURL(at: context.date, isHovering: isHovering),
                       let image = NSImage(contentsOf: frameURL) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .opacity(renderState.opacity)
                            .frame(width: renderState.size, height: renderState.size)
                            .accessibilityLabel(renderState.packName)
                    } else {
                        DinoBody(state: renderState.focusState, action: displayAction, phase: actionAge)
                            .opacity(renderState.opacity)
                            .frame(width: renderState.size, height: renderState.size)
                            .animation(renderState.animationEnabled ? .easeInOut(duration: 0.28) : nil, value: displayAction)
                    }
                }
                .shadow(color: isHovering ? Color.accentColor.opacity(0.35) : .clear, radius: isHovering ? 12 : 0)
            }
            .contentShape(Rectangle())
            .gesture(tapGesture)
            .simultaneousGesture(dragGesture)
            .overlay(alignment: .center) {
                if isHovering {
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
            Button("暂停提醒 30 分钟") {
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
    var action: PetAction
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

            if action == .stretch {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .scaleEffect(1 + abs(breath) * 0.12)
                    .offset(x: -50, y: -58 - abs(bounce) * 5)
            }

            if action == .welcomeBack {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .rotationEffect(.degrees(sin(phase * 8) * 12))
                    .offset(x: 46, y: -54 + bounce * 3)
            }

            if action == .screenTransfer || action == .mouseSummon {
                Image(systemName: action == .screenTransfer ? "arrow.left.arrow.right.circle.fill" : "cursorarrow.motionlines")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.purple)
                    .scaleEffect(1 + abs(bounce) * 0.08)
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
        return cycle > 3.92 || action == .blink
    }

    private var eyeHeight: CGFloat {
        if state == .away {
            return 3
        }
        return isBlinking ? 3 : 18
    }

    private var headTilt: Double {
        switch action {
        case .distractedLook, .nudgeGentle, .nudgeStrong:
            return sin(phase * 3.0) * 6
        case .stretch:
            return -5
        case .welcomeBack, .wake:
            return sin(phase * 6.0) * 4
        case .run, .screenTransfer, .mouseSummon:
            return sin(phase * 8.0) * 5
        default:
            return 0
        }
    }

    private var headLift: CGFloat {
        switch action {
        case .stretch:
            return -5 - abs(breath) * 2
        case .welcomeBack, .wake:
            return -abs(bounce) * 5
        case .run, .screenTransfer, .mouseSummon:
            return -abs(bounce) * 8
        default:
            return breath * 1.5
        }
    }

    private var mouthWidth: CGFloat {
        switch action {
        case .welcomeBack, .wake:
            return 38
        case .distractedLook, .nudgeGentle, .nudgeStrong:
            return 20
        case .run, .screenTransfer, .mouseSummon:
            return 34
        default:
            return 30
        }
    }

    private var baseScale: CGFloat {
        switch action {
        case .welcomeBack, .wake:
            return 1.04 + abs(bounce) * 0.02
        case .stretch:
            return 1.03 + abs(breath) * 0.02
        case .sleep:
            return 0.98 + breath * 0.01
        case .run, .screenTransfer, .mouseSummon:
            return 1.02 + abs(bounce) * 0.035
        default:
            return 1.0 + breath * 0.008
        }
    }

    private var bodyOffsetX: CGFloat {
        switch action {
        case .run:
            return CGFloat(sin(phase * 8.0)) * 8
        case .screenTransfer:
            return CGFloat(sin(phase * 10.0)) * 12
        case .mouseSummon:
            return CGFloat(sin(phase * 6.0)) * 5
        default:
            return 0
        }
    }

    private var bodyOffsetY: CGFloat {
        switch action {
        case .welcomeBack, .wake:
            return -abs(bounce) * 5
        case .sleep:
            return 3
        case .run, .screenTransfer, .mouseSummon:
            return -abs(bounce) * 5
        default:
            return 0
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

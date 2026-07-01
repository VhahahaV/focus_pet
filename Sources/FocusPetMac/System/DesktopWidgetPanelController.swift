import AppKit
import CoreGraphics
import FocusPetWidgets
import SwiftUI

enum DesktopWidgetCardKind: String, CaseIterable, Identifiable, Hashable {
    case currentStatus
    case recentRhythm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentStatus: "当前状态卡"
        case .recentRhythm: "最近节奏卡"
        }
    }

    var subtitle: String {
        switch self {
        case .currentStatus: "专注、走神、休息和今日短摘要"
        case .recentRhythm: "最近 4 小时的节奏占比和时间线"
        }
    }

    var symbolName: String {
        switch self {
        case .currentStatus: "checkmark.circle.fill"
        case .recentRhythm: "chart.pie.fill"
        }
    }

    fileprivate var cardSize: NSSize {
        switch self {
        case .currentStatus: NSSize(width: 170, height: 170)
        case .recentRhythm: NSSize(width: 360, height: 170)
        }
    }

    fileprivate var panelSize: NSSize {
        let cardSize = cardSize
        let shadowPadding = Self.panelShadowPadding
        return NSSize(
            width: cardSize.width + shadowPadding * 2,
            height: cardSize.height + shadowPadding * 2
        )
    }

    fileprivate static let panelShadowPadding: CGFloat = 0
}

enum DesktopWidgetPanelCommand {
    case openDashboard
    case openSettings
    case showAllCards
    case hideCard
    case hideAllCards
}

@MainActor
final class DesktopWidgetPanelController: NSObject, NSWindowDelegate {
    private struct PanelRecord {
        var state: DesktopWidgetPanelState
        var panel: DesktopWidgetPanel?
        var onMoveEnded: ((NSPoint) -> Void)?
        var onClose: (() -> Void)?
        var onCommand: ((DesktopWidgetPanelCommand) -> Void)?
    }

    private var records: [DesktopWidgetCardKind: PanelRecord] = [:]

    func isVisible(_ kind: DesktopWidgetCardKind) -> Bool {
        records[kind]?.panel?.isVisible == true
    }

    func show(
        _ kind: DesktopWidgetCardKind,
        snapshot: FocusPetWidgetSnapshot,
        recentRhythmWindowHours: Int,
        cardsMovable: Bool,
        preferredOrigin: NSPoint?,
        onMoveEnded: @escaping (NSPoint) -> Void,
        onClose: @escaping () -> Void,
        onCommand: @escaping (DesktopWidgetPanelCommand) -> Void
    ) {
        var record = records[kind] ?? PanelRecord(
            state: DesktopWidgetPanelState(snapshot: snapshot),
            panel: nil,
            onMoveEnded: nil,
            onClose: nil,
            onCommand: nil
        )
        record.state.apply(
            snapshot: snapshot,
            recentRhythmWindowHours: recentRhythmWindowHours,
            cardsMovable: cardsMovable
        )
        record.onMoveEnded = onMoveEnded
        record.onClose = onClose
        record.onCommand = onCommand

        let panel = record.panel ?? makePanel(
            kind: kind,
            state: record.state,
            onCommand: onCommand
        )
        panel.onMoveEnded = onMoveEnded
        panel.onCommand = onCommand
        record.panel = panel
        records[kind] = record
        updatePanelCommandHandler(panel, state: record.state, onCommand: onCommand)

        if !panel.isVisible {
            panel.setFrameOrigin(preferredOrigin ?? defaultOrigin(for: kind))
        }
        panel.orderFrontRegardless()
    }

    func update(
        snapshot: FocusPetWidgetSnapshot,
        visibleKinds: Set<DesktopWidgetCardKind>,
        recentRhythmWindowHours: Int,
        cardsMovable: Bool
    ) {
        for kind in visibleKinds {
            records[kind]?.state.apply(
                snapshot: snapshot,
                recentRhythmWindowHours: recentRhythmWindowHours,
                cardsMovable: cardsMovable
            )
        }
    }

    func close(_ kind: DesktopWidgetCardKind) {
        guard let panel = records[kind]?.panel else { return }
        panel.orderOut(nil)
        panel.close()
    }

    func closeAll() {
        for kind in DesktopWidgetCardKind.allCases {
            close(kind)
        }
    }

    func origin(of kind: DesktopWidgetCardKind) -> NSPoint? {
        records[kind]?.panel?.frame.origin
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? DesktopWidgetPanel else { return }
        let kind = panel.kind
        records[kind]?.onMoveEnded?(panel.frame.origin)
        let onClose = records[kind]?.onClose
        records[kind]?.panel = nil
        onClose?()
    }

    private func makePanel(
        kind: DesktopWidgetCardKind,
        state: DesktopWidgetPanelState,
        onCommand: @escaping (DesktopWidgetPanelCommand) -> Void
    ) -> DesktopWidgetPanel {
        let size = kind.panelSize
        let panel = DesktopWidgetPanel(
            kind: kind,
            state: state,
            contentRect: NSRect(origin: defaultOrigin(for: kind), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = kind.title
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.level = Self.desktopWidgetLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.delegate = self

        let rootView = DesktopWidgetPanelView(
            kind: kind,
            state: state,
            onCommand: onCommand
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: size)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
        return panel
    }

    private func updatePanelCommandHandler(
        _ panel: DesktopWidgetPanel,
        state: DesktopWidgetPanelState,
        onCommand: @escaping (DesktopWidgetPanelCommand) -> Void
    ) {
        panel.onCommand = onCommand
        guard let hostingController = panel.contentViewController as? NSHostingController<DesktopWidgetPanelView> else {
            return
        }
        hostingController.rootView = DesktopWidgetPanelView(
            kind: panel.kind,
            state: state,
            onCommand: onCommand
        )
    }

    private func defaultOrigin(for kind: DesktopWidgetCardKind) -> NSPoint {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = kind.panelSize
        let shadowPadding = DesktopWidgetCardKind.panelShadowPadding
        let topY = screenFrame.maxY - size.height + shadowPadding
        let rightX = screenFrame.maxX - size.width + shadowPadding

        switch kind {
        case .recentRhythm:
            return NSPoint(x: rightX, y: topY)
        case .currentStatus:
            let rhythmWidth = DesktopWidgetCardKind.recentRhythm.panelSize.width
            let besideRhythmX = screenFrame.maxX - rhythmWidth - size.width + shadowPadding - 12
            if besideRhythmX >= screenFrame.minX - shadowPadding {
                return NSPoint(x: besideRhythmX, y: topY)
            }
            return NSPoint(x: rightX, y: topY - size.height + shadowPadding - 12)
        }
    }

    private static let desktopWidgetLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow))
    )
}

private final class DesktopWidgetPanel: NSPanel {
    let kind: DesktopWidgetCardKind
    private let state: DesktopWidgetPanelState
    var onMoveEnded: ((NSPoint) -> Void)?
    var onCommand: ((DesktopWidgetPanelCommand) -> Void)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var isDraggingWidget = false
    private let dragThreshold: CGFloat = 1

    init(
        kind: DesktopWidgetCardKind,
        state: DesktopWidgetPanelState,
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.kind = kind
        self.state = state
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if event.clickCount >= 2 {
                onCommand?(.openDashboard)
                resetDragState()
                return
            }
            if state.cardsMovable {
                state.isDragSelected = true
                dragStartMouseLocation = NSEvent.mouseLocation
                dragStartWindowOrigin = frame.origin
                isDraggingWidget = false
                return
            }
            resetDragState()
            state.isDragSelected = false
            super.sendEvent(event)
        case .leftMouseDragged:
            guard updateDragPosition(mouseLocation: NSEvent.mouseLocation) else {
                super.sendEvent(event)
                return
            }
        case .leftMouseUp:
            if state.cardsMovable && state.isDragSelected && isDraggingWidget {
                onMoveEnded?(frame.origin)
                resetDragState()
                return
            }
            resetDragState()
            super.sendEvent(event)
        case .rightMouseDown:
            showContextMenu(for: event)
        default:
            super.sendEvent(event)
        }
    }

    @discardableResult
    private func updateDragPosition(mouseLocation: NSPoint) -> Bool {
        guard state.cardsMovable, state.isDragSelected else {
            return false
        }
        guard let dragStartMouseLocation,
              let dragStartWindowOrigin else {
            return false
        }

        let deltaX = mouseLocation.x - dragStartMouseLocation.x
        let deltaY = mouseLocation.y - dragStartMouseLocation.y
        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard isDraggingWidget || distance >= dragThreshold else {
            return false
        }

        isDraggingWidget = true
        setFrameOrigin(
            NSPoint(
                x: dragStartWindowOrigin.x + deltaX,
                y: dragStartWindowOrigin.y + deltaY
            )
        )
        return true
    }

    private func resetDragState() {
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        isDraggingWidget = false
    }

    private func showContextMenu(for event: NSEvent) {
        let menu = NSMenu(title: kind.title)
        addMenuItem("打开面板", command: .openDashboard, symbolName: "macwindow", to: menu)
        addMenuItem("打开设置", command: .openSettings, symbolName: "gearshape.fill", to: menu)
        menu.addItem(.separator())
        addMenuItem("显示全部状态卡", command: .showAllCards, symbolName: "rectangle.on.rectangle.angled", to: menu)
        addMenuItem("隐藏\(kind.title)", command: .hideCard, symbolName: "rectangle.slash", to: menu)
        addMenuItem("隐藏全部状态卡", command: .hideAllCards, symbolName: "eye.slash.fill", to: menu)

        if let contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        }
    }

    private func addMenuItem(
        _ title: String,
        command: DesktopWidgetPanelCommand,
        symbolName: String,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: #selector(handleContextMenuItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = DesktopWidgetPanelCommandBox(command)
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        menu.addItem(item)
    }

    @objc private func handleContextMenuItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? DesktopWidgetPanelCommandBox else { return }
        onCommand?(box.command)
    }

}

private final class DesktopWidgetPanelCommandBox: NSObject {
    let command: DesktopWidgetPanelCommand

    init(_ command: DesktopWidgetPanelCommand) {
        self.command = command
        super.init()
    }
}

private final class DesktopWidgetPanelState: ObservableObject {
    @Published var snapshot: FocusPetWidgetSnapshot
    @Published var recentRhythmWindowHours: Int
    @Published var cardsMovable: Bool
    @Published var isDragSelected: Bool

    init(snapshot: FocusPetWidgetSnapshot) {
        self.snapshot = snapshot
        self.recentRhythmWindowHours = 4
        self.cardsMovable = true
        self.isDragSelected = false
    }

    func apply(
        snapshot: FocusPetWidgetSnapshot,
        recentRhythmWindowHours: Int,
        cardsMovable: Bool
    ) {
        self.snapshot = snapshot
        self.recentRhythmWindowHours = recentRhythmWindowHours
        self.cardsMovable = cardsMovable
        if !cardsMovable {
            isDragSelected = false
        }
    }
}

private struct DesktopWidgetPanelView: View {
    var kind: DesktopWidgetCardKind
    @ObservedObject var state: DesktopWidgetPanelState
    var onCommand: (DesktopWidgetPanelCommand) -> Void

    var body: some View {
        card
            .frame(width: kind.cardSize.width, height: kind.cardSize.height)
            .padding(DesktopWidgetCardKind.panelShadowPadding)
            .background(Color.clear)
            .overlay {
                if state.isDragSelected {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if state.isDragSelected {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.black.opacity(0.32), lineWidth: 1.2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var card: some View {
        switch kind {
        case .currentStatus:
            FocusPetCurrentStatusWidgetView(snapshot: state.snapshot)
        case .recentRhythm:
            FocusPetRecentRhythmWidgetView(
                snapshot: state.snapshot,
                selectedWindowHours: state.recentRhythmWindowHours,
                showsWindowSwitcher: false
            )
        }
    }
}

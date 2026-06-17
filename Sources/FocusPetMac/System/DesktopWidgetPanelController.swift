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

    fileprivate static let panelShadowPadding: CGFloat = 16
}

@MainActor
final class DesktopWidgetPanelController: NSObject, NSWindowDelegate {
    private struct PanelRecord {
        var state: DesktopWidgetPanelState
        var panel: DesktopWidgetPanel?
        var onMoveEnded: ((NSPoint) -> Void)?
        var onClose: (() -> Void)?
    }

    private var records: [DesktopWidgetCardKind: PanelRecord] = [:]

    func isVisible(_ kind: DesktopWidgetCardKind) -> Bool {
        records[kind]?.panel?.isVisible == true
    }

    func show(
        _ kind: DesktopWidgetCardKind,
        snapshot: FocusPetWidgetSnapshot,
        preferredOrigin: NSPoint?,
        onMoveEnded: @escaping (NSPoint) -> Void,
        onClose: @escaping () -> Void
    ) {
        var record = records[kind] ?? PanelRecord(
            state: DesktopWidgetPanelState(snapshot: snapshot),
            panel: nil,
            onMoveEnded: nil,
            onClose: nil
        )
        record.state.snapshot = snapshot
        record.onMoveEnded = onMoveEnded
        record.onClose = onClose

        let panel = record.panel ?? makePanel(
            kind: kind,
            state: record.state,
            onMoveEnded: onMoveEnded
        )
        record.panel = panel
        records[kind] = record
        updatePanelMoveHandler(panel, onMoveEnded: onMoveEnded)

        if !panel.isVisible {
            panel.setFrameOrigin(preferredOrigin ?? defaultOrigin(for: kind))
        }
        panel.orderFrontRegardless()
    }

    func update(snapshot: FocusPetWidgetSnapshot, visibleKinds: Set<DesktopWidgetCardKind>) {
        for kind in visibleKinds {
            records[kind]?.state.snapshot = snapshot
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
        onMoveEnded: @escaping (NSPoint) -> Void
    ) -> DesktopWidgetPanel {
        let size = kind.panelSize
        let panel = DesktopWidgetPanel(
            kind: kind,
            contentRect: NSRect(origin: defaultOrigin(for: kind), size: size),
            styleMask: [.nonactivatingPanel, .borderless],
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
            onMoveEnded: onMoveEnded
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: size)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
        return panel
    }

    private func updatePanelMoveHandler(
        _ panel: DesktopWidgetPanel,
        onMoveEnded: @escaping (NSPoint) -> Void
    ) {
        guard let hostingController = panel.contentViewController as? NSHostingController<DesktopWidgetPanelView> else {
            return
        }
        hostingController.rootView = DesktopWidgetPanelView(
            kind: panel.kind,
            state: hostingController.rootView.state,
            onMoveEnded: onMoveEnded
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

    init(
        kind: DesktopWidgetCardKind,
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.kind = kind
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class DesktopWidgetPanelState: ObservableObject {
    @Published var snapshot: FocusPetWidgetSnapshot

    init(snapshot: FocusPetWidgetSnapshot) {
        self.snapshot = snapshot
    }
}

private struct DesktopWidgetPanelView: View {
    var kind: DesktopWidgetCardKind
    @ObservedObject var state: DesktopWidgetPanelState
    var onMoveEnded: (NSPoint) -> Void

    var body: some View {
        ZStack {
            card
                .frame(width: kind.cardSize.width, height: kind.cardSize.height)
            DesktopWidgetDragSurface(onMoveEnded: onMoveEnded)
                .frame(width: kind.cardSize.width, height: kind.cardSize.height)
        }
        .padding(DesktopWidgetCardKind.panelShadowPadding)
        .background(Color.clear)
    }

    @ViewBuilder
    private var card: some View {
        switch kind {
        case .currentStatus:
            FocusPetCurrentStatusWidgetView(snapshot: state.snapshot)
        case .recentRhythm:
            FocusPetRecentRhythmWidgetView(snapshot: state.snapshot, selectedWindowHours: 4)
        }
    }
}

private struct DesktopWidgetDragSurface: NSViewRepresentable {
    var onMoveEnded: (NSPoint) -> Void

    func makeNSView(context: Context) -> DesktopWidgetDragView {
        let view = DesktopWidgetDragView()
        view.onMoveEnded = onMoveEnded
        return view
    }

    func updateNSView(_ nsView: DesktopWidgetDragView, context: Context) {
        nsView.onMoveEnded = onMoveEnded
    }
}

private final class DesktopWidgetDragView: NSView {
    private var mouseDownLocation: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    var onMoveEnded: ((NSPoint) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        mouseDownWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let mouseDownLocation,
              let mouseDownWindowOrigin else { return }
        let mouseLocation = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(
                x: mouseDownWindowOrigin.x + mouseLocation.x - mouseDownLocation.x,
                y: mouseDownWindowOrigin.y + mouseLocation.y - mouseDownLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        if let origin = window?.frame.origin {
            onMoveEnded?(origin)
        }
        mouseDownLocation = nil
        mouseDownWindowOrigin = nil
    }
}

import AppKit
import FocusPetCore
import FocusPetResources
import SwiftUI

private enum DashboardLayout {
    static let sidebarWidth: CGFloat = 218
    static let contentInset: CGFloat = 14
    static let shellCornerRadius: CGFloat = 16
    static let titlebarClearance: CGFloat = 10
    static let cardGap: CGFloat = 14
    static let todayCanvasMinHeight: CGFloat = 840
    static let todayTimelineMinHeight: CGFloat = 300
    static let todayInsightsMinHeight: CGFloat = 300
    static let todayStackedTopBreakpoint: CGFloat = 760
}

private enum DashboardInteraction {
    static let contentSwitchDelayNanoseconds: UInt64 = 45_000_000
}

struct MainDashboardView: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var contentTab: DashboardTab = .today
    @State private var pendingContentTab: DashboardTab?

    var body: some View {
        ZStack {
            DashboardLiquidBackground()
            HStack(spacing: DashboardLayout.cardGap) {
                DashboardSidebar(currentSelection: contentTab) { tab in
                    scheduleContentSwitch(to: tab)
                    model.presentPetForDashboard(tab: tab)
                }
                    .frame(width: DashboardLayout.sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 0) {
                    currentTabView
                        .padding(DashboardLayout.contentInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, DashboardLayout.titlebarClearance)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .dashboardPetAnchor(.dashboardPanel)
            }

            DashboardEventBridge(contentTab: $contentTab)
        }
        .background {
            DashboardWindowLifecycleReporter(model: model)
                .allowsHitTesting(false)
        }
        .foregroundStyle(FPColor.textPrimary)
        .tint(FPColor.focus500)
        .preferredColorScheme(.light)
        .onChange(of: contentTab) { _, tab in
            if pendingContentTab != nil && pendingContentTab != tab {
                pendingContentTab = nil
            }
        }
        .onDisappear {
            model.dashboardWindowDidDismiss()
        }
    }

    @ViewBuilder
    private var currentTabView: some View {
        switch contentTab {
        case .today:
            TodayView()
        case .sessions:
            SessionsView()
        case .pet:
            PetView()
        case .settings:
            SettingsView()
        }
    }

    private func scheduleContentSwitch(to tab: DashboardTab) {
        guard contentTab != tab else { return }
        pendingContentTab = tab
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: DashboardInteraction.contentSwitchDelayNanoseconds)
            guard pendingContentTab == tab else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                contentTab = tab
            }
            pendingContentTab = nil
        }
    }
}

private struct DashboardEventBridge: View {
    @EnvironmentObject private var model: FocusPetModel
    @Environment(\.openWindow) private var openWindow
    @Binding var contentTab: DashboardTab

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                contentTab = model.selectedTab
                model.registerOpenDashboardRequest { tab in
                    contentTab = tab
                    model.selectedTab = tab
                    openWindow(id: "dashboard")
                }
                Task { @MainActor in
                    await Task.yield()
                    model.dashboardWindowDidActivate()
                }
            }
            .onChange(of: contentTab) { _, tab in
                guard model.selectedTab != tab else { return }
                model.selectedTab = tab
            }
            .onChange(of: model.selectedTab) { _, tab in
                guard contentTab != tab else { return }
                contentTab = tab
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusPetOpenDashboardRequested)) { notification in
                model.openDashboard(tab: notification.object as? DashboardTab ?? model.selectedTab)
            }
    }
}

private struct DashboardWindowLifecycleReporter: NSViewRepresentable {
    weak var model: FocusPetModel?

    func makeNSView(context: Context) -> DashboardWindowLifecycleReportingView {
        let view = DashboardWindowLifecycleReportingView()
        view.dismiss = { [weak model] in
            Task { @MainActor in
                model?.dashboardWindowDidDismiss()
            }
        }
        view.activate = { [weak model] in
            Task { @MainActor in
                model?.dashboardWindowDidActivate()
            }
        }
        return view
    }

    func updateNSView(_ nsView: DashboardWindowLifecycleReportingView, context: Context) {
        nsView.configureWindowObservers()
    }
}

@MainActor
private final class DashboardWindowLifecycleReportingView: NSView {
    var dismiss: () -> Void = {}
    var activate: () -> Void = {}
    private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []
    private weak var observedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowObservers()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func configureWindowObservers() {
        guard observedWindow !== window else { return }
        clearWindowObservers()
        guard let window else { return }
        observedWindow = window
        let names: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.willMiniaturizeNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didExposeNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        observerTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWindowNotification(name)
                }
            }
        }
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.dismiss()
                }
            }
        )
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.activate()
                }
            }
        )
    }

    private func handleWindowNotification(_ name: Notification.Name) {
        guard let window = observedWindow else { return }
        switch name {
        case NSWindow.willCloseNotification,
            NSWindow.willMiniaturizeNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResignMainNotification:
            dismiss()
        case NSWindow.didChangeOcclusionStateNotification:
            if NSApp.isActive,
               window.isVisible,
               !window.isMiniaturized,
               window.occlusionState.contains(.visible),
               window.isKeyWindow || window.isMainWindow || NSApp.keyWindow === window || NSApp.mainWindow === window {
                activate()
            } else {
                dismiss()
            }
        default:
            activate()
        }
    }

    private func clearWindowObservers() {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens = []
        observedWindow = nil
    }
}

private struct DashboardPetAnchorModifier: ViewModifier {
    @EnvironmentObject private var model: FocusPetModel
    var anchor: DashboardPetAnchor

    func body(content: Content) -> some View {
        content.background {
            DashboardPetAnchorReporter(anchor: anchor, model: model)
                .allowsHitTesting(false)
        }
    }
}

private struct DashboardPetAnchorReporter: NSViewRepresentable {
    var anchor: DashboardPetAnchor
    weak var model: FocusPetModel?

    func makeNSView(context: Context) -> DashboardPetAnchorReportingView {
        let view = DashboardPetAnchorReportingView()
        view.anchor = anchor
        view.report = { [weak model] anchor, frame in
            Task { @MainActor in
                model?.updateDashboardPetAnchor(anchor, frame: frame)
            }
        }
        view.dismiss = { [weak model] in
            Task { @MainActor in
                model?.dashboardWindowDidDismiss()
            }
        }
        view.activate = { [weak model] in
            Task { @MainActor in
                model?.dashboardWindowDidActivate()
            }
        }
        return view
    }

    func updateNSView(_ nsView: DashboardPetAnchorReportingView, context: Context) {
        nsView.anchor = anchor
        nsView.reportFrameSoon()
    }
}

@MainActor
private final class DashboardPetAnchorReportingView: NSView {
    var anchor: DashboardPetAnchor = .todayFocusCard
    var report: (DashboardPetAnchor, CGRect) -> Void = { _, _ in }
    var dismiss: () -> Void = {}
    var activate: () -> Void = {}
    private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []

    override func layout() {
        super.layout()
        reportFrameSoon()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowObservers()
        reportFrameSoon()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func reportFrameSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.reportFrame()
        }
    }

    private func reportFrame() {
        guard let window, bounds.width > 1, bounds.height > 1 else { return }
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY)
        ]
        let screenPoints = corners.map { point in
            window.convertPoint(toScreen: convert(point, to: nil))
        }
        guard let minX = screenPoints.map(\.x).min(),
              let maxX = screenPoints.map(\.x).max(),
              let minY = screenPoints.map(\.y).min(),
              let maxY = screenPoints.map(\.y).max() else { return }
        let frameInScreen = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        report(anchor, frameInScreen)
    }

    private func configureWindowObservers() {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens = []
        guard let window else { return }
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didExposeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willMiniaturizeNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.willCloseNotification
        ]
        observerTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    if name == NSWindow.willMiniaturizeNotification || name == NSWindow.didMiniaturizeNotification || name == NSWindow.willCloseNotification {
                        self?.dismiss()
                    } else {
                        self?.reportFrameSoon()
                        self?.activate()
                    }
                }
            }
        }
    }
}

private enum DashboardPalette {
    static let backgroundTop = FPColor.appBackgroundTop
    static let backgroundMiddle = FPColor.appBackgroundMiddle
    static let backgroundBottom = FPColor.appBackgroundBottom
    static let sidebarFill = FPColor.sidebarTop.opacity(0.84)
    static let contentFill = FPColor.card.opacity(0.64)
    static let cardFill = FPColor.card
    static let elevatedCardFill = FPColor.card
    static let sidebarButtonHoverFill = FPColor.cardHover
    static let sidebarSelectedGradient = LinearGradient(
        colors: [
            FPColor.card,
            FPColor.focus100,
            FPColor.focus050
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let controlFill = FPColor.controlSurface
    static let rowFill = FPColor.cardSoft
    static let trackFill = FPChartPalette.neutralTrack
    static let border = FPColor.borderDefault
    static let strongBorder = FPColor.borderStrong
    static let innerStroke = FPColor.borderSoft
    static let glassRim = FPColor.borderSoft
    static let glassInnerShadow = FPColor.focus600.opacity(0.10)
    static let glassRefractionBlue = FPColor.focus300.opacity(0.24)
    static let glassRefractionViolet = FPColor.focus200.opacity(0.16)
    static let primaryText = FPColor.textPrimary
    static let secondaryText = FPColor.textSecondary
    static let mutedText = FPColor.textTertiary
    static let accent = FPColor.focus500
    static let gold = FPColor.warning
    static let focusBlue = FPChartPalette.focus
    static let distractedPeach = FPChartPalette.distracted
    static let distractedRed = FPChartPalette.distractedStrong
    static let restGreen = FPChartPalette.rest
    static let awayPurple = FPColor.away500
    static let pauseGray = FPColor.away500
    static let appRose = FPColor.distracted500
    static let appCyan = FPColor.systemCyan500
    static let appIndigo = FPColor.focus600
    static let appMint = FPColor.rest500
    static let shadow = FPColor.focus600.opacity(0.08)
    static let focusTint = FPColor.focus500
    static let focusInk = FPColor.focus600
    static let warmFocus = FPColor.distracted500
    static let surfaceHighlight = LinearGradient(
        colors: [
            FPColor.card.opacity(0.72),
            FPColor.card.opacity(0.24),
            FPColor.card.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct DashboardLiquidBackground: View {
    var body: some View {
        FPPageBackground()
    }
}

private struct DashboardSidebar: View {
    var currentSelection: DashboardTab
    var onSelect: (DashboardTab) -> Void
    @State private var selection: DashboardTab = .today

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 30)

                HStack(spacing: 12) {
                    DashboardAppIconMark()
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Focus Pet")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardPalette.primaryText)
                            .lineLimit(1)
                        Text("陪你稳住专注")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardPalette.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 24)

                VStack(spacing: 10) {
                    ForEach(DashboardTab.allCases) { tab in
                        DashboardSidebarButton(tab: tab, isSelected: selection == tab) {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            if selection != tab {
                                withAnimation(.snappy(duration: 0.16, extraBounce: 0.02)) {
                                    selection = tab
                                }
                            }
                            onSelect(tab)
                        }
                    }
                }
                .padding(.horizontal, 18)

                Spacer(minLength: 18)

                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 184)
                    .dashboardPetAnchor(.sidebarPetDock)
                    .padding(.bottom, 18)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background {
                FPSidebarBackground()
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(FPColor.borderSoft)
                            .frame(width: 1)
                    }
            }
            .onAppear {
                selection = currentSelection
            }
            .onChange(of: currentSelection) { _, tab in
                guard selection != tab else { return }
                withAnimation(.snappy(duration: 0.16, extraBounce: 0.02)) {
                    selection = tab
                }
            }
        }
    }
}

private struct DashboardAppIconMark: View {
    private static let appIcon: NSImage = {
        if let url = FocusPetPackagedResources.url(
            inBundleNamed: "FocusPet_FocusPetMac.bundle",
            forResource: "AppIcon",
            withExtension: "png",
            fallback: Bundle.module.url(forResource: "AppIcon", withExtension: "png")
        ),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil) ?? NSImage()
    }()

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            FPColor.rest100.opacity(0.86),
                            FPColor.focus100.opacity(0.72)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 56
                    )
                )

            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 47, height: 47)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.82), lineWidth: 1.1)
                }

            Circle()
                .fill(Color.white.opacity(0.32))
                .frame(width: 18, height: 18)
                .blur(radius: 4)
                .offset(x: -12, y: -13)
        }
        .overlay {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.86),
                            DashboardPalette.border.opacity(0.72),
                            DashboardPalette.focusBlue.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .shadow(color: DashboardPalette.shadow.opacity(0.18), radius: 5, x: 0, y: 2)
        .accessibilityHidden(true)
    }
}

private struct DashboardSidebarButton: View {
    var tab: DashboardTab
    var isSelected: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            FPSidebarItem(title: tab.title, systemImage: tab.symbolName, isSelected: isSelected)
                .background {
                    if isHovering && !isSelected {
                        RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                            .fill(FPColor.cardHover)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous))
        }
        .buttonStyle(DashboardSidebarButtonPressStyle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = inside
            }
        }
        .help(tab.title)
    }

    private var backgroundFill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(DashboardPalette.sidebarSelectedGradient)
        }
        return AnyShapeStyle(DashboardPalette.sidebarButtonHoverFill)
    }

    private var iconFill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        DashboardPalette.accent.opacity(0.18),
                        DashboardPalette.restGreen.opacity(0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(isHovering ? 0.52 : 0.26))
    }
}

private struct DashboardSidebarButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .brightness(configuration.isPressed ? -0.018 : 0)
            .animation(.linear(duration: 0.045), value: configuration.isPressed)
    }
}

private enum DashboardDateFormatters {
    private static let todayFormatterKey = "FocusPetDashboard.todayFormatter"

    static func todayLabel(for date: Date = Date()) -> String {
        if let formatter = Thread.current.threadDictionary[todayFormatterKey] as? DateFormatter {
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        Thread.current.threadDictionary[todayFormatterKey] = formatter
        return formatter.string(from: date)
    }
}

private struct DashboardPageHeader: View {
    var tab: DashboardTab

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tab.title)
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(tab.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 24)

            HStack(spacing: 20) {
                HeaderSkyMark()
                    .frame(width: 104, height: 44)
                Label(todayLabel, systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
            }
            .padding(.top, 8)
        }
    }

    private var todayLabel: String {
        DashboardDateFormatters.todayLabel()
    }
}

private struct HeaderSkyMark: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: proxy.size.width * 0.06, y: proxy.size.height * 0.70))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.18, y: proxy.size.height * 0.60))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.32, y: proxy.size.height * 0.66))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.46, y: proxy.size.height * 0.54))
                    path.addLine(to: CGPoint(x: proxy.size.width * 0.70, y: proxy.size.height * 0.70))
                    path.closeSubpath()
                }
                .fill(DashboardPalette.focusBlue.opacity(0.16))

                CloudShape()
                    .fill(Color.white.opacity(0.46))
                    .frame(width: proxy.size.width * 0.56, height: proxy.size.height * 0.44)
                    .position(x: proxy.size.width * 0.55, y: proxy.size.height * 0.48)

                ShootingStar()
                    .stroke(DashboardPalette.gold.opacity(0.86), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: proxy.size.width * 0.36, height: proxy.size.height * 0.30)
                    .position(x: proxy.size.width * 0.20, y: proxy.size.height * 0.30)
            }
        }
    }
}

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.05, y: rect.midY - rect.height * 0.20, width: rect.width * 0.34, height: rect.height * 0.42))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.05, width: rect.width * 0.38, height: rect.height * 0.56))
        path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.48, y: rect.midY - rect.height * 0.14, width: rect.width * 0.38, height: rect.height * 0.42))
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.12, y: rect.midY - rect.height * 0.02, width: rect.width * 0.76, height: rect.height * 0.32), cornerSize: CGSize(width: rect.height * 0.16, height: rect.height * 0.16))
        return path
    }
}

private struct ShootingStar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var model: FocusPetModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liquidMotionPhase: CGFloat = 0.5
    @State private var contentRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuStatusHeader()
            MenuStatusStrip()
            MenuGlassDivider()
            MenuActionGrid()
            MenuGlassDivider()
            HStack {
                Label(model.reminderPauseTitle, systemImage: "bell.badge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(.borderless)
                .help("退出 Focus Pet")
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background {
            FPGlassLayer(
                role: .menu,
                cornerRadius: 20,
                tint: model.currentDecision.state.timelineColor,
                isSelected: true,
                intensity: 1.04,
                motionPhase: liquidMotionPhase,
                motionStrength: reduceMotion ? 0 : 1.04
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .background(MenuBarWindowChromeCleaner().allowsHitTesting(false))
        .opacity(contentRevealed ? 1 : 0.96)
        .scaleEffect(contentRevealed ? 1 : 0.986, anchor: .top)
        .animation(.smooth(duration: 0.28), value: contentRevealed)
        .animation(.smooth(duration: 0.46), value: menuVisualKey)
        .onAppear {
            model.start()
            contentRevealed = true
            triggerLiquidSlide()
        }
        .onAppear {
            model.registerOpenDashboardRequest { tab in
                model.selectedTab = tab
                openWindow(id: "dashboard")
            }
        }
        .onChange(of: menuVisualKey) { _, _ in
            triggerLiquidSlide()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPetOpenDashboardRequested)) { notification in
            model.openDashboard(tab: notification.object as? DashboardTab ?? model.selectedTab)
        }
    }

    private var menuVisualKey: String {
        [
            model.currentDecision.state.id,
            model.activeFocusSession?.id ?? "no-focus",
            model.activeBreakSession?.id ?? "no-break",
            model.settings.reminder.pauseUntil.map { String(Int($0.timeIntervalSince1970)) } ?? "reminders-on",
            model.settings.pet.hidden ? "pet-hidden" : "pet-visible",
            model.currentStatusDesktopWidgetIsVisible ? "current-widget-visible" : "current-widget-hidden",
            model.recentRhythmDesktopWidgetIsVisible ? "rhythm-widget-visible" : "rhythm-widget-hidden"
        ].joined(separator: "|")
    }

    private func triggerLiquidSlide() {
        guard !reduceMotion else {
            liquidMotionPhase = 0.5
            return
        }
        liquidMotionPhase = -0.35
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.78)) {
                liquidMotionPhase = 1.16
            }
        }
    }
}

private struct MenuBarWindowChromeCleaner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            self.configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.superview?.wantsLayer = true
        window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private struct MenuGlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        DashboardPalette.innerStroke.opacity(0.74),
                        Color.white.opacity(0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

private struct MenuStatusHeader: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(model.currentDecision.state.timelineColor.opacity(0.18))
                Image(systemName: model.currentDecision.state.symbolName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(model.currentDecision.state.timelineColor)
            }
            .frame(width: 42, height: 42)
            .fpGlassBackground(
                role: .badge,
                cornerRadius: 21,
                tint: model.currentDecision.state.timelineColor,
                isSelected: true,
                intensity: 0.9
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.currentDecision.state.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(FocusPetFormatters.percentage(model.currentDecision.confidence))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text("今日专注 \(FocusPetFormatters.duration(model.summary.focusSeconds))")
                    .font(.headline)
                Text(model.currentSnapshot.appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.42), value: model.currentDecision.state.id)
        .animation(.smooth(duration: 0.36), value: model.currentSnapshot.appName)
    }
}

private struct MenuStatusStrip: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        HStack(spacing: 8) {
            MenuMetricChip(title: "专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), tint: FocusPetCore.FocusState.focus.timelineColor)
            MenuMetricChip(title: "走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), tint: FocusPetCore.FocusState.distracted.timelineColor)
            MenuMetricChip(title: "休息", value: FocusPetFormatters.duration(model.summary.breakSeconds), tint: FocusPetCore.FocusState.breakTime.timelineColor)
        }
    }
}

private struct MenuMetricChip: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .fpGlassBackground(role: .control, cornerRadius: 8, tint: tint, intensity: 0.82)
    }
}

private struct MenuActionGrid: View {
    @EnvironmentObject private var model: FocusPetModel

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            MenuActionButton(title: "打开面板", symbol: "macwindow", tint: FPColor.focus500) {
                model.openDashboard(tab: .today)
            }

            MenuActionButton(title: "设置", symbol: "gearshape.fill", tint: FPColor.textTertiary) {
                model.openDashboard(tab: .settings)
            }

            MenuActionButton(
                title: model.desktopWidgetPanelIsVisible ? "隐藏全部状态卡" : "桌面状态卡",
                symbol: model.desktopWidgetPanelIsVisible ? "rectangle.slash" : "rectangle.on.rectangle.angled",
                tint: DashboardPalette.focusBlue
            ) {
                model.toggleDesktopWidgetPanel()
            }
            .menuActionTransition()

            if let active = model.activeFocusSession {
                MenuActionButton(title: "完成任务", symbol: "checkmark.circle.fill", tint: DashboardPalette.focusBlue) {
                    model.finishCurrentFocusSession(completed: true)
                }
                .help(active.taskName)
                .menuActionTransition()
            }

            if model.activeBreakSession == nil {
                MenuActionButton(title: "休息 \(model.settings.breakMinutes) 分钟", symbol: "cup.and.saucer.fill", tint: DashboardPalette.restGreen) {
                    model.toggleBreakFromPet()
                }
                .menuActionTransition()
            } else {
                MenuActionButton(title: "结束休息", symbol: "checkmark.circle.fill", tint: DashboardPalette.restGreen) {
                    model.toggleBreakFromPet()
                }
                .menuActionTransition()
            }

            if let pauseUntil = model.settings.reminder.pauseUntil, pauseUntil > Date() {
                MenuActionButton(title: "恢复提醒", symbol: "bell.fill", tint: FPColor.warning) {
                    model.resumeReminders()
                }
                .menuActionTransition()
            } else {
                MenuActionButton(title: "暂停提醒", symbol: "bell.slash.fill", tint: FPColor.warning) {
                    model.pauseReminders()
                }
                .menuActionTransition()
            }

            MenuActionButton(
                title: petVisibilityActionTitle,
                symbol: petVisibilityActionSymbol,
                tint: FPColor.petWarm500
            ) {
                model.togglePetHidden()
            }
            .menuActionTransition()
        }
        .animation(.smooth(duration: 0.34), value: actionStateKey)
    }

    private var actionStateKey: String {
        [
            model.activeFocusSession?.id ?? "no-focus",
            model.activeBreakSession?.id ?? "no-break",
            model.settings.reminder.pauseUntil.map { String(Int($0.timeIntervalSince1970)) } ?? "reminders-on",
            model.settings.pet.hidden ? "pet-hidden" : "pet-visible",
            model.hasAvailablePetPacks ? "pet-packs" : "no-pet-packs",
            model.currentStatusDesktopWidgetIsVisible ? "current-widget-visible" : "current-widget-hidden",
            model.recentRhythmDesktopWidgetIsVisible ? "rhythm-widget-visible" : "rhythm-widget-hidden"
        ].joined(separator: "|")
    }

    private var petVisibilityActionTitle: String {
        guard model.hasAvailablePetPacks else { return "导入桌宠资源" }
        return model.settings.pet.hidden ? "显示桌宠" : "隐藏桌宠"
    }

    private var petVisibilityActionSymbol: String {
        guard model.hasAvailablePetPacks else { return "square.and.arrow.down" }
        return model.settings.pet.hidden ? "eye.fill" : "eye.slash.fill"
    }
}

private struct MenuActionButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var action: () -> Void
    @State private var isHovering = false
    @State private var hoverMotionPhase: CGFloat = 0.5

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 42)
            .fpGlassBackground(
                role: .button,
                cornerRadius: 8,
                tint: tint,
                isSelected: isHovering,
                intensity: isHovering ? 0.98 : 0.88,
                motionPhase: hoverMotionPhase,
                motionStrength: isHovering ? 0.34 : 0
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.014 : 1)
        .animation(.smooth(duration: 0.16), value: isHovering)
        .onHover { inside in
            withAnimation(.smooth(duration: 0.16)) {
                isHovering = inside
            }
            guard inside else { return }
            hoverMotionPhase = -0.2
            DispatchQueue.main.async {
                withAnimation(.smooth(duration: 0.42)) {
                    hoverMotionPhase = 1.1
                }
            }
        }
        .help(title)
    }
}

private extension View {
    func menuActionTransition() -> some View {
        transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
    }
}

struct TodayView: View {
    var body: some View {
        GeometryReader { proxy in
            let topBreathingRoom: CGFloat = 8
            let bottomBreathingRoom: CGFloat = 0
            let stacksTopCards = proxy.size.width < DashboardLayout.todayStackedTopBreakpoint
            let stackedHeightAdjustment = stacksTopCards ? FPLayout.todayTopCardHeight + DashboardLayout.cardGap : 0
            let canvasHeight = max(
                proxy.size.height - topBreathingRoom - bottomBreathingRoom,
                DashboardLayout.todayCanvasMinHeight + stackedHeightAdjustment
            )
            ScrollView(.vertical) {
                TodayDashboardCanvas(size: CGSize(width: proxy.size.width, height: canvasHeight))
                    .frame(width: proxy.size.width, height: canvasHeight, alignment: .topLeading)
                    .padding(.top, topBreathingRoom)
                    .padding(.bottom, bottomBreathingRoom)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct TodayDashboardCanvas: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var selectedInsightWindow: ActivityTimelineWindow = .fourHours
    var size: CGSize

    var body: some View {
        let now = Date()
        let spacing = DashboardLayout.cardGap
        let stacksTopCards = size.width < DashboardLayout.todayStackedTopBreakpoint
        let contentHeight = max(size.height, DashboardLayout.todayCanvasMinHeight)
        let rowSpace = max(0, contentHeight - spacing * 2)
        let topHeight = FPLayout.todayTopCardHeight
        let topSectionHeight = stacksTopCards ? topHeight * 2 + spacing : topHeight
        let timelineHeight = clamped(rowSpace * 0.36, min: DashboardLayout.todayTimelineMinHeight, max: 340)
        let insightsHeight = max(DashboardLayout.todayInsightsMinHeight, rowSpace - topSectionHeight - timelineHeight)
        let breakWidth = clamped(
            size.width * 0.32,
            min: FPLayout.todayBreakMinWidth,
            max: FPLayout.todayBreakMaxWidth
        )
        let insightSnapshot = TodayWindowInsightSnapshot(
            window: selectedInsightWindow,
            stateSegments: model.stateSegments,
            appUsage: model.appUsage,
            now: now
        )

        VStack(alignment: .leading, spacing: spacing) {
            Group {
                if stacksTopCards {
                    VStack(alignment: .leading, spacing: spacing) {
                        TodayFocusFeatureCard()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(height: topHeight)
                        BreakDurationControl()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(height: topHeight)
                            .dashboardPetAnchor(.todayBreakControl)
                    }
                } else {
                    HStack(alignment: .top, spacing: spacing) {
                        TodayFocusFeatureCard()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(height: topHeight)
                            .layoutPriority(1)
                        BreakDurationControl()
                            .frame(
                                width: min(
                                    breakWidth,
                                    max(FPLayout.todayBreakMinWidth, size.width * FPLayout.todayBreakResponsiveWidthRatio)
                                ),
                                height: topHeight
                            )
                            .dashboardPetAnchor(.todayBreakControl)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: topSectionHeight, maxHeight: topSectionHeight)

            InputActivityTimelinePanel(selectedWindow: $selectedInsightWindow, now: now)
                .frame(maxWidth: .infinity, minHeight: timelineHeight, maxHeight: timelineHeight)
                .dashboardPetAnchor(.todayTimeline)

            TodayInsightsGrid(snapshot: insightSnapshot)
                .frame(maxWidth: .infinity, minHeight: insightsHeight, maxHeight: insightsHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.snappy(duration: 0.34, extraBounce: 0.03), value: selectedInsightWindow)

    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

private struct TodayFocusFeatureCard: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        let workload = model.todayWorkload
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日态势")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusTint)
                    Text(statusHeadline)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(currentState.fpStatus.strongText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(statusSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FPColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(statusDuration)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(currentState.fpStatus.strongText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    Text(statusDurationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FPColor.textSecondary)
                    Text(secondaryDurationLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryDurationTint)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            TodaySignalStrip(items: [
                TodaySignalItem(
                    title: currentState.title,
                    symbol: currentState.symbolName,
                    tint: statusTint,
                    minWidth: 118
                ),
                TodaySignalItem(
                    title: FocusPetFormatters.contextSwitches(workload.contextSwitchCount),
                    symbol: "arrow.triangle.2.circlepath",
                    tint: FPChartPalette.inputSwitch,
                    minWidth: 156
                ),
                TodaySignalItem(
                    title: "键盘 \(FocusPetFormatters.compactCount(workload.estimatedTypedCharacters)) 次",
                    symbol: "keyboard",
                    tint: FPChartPalette.inputKeyboardStrong,
                    minWidth: 156
                ),
                TodaySignalItem(
                    title: "鼠标 \(FocusPetFormatters.compactCount(workload.pointerActionCount)) 次",
                    symbol: "cursorarrow.click",
                    tint: FPChartPalette.inputPointerStrong,
                    minWidth: 156
                )
            ])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .todayGlassFeatureCard(status: currentState.fpStatus, tint: statusTint, padding: 20, role: .hero)
        .dashboardPetAnchor(.todayFocusCard)
    }

    private var currentState: FocusPetCore.FocusState {
        model.currentDecision.state
    }

    private var statusTint: Color {
        currentState.timelineColor
    }

    private var statusHeadline: String {
        switch currentState {
        case .focus:
            return model.summary.focusSeconds == 0 ? "正在自动识别" : "已进入稳定工作"
        case .distracted:
            return "注意力正在偏离"
        case .breakTime:
            return "正在休息恢复"
        case .away:
            return "暂离中"
        }
    }

    private var statusSubtitle: String {
        switch currentState {
        case .focus:
            return "App、输入和切换节奏保持稳定"
        case .distracted:
            return "建议先回到当前任务两分钟"
        case .breakTime:
            return "这段时间会单独记录"
        case .away:
            return "回来后继续接上今日记录"
        }
    }

    private var statusDuration: String {
        FocusPetFormatters.duration(todaySeconds(for: currentState))
    }

    private var statusDurationLabel: String {
        switch currentState {
        case .focus:
            return "今日专注"
        case .distracted:
            return "今日走神"
        case .breakTime:
            return "今日休息"
        case .away:
            return "今日暂离"
        }
    }

    private var secondaryDurationLabel: String {
        if currentState == .distracted {
            return "今日专注 \(FocusPetFormatters.duration(model.summary.focusSeconds))"
        }
        return "今日走神 \(FocusPetFormatters.duration(model.summary.distractedSeconds))"
    }

    private var secondaryDurationTint: Color {
        currentState == .distracted ? FPColor.focus600.opacity(0.72) : FPColor.distracted600
    }

    private func todaySeconds(for state: FocusPetCore.FocusState) -> Int {
        switch state {
        case .focus:
            return model.summary.focusSeconds
        case .distracted:
            return model.summary.distractedSeconds
        case .breakTime:
            return model.summary.breakSeconds
        case .away:
            return model.summary.awaySeconds
        }
    }
}

private struct TodayFocusBackdrop: View {
    var tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.86),
                        tint.opacity(0.12),
                        DashboardPalette.elevatedCardFill
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.11),
                                DashboardPalette.restGreen.opacity(0.08),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 42)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    ForEach(0..<12, id: \.self) { index in
                        Capsule()
                            .fill(tint.opacity(index.isMultiple(of: 3) ? 0.16 : 0.08))
                            .frame(width: 2, height: CGFloat(10 + (index % 4) * 5))
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 18)
            }
    }
}

private struct TodayGlassFeatureCardModifier: ViewModifier {
    var status: FPStatus
    var tint: Color
    var padding: CGFloat
    var radius: CGFloat
    var role: FPGlassLayerRole

    func body(content: Content) -> some View {
        content
            .padding(.leading, FPCardMetrics.semanticContentLeadingReserve)
            .padding(padding)
            .background {
                ZStack(alignment: .leading) {
                    if role == .hero {
                        TodayFocusBackdrop(tint: tint)
                            .opacity(0.68)
                            .padding(2)
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.10),
                                        Color.white.opacity(0.30),
                                        FPColor.cardSoft.opacity(0.34)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    FPGlassLayer(
                        role: role,
                        cornerRadius: radius,
                        tint: tint,
                        isSelected: true,
                        intensity: role == .hero ? 1.08 : 0.98
                    )

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    status.softBackground.opacity(role == .hero ? 0.24 : 0.18),
                                    Color.white.opacity(role == .hero ? 0.12 : 0.06),
                                    tint.opacity(role == .hero ? 0.06 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Capsule()
                        .fill(tint.opacity(role == .hero ? 0.90 : 0.74))
                        .frame(width: FPCardMetrics.semanticStripWidth)
                        .padding(.vertical, FPCardMetrics.semanticStripVerticalInset)
                        .padding(.leading, FPCardMetrics.semanticStripLeadingInset)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                status.border.opacity(0.78),
                                tint.opacity(role == .hero ? 0.28 : 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: tint.opacity(role == .hero ? 0.12 : 0.08), radius: role == .hero ? 26 : 18, x: 0, y: role == .hero ? 14 : 10)
    }
}

private extension View {
    func todayGlassFeatureCard(
        status: FPStatus,
        tint: Color,
        padding: CGFloat,
        radius: CGFloat = FPRadius.large,
        role: FPGlassLayerRole
    ) -> some View {
        modifier(TodayGlassFeatureCardModifier(
            status: status,
            tint: tint,
            padding: padding,
            radius: radius,
            role: role
        ))
    }
}

private struct TodaySignalItem: Identifiable {
    var title: String
    var symbol: String
    var tint: Color
    var minWidth: CGFloat

    var id: String {
        "\(symbol)-\(title)"
    }
}

private struct TodaySignalStrip: View {
    var items: [TodaySignalItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    TodaySignalChip(item: item)
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(items.prefix(2)) { item in
                        TodaySignalChip(item: item)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(items.dropFirst(2)) { item in
                        TodaySignalChip(item: item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct TodaySignalChip: View {
    var item: TodaySignalItem

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16)

            Text(item.title)
                .font(FPTypography.badge)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .layoutPriority(1)
        }
        .foregroundStyle(item.tint)
        .padding(.horizontal, 13)
        .frame(
            minWidth: item.minWidth,
            minHeight: FPSize.badgeHeight,
            alignment: .center
        )
        .background {
            Capsule()
                .fill(item.tint.opacity(0.10))
            FPGlassLayer(
                role: .badge,
                cornerRadius: FPRadius.pill,
                tint: item.tint,
                isSelected: true,
                intensity: 0.92
            )
        }
        .overlay {
            Capsule().stroke(item.tint.opacity(0.18), lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

private struct TodayStateSummaryStrip: View {
    @EnvironmentObject private var model: FocusPetModel

    private var items: [StateDurationItem] {
        [
            StateDurationItem(state: .distracted, seconds: model.summary.distractedSeconds),
            StateDurationItem(state: .breakTime, seconds: model.summary.breakSeconds),
            StateDurationItem(state: .away, seconds: model.summary.awaySeconds)
        ]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                ForEach(items) { item in
                    TodayStateRibbonCard(item: item)
                }
            }

            VStack(spacing: 10) {
                ForEach(items) { item in
                    TodayStateRibbonCard(item: item)
                }
            }
        }
    }
}

private struct TodayStateRibbonCard: View {
    var item: StateDurationItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.state.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(item.state.timelineColor.opacity(0.72), in: Circle())
                .overlay {
                    Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.state.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
                Text(FocusPetFormatters.duration(item.seconds))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    item.state.timelineColor.opacity(0.34),
                    item.state.timelineColor.opacity(0.12),
                    DashboardPalette.elevatedCardFill
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(item.state.timelineColor.opacity(0.86))
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(item.state.timelineColor.opacity(0.36), lineWidth: 1)
        }
        .liquidGlassSurface(cornerRadius: 12)
        .shadow(color: DashboardPalette.shadow.opacity(0.10), radius: 2, x: 0, y: 1)
    }
}

private struct TodayInsightsGrid: View {
    var snapshot: TodayWindowInsightSnapshot

    var body: some View {
        GeometryReader { proxy in
            let spacing = DashboardLayout.cardGap
            let availableWidth = max(0, proxy.size.width - spacing)
            let rightWidth = clamped(availableWidth * 0.25, min: 300, max: 360)
            let leftWidth = max(0, availableWidth - rightWidth)

            HStack(alignment: .top, spacing: spacing) {
                TodayAppUsageBarChartPanel(snapshot: snapshot)
                    .layoutPriority(1)
                    .frame(width: leftWidth)
                    .frame(height: proxy.size.height)

                VStack(alignment: .leading, spacing: spacing) {
                    TodayRhythmSummaryPanel(snapshot: snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: rightWidth)
                .frame(height: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

private struct TodayRhythmSummaryPanel: View {
    private var items: [StateDurationItem] {
        snapshot.rhythmItems
    }

    private var totalSeconds: Int {
        snapshot.rhythmTotalSeconds
    }

    private var displayedCurrentState: FocusPetCore.FocusState {
        snapshot.dominantRhythmState
    }

    var snapshot: TodayWindowInsightSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("窗口节奏")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                StatusPill(snapshot.window.heading, symbol: "clock")
            }

            HStack {
                Spacer(minLength: 0)
                StateDonutChart(items: items, total: totalSeconds)
                    .frame(width: 96, height: 96)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(items) { item in
                    RhythmLegendRow(item: item, totalSeconds: totalSeconds, isDominant: item.state == displayedCurrentState)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(12)
        .animation(.snappy(duration: 0.36, extraBounce: 0.04), value: snapshot.animationKey)
    }

}

private struct RhythmLegendRow: View {
    var item: StateDurationItem
    var totalSeconds: Int
    var isDominant: Bool

    private var ratio: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(item.seconds) / Double(totalSeconds)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.state.timelineColor)
                .frame(width: 8, height: 8)
            Text(item.state.title)
                .font(.caption.weight(isDominant ? .bold : .semibold))
                .foregroundStyle(isDominant ? DashboardPalette.primaryText : DashboardPalette.secondaryText)
                .frame(width: 38, alignment: .leading)
            Text(FocusPetFormatters.duration(item.seconds))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            Spacer(minLength: 4)
            Text(FocusPetFormatters.percentage(ratio))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.secondaryText)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            item.state.timelineColor.opacity(isDominant ? 0.10 : 0.05),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(item.state.timelineColor.opacity(isDominant ? 0.18 : 0.08), lineWidth: 1)
        }
    }
}

private struct CurrentRhythmPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: model.currentDecision.state.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(model.currentDecision.state.timelineColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前节奏")
                        .font(.headline.weight(.semibold))
                    Text(model.currentDecision.state == .focus ? "还不错，保持平稳" : rhythmSubtitle)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Text(model.currentDecision.state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.currentDecision.state.timelineColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(model.currentDecision.state.timelineColor.opacity(0.10), in: Capsule())
                Text(model.currentSnapshot.appName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            model.currentDecision.state.timelineColor.opacity(0.12),
                            DashboardPalette.elevatedCardFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(model.currentDecision.state.timelineColor.opacity(0.86))
                .frame(width: 4)
                .padding(.vertical, 12)
                .padding(.leading, 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(model.currentDecision.state.timelineColor.opacity(0.36), lineWidth: 1)
        }
        .liquidGlassSurface(cornerRadius: 12)
        .dashboardPetAnchor(.todayBreakControl)
    }

    private var rhythmSubtitle: String {
        switch model.currentDecision.state {
        case .focus: "还不错，保持平稳"
        case .distracted: "正在走神，适合收束窗口"
        case .breakTime: "正在休息，恢复后再继续"
        case .away: "暂离中，回来后自动恢复"
        }
    }
}

private struct TodayDistributionPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var items: [StateDurationItem] {
        [
            StateDurationItem(state: .focus, seconds: model.summary.focusSeconds),
            StateDurationItem(state: .distracted, seconds: model.summary.distractedSeconds),
            StateDurationItem(state: .breakTime, seconds: model.summary.breakSeconds),
            StateDurationItem(state: .away, seconds: model.summary.awaySeconds)
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StateDonutChart(items: items, total: model.summary.totalSeconds)
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 12) {
                Text("今日分布")
                    .font(.headline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.state.timelineColor)
                                .frame(width: 9, height: 9)
                            Text(item.state.title)
                                .frame(width: 34, alignment: .leading)
                            Spacer(minLength: 6)
                            Text(FocusPetFormatters.percentage(ratio(for: item)))
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(12)
    }

    private func ratio(for item: StateDurationItem) -> Double {
        guard model.summary.totalSeconds > 0 else { return 0 }
        return Double(item.seconds) / Double(model.summary.totalSeconds)
    }
}

private struct BreakDurationControl: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        Group {
            if model.activeBreakSession == nil {
                content(at: Date())
            } else {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    content(at: context.date)
                }
            }
        }
    }

    private func content(at date: Date) -> some View {
        let isActive = model.activeBreakSession != nil
        let progress = activeBreakProgress(at: date)

        return VStack(alignment: .leading, spacing: FPSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: FPSpacing.sm) {
                Text(isActive ? "正在恢复" : "休息恢复")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)

                Spacer(minLength: FPSpacing.sm)
            }

            HStack(alignment: .center, spacing: FPSpacing.md) {
                VStack(alignment: .leading, spacing: FPSpacing.xs) {
                    Text(primaryTimeText(at: date))
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(DashboardPalette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: FPSpacing.md)

                BreakRecoveryRing(progress: progress, isActive: isActive)
                    .frame(width: FPControlMetrics.restRingSize, height: FPControlMetrics.restRingSize)
            }

            if let progress {
                VStack(alignment: .leading, spacing: FPSpacing.sm) {
                    CompactMeter(ratio: progress, tint: DashboardPalette.restGreen, height: 6)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: FPControlMetrics.restMinuteSelectorHeight)
            } else {
                VStack(alignment: .leading, spacing: FPSpacing.sm) {
                    BreakMinuteKeySelector(value: breakMinutesKeyBinding)
                        .frame(height: FPControlMetrics.restMinuteSelectorHeight)
                }
            }

            Spacer(minLength: 0)

            BreakRestActionButton(isActive: isActive) {
                model.toggleBreakFromPet()
            }
        }
        .padding(.horizontal, FPCardMetrics.compactPadding)
        .padding(.vertical, FPCardMetrics.compactPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .todayGlassFeatureCard(status: .rest, tint: DashboardPalette.restGreen, padding: 0, role: .control)
    }

    private var breakMinutesKeyBinding: Binding<Int> {
        Binding(
            get: { model.settings.breakMinutes },
            set: { value in
                let next = max(1, min(60, value))
                guard model.settings.breakMinutes != next else { return }
                model.settings.breakMinutes = next
                model.saveSettings()
            }
        )
    }

    private func primaryTimeText(at date: Date) -> String {
        guard let rest = model.activeBreakSession else {
            return "\(model.settings.breakMinutes) 分钟"
        }
        let remaining = max(0, rest.targetDurationSeconds - max(0, Int(date.timeIntervalSince(rest.start))))
        return FocusPetFormatters.duration(remaining)
    }

    private func activeBreakProgress(at date: Date) -> Double? {
        guard let rest = model.activeBreakSession else { return nil }
        let elapsed = max(0, date.timeIntervalSince(rest.start))
        return min(1, elapsed / Double(max(1, rest.targetDurationSeconds)))
    }
}

private struct BreakRecoveryRing: View {
    var progress: Double?
    var isActive: Bool

    private var ringProgress: Double {
        min(1, max(0, progress ?? 0.72))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DashboardPalette.trackFill.opacity(0.65), lineWidth: 6)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    DashboardPalette.restGreen.gradient,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(isActive ? 1 : 0.42)

            Image(systemName: isActive ? "leaf.fill" : "cup.and.saucer.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DashboardPalette.restGreen)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.70), in: Circle())
                .overlay {
                    Circle().stroke(Color.white.opacity(0.48), lineWidth: 1)
                }
        }
    }
}

private struct BreakRestActionButton: View {
    var isActive: Bool
    var action: () -> Void

    private var tint: Color {
        isActive ? DashboardPalette.distractedPeach : DashboardPalette.restGreen
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "stop.fill" : "leaf.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: FPControlMetrics.restActionIconBox, height: FPControlMetrics.restActionIconBox)
                    .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.40), lineWidth: 1)
                    }

                Text(isActive ? "结束休息" : "开始恢复")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                Image(systemName: isActive ? "checkmark" : "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.70)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, FPSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: FPControlMetrics.restActionHeight)
            .background(tint.opacity(isActive ? 0.10 : 0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .fpGlassBackground(role: .button, cornerRadius: 9, tint: tint, isSelected: true, intensity: 0.96)
        }
        .buttonStyle(.plain)
        .help(isActive ? "结束休息" : "开始恢复")
    }
}

private struct BreakMinuteKeySelector: View {
    @Binding var value: Int

    private var options: [Int] {
        Array(Set([1, 5, 10, 30, value])).sorted()
    }

    var body: some View {
        HStack(spacing: FPSpacing.sm) {
            ForEach(options, id: \.self) { minute in
                let selected = minute == value
                Button {
                    value = minute
                } label: {
                    Text("\(minute)m")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(selected ? Color.white : DashboardPalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: FPControlMetrics.restMinuteButtonHeight)
                        .background(
                            selected ? DashboardPalette.restGreen.opacity(0.70) : Color.white.opacity(0.12),
                            in: Capsule()
                        )
                        .background {
                            if selected {
                                FPGlassLayer(role: .badge, cornerRadius: FPRadius.pill, tint: DashboardPalette.restGreen, isSelected: true, intensity: 0.92)
                            }
                        }
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(minute) 分钟")
            }
        }
        .padding(FPSpacing.xs)
        .fpGlassBackground(role: .control, cornerRadius: 10, tint: DashboardPalette.restGreen, intensity: 0.82)
    }
}

private struct HeaderActionButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct DailyVisualOverviewPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var items: [StateDurationItem] {
        [
            StateDurationItem(state: .focus, seconds: model.summary.focusSeconds),
            StateDurationItem(state: .distracted, seconds: model.summary.distractedSeconds),
            StateDurationItem(state: .breakTime, seconds: model.summary.breakSeconds),
            StateDurationItem(state: .away, seconds: model.summary.awaySeconds)
        ]
    }

    var body: some View {
        let workload = model.todayWorkload
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("今日状态总览", systemImage: "chart.pie.fill")
                    .font(.headline)
                Spacer()
                StatusPill(FocusPetFormatters.estimatedTypedCharacters(workload.estimatedTypedCharacters), symbol: "keyboard")
                StatusPill(FocusPetFormatters.contextSwitches(workload.contextSwitchCount), symbol: "arrow.triangle.2.circlepath")
                StatusPill("提醒 \(model.summary.nudgeCount) 次", symbol: "bell.badge.fill")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    StateDonutChart(items: items, total: model.summary.totalSeconds)
                        .frame(width: 178, height: 178)
                    StateShareBars(items: items, total: model.summary.totalSeconds)
                        .frame(minHeight: 172)
                }

                VStack(alignment: .leading, spacing: 16) {
                    StateDonutChart(items: items, total: model.summary.totalSeconds)
                        .frame(width: 178, height: 178)
                        .frame(maxWidth: .infinity)
                    StateShareBars(items: items, total: model.summary.totalSeconds)
                }
            }
        }
        .dashboardCard()
    }
}

private struct StateDurationItem: Identifiable {
    var state: FocusPetCore.FocusState
    var seconds: Int

    var id: String { state.id }
}

private struct StateShareSlice: Identifiable {
    var id: String
    var state: FocusPetCore.FocusState
    var start: Double
    var end: Double
}

private struct StateDonutChart: View {
    var items: [StateDurationItem]
    var total: Int

    private var slices: [StateShareSlice] {
        guard total > 0 else { return [] }
        var cursor = 0.0
        return items.compactMap { item in
            guard item.seconds > 0 else { return nil }
            let start = cursor
            let end = min(1, cursor + Double(item.seconds) / Double(total))
            cursor = end
            return StateShareSlice(id: item.state.id, state: item.state, start: start, end: end)
        }
    }

    private var focusPercent: Int {
        guard total > 0 else { return 0 }
        let focus = items.first { $0.state == .focus }?.seconds ?? 0
        return Int((Double(focus) / Double(total) * 100).rounded())
    }

    private var animationKey: String {
        slices
            .map { "\($0.id):\(String(format: "%.3f", $0.start))-\(String(format: "%.3f", $0.end))" }
            .joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(12, side * 0.12)
            ZStack {
                Circle()
                    .stroke(DashboardPalette.trackFill, lineWidth: lineWidth)

                ForEach(slices) { slice in
                    Circle()
                        .trim(from: slice.start, to: slice.end)
                        .stroke(slice.state.timelineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 2) {
                    Text("\(focusPercent)%")
                        .font(.system(size: max(22, side * 0.18), weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("专注占比")
                        .font(.system(size: max(9, side * 0.065), weight: .medium))
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .animation(.snappy(duration: 0.38, extraBounce: 0.04), value: animationKey)
        }
    }
}

private struct StateShareBars: View {
    var items: [StateDurationItem]
    var total: Int

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                StateSummaryTile(item: item, total: total)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 134), spacing: 10)]
    }
}

private struct StateSummaryTile: View {
    var item: StateDurationItem
    var total: Int

    private var ratio: Double {
        total == 0 ? 0 : Double(item.seconds) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
            Image(systemName: item.state.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.state.timelineColor)
                .frame(width: 22, height: 22)
                    .background(item.state.timelineColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                Text(item.state.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            Text(FocusPetFormatters.percentage(ratio))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(DashboardPalette.secondaryText)
            }

            CompactMeter(ratio: ratio, tint: item.state.timelineColor, height: 8)
                .frame(maxWidth: 128)

            Text(FocusPetFormatters.duration(item.seconds))
                .font(.headline.monospacedDigit())
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }
}

struct RestStatusCompactPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("当前节奏", systemImage: "timer")
                .font(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    RestStatusTile(title: "当前状态", value: model.currentDecision.state.title, symbol: model.currentDecision.state.symbolName, tint: model.currentDecision.state.timelineColor)
                    RestStatusTile(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: FPChartPalette.focus)
                    RestStatusTile(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: FocusPetCore.FocusState.distracted.timelineColor)
                    restAction
                }
                VStack(spacing: 10) {
                    RestStatusTile(title: "当前状态", value: model.currentDecision.state.title, symbol: model.currentDecision.state.symbolName, tint: model.currentDecision.state.timelineColor)
                    RestStatusTile(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: FPChartPalette.focus)
                    RestStatusTile(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: FocusPetCore.FocusState.distracted.timelineColor)
                    restAction
                }
            }
        }
        .dashboardCard()
    }

    private var restAction: some View {
        Button {
            model.toggleBreakFromPet()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title3.weight(.semibold))
                Text(model.activeBreakSession == nil ? "休息 \(model.settings.breakMinutes) 分钟" : "结束休息")
                    .font(.headline)
                if let rest = model.activeBreakSession {
                    Text("剩余 \(FocusPetFormatters.duration(rest.remainingSeconds()))")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                } else {
                    Text("休息后自动恢复判断")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .padding(12)
            .foregroundStyle(DashboardPalette.primaryText)
            .background(DashboardPalette.elevatedCardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DashboardPalette.border, lineWidth: 1)
            }
            .liquidGlassSurface(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }
}

private struct RestStatusTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(12)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }
}

private enum ActivityTimelineWindow: Int, CaseIterable, Hashable, Identifiable {
    case twoHours = 7_200
    case fourHours = 14_400
    case sixHours = 21_600
    case eightHours = 28_800
    case twelveHours = 43_200
    case twentyFourHours = 86_400

    var id: Int { rawValue }

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    var title: String {
        switch self {
        case .twoHours: "2h"
        case .fourHours: "4h"
        case .sixHours: "6h"
        case .eightHours: "8h"
        case .twelveHours: "12h"
        case .twentyFourHours: "24h"
        }
    }

    var heading: String {
        switch self {
        case .twoHours: "最近 2 小时"
        case .fourHours: "最近 4 小时"
        case .sixHours: "最近 6 小时"
        case .eightHours: "最近 8 小时"
        case .twelveHours: "最近 12 小时"
        case .twentyFourHours: "最近 24 小时"
        }
    }

}

private struct TodayWindowInsightSnapshot {
    var window: ActivityTimelineWindow
    var start: Date
    var end: Date
    var rangeLabel: String
    var focusSeconds: Int
    var distractedSeconds: Int
    var breakSeconds: Int
    var awaySeconds: Int
    var stateItems: [StateDurationItem]
    var appItems: [AppUsageDisplayItem]

    var rhythmItems: [StateDurationItem] {
        stateItems.filter { $0.state != .away }
    }

    var rhythmTotalSeconds: Int {
        max(0, rhythmItems.reduce(0) { $0 + $1.seconds })
    }

    var dominantRhythmState: FocusPetCore.FocusState {
        rhythmItems
            .filter { $0.seconds > 0 }
            .max { lhs, rhs in lhs.seconds < rhs.seconds }?
            .state ?? .focus
    }

    var animationKey: String {
        let appFingerprint = appItems
            .map { "\($0.id):\($0.seconds)" }
            .joined(separator: "|")
        return "\(window.id)-\(focusSeconds)-\(distractedSeconds)-\(breakSeconds)-\(awaySeconds)-\(appFingerprint)"
    }

    init(
        window: ActivityTimelineWindow,
        stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        now: Date = Date()
    ) {
        let windowEnd = now
        let windowStart = now.addingTimeInterval(-window.seconds)
        let bounds = (start: windowStart, end: windowEnd)
        var durations = Dictionary(uniqueKeysWithValues: FocusPetCore.FocusState.allCases.map { ($0, 0) })

        for segment in orderedStateSegments(stateSegments).reversed() {
            if segment.end <= windowStart { break }
            guard todayWindowOverlaps(segment.start, segment.end, bounds: bounds) else { continue }
            durations[segment.state, default: 0] += todayWindowClippedSeconds(start: segment.start, end: segment.end, bounds: bounds)
        }

        self.window = window
        self.start = windowStart
        self.end = windowEnd
        self.rangeLabel = "\(FocusPetFormatters.clock(windowStart)) - \(FocusPetFormatters.clock(windowEnd))"
        self.focusSeconds = durations[.focus, default: 0]
        self.distractedSeconds = durations[.distracted, default: 0]
        self.breakSeconds = durations[.breakTime, default: 0]
        self.awaySeconds = durations[.away, default: 0]
        self.stateItems = [
            StateDurationItem(state: .focus, seconds: durations[.focus, default: 0]),
            StateDurationItem(state: .distracted, seconds: durations[.distracted, default: 0]),
            StateDurationItem(state: .breakTime, seconds: durations[.breakTime, default: 0]),
            StateDurationItem(state: .away, seconds: durations[.away, default: 0])
        ]
        self.appItems = AppUsageDisplayItem.windowed(
            from: stateSegments,
            appUsage: appUsage,
            bounds: bounds
        )
    }
}

private func todayWindowOverlaps(_ start: Date, _ end: Date, bounds: (start: Date, end: Date)) -> Bool {
    end > bounds.start && start < bounds.end
}

private func todayWindowClippedSeconds(start: Date, end: Date, bounds: (start: Date, end: Date)) -> Int {
    max(0, Int(min(end, bounds.end).timeIntervalSince(max(start, bounds.start)).rounded()))
}

private func todayWindowNormalizedCategory(_ category: ActivityCategory) -> ActivityCategory {
    category == .neutral ? .ignore : category
}

private func todayWindowAppKey(appName: String, bundleID: String?) -> String {
    let rawKey = (bundleID?.isEmpty == false ? bundleID : nil) ?? appName
    return rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func todayWindowIsHiddenSystemUsage(appName: String, bundleID: String?) -> Bool {
    let normalizedName = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedBundleID = bundleID?.lowercased() ?? ""
    return normalizedName == "sleep"
        || normalizedName == "loginwindow"
        || normalizedName == "locked screen"
        || normalizedName == "break"
        || normalizedName == "away"
        || normalizedBundleID.contains("loginwindow")
}

private struct InputActivityTimelinePanel: View {
    @EnvironmentObject private var model: FocusPetModel
    @Binding var selectedWindow: ActivityTimelineWindow
    var now: Date

    var body: some View {
        let snapshot = InputTimelineSnapshot(
            windowSeconds: selectedWindow.seconds,
            stateSegments: model.stateSegments,
            appUsage: model.appUsage,
            inputActivity: model.inputActivity,
            now: now,
            includeAwayState: false,
            includeAppSegments: false
        )

        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    Text("活动时间窗")
                        .font(.headline.weight(.semibold))

                    Text("自动记录")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DashboardPalette.controlFill, in: Capsule())
                        .overlay {
                            Capsule().stroke(DashboardPalette.border, lineWidth: 1)
                        }

                    StatusPill(selectedWindow.heading, symbol: "clock.arrow.circlepath")
                    timelineMetrics(snapshot)

                    Spacer(minLength: 10)

                    TimelineWindowPicker(selection: $selectedWindow)
                        .frame(width: 260)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("活动时间窗")
                            .font(.headline.weight(.semibold))

                        Text("自动记录")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DashboardPalette.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DashboardPalette.controlFill, in: Capsule())
                            .overlay {
                                Capsule().stroke(DashboardPalette.border, lineWidth: 1)
                            }

                        Spacer(minLength: 12)

                        TimelineWindowPicker(selection: $selectedWindow)
                            .frame(width: 260)
                    }

                    HStack(spacing: 8) {
                        StatusPill(selectedWindow.heading, symbol: "clock.arrow.circlepath")
                        timelineMetrics(snapshot)
                        Spacer(minLength: 0)
                    }
                }
            }
            .contentTransition(.numericText())

            InputTimelineChart(snapshot: snapshot)
                .id(selectedWindow)
                .layoutPriority(1)
                .frame(minHeight: 188)
                .clipped()
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fpCard(padding: 0, radius: FPRadius.large, background: FPColor.card, border: FPColor.borderDefault)
        .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: selectedWindow)
    }

    @ViewBuilder
    private func timelineMetrics(_ snapshot: InputTimelineSnapshot) -> some View {
        HStack(spacing: 8) {
            TimelineMetricPill(
                "键盘 \(FocusPetFormatters.compactCount(snapshot.estimatedTypedCharacters)) 次",
                symbol: "keyboard",
                tint: FPChartPalette.inputKeyboardStrong
            )
            TimelineMetricPill(
                "鼠标 \(FocusPetFormatters.compactCount(snapshot.pointerActionCount)) 次",
                symbol: "cursorarrow.click",
                tint: FPChartPalette.inputPointerStrong
            )
            TimelineMetricPill(
                "切换 \(FocusPetFormatters.compactCount(snapshot.contextSwitchCount)) 次",
                symbol: "arrow.triangle.2.circlepath",
                tint: FPChartPalette.inputSwitch
            )
            StatusPill(snapshot.rangeLabel, symbol: "calendar")
        }
    }
}

private struct TimelineMetricPill: View {
    var title: String
    var symbol: String
    var tint: Color

    init(_ title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.11), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.20), lineWidth: 1)
        }
    }
}

private struct TimelineWindowPicker: View {
    @Binding var selection: ActivityTimelineWindow

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ActivityTimelineWindow.allCases) { window in
                let selected = selection == window
                Button {
                    selection = window
                } label: {
                    Text(window.title)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(selected ? DashboardPalette.focusBlue : DashboardPalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(FPColor.focus050)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(FPColor.focus300.opacity(0.48), lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(window.heading)
            }
        }
        .padding(3)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DashboardPalette.border, lineWidth: 1)
        }
        .liquidGlassSurface(cornerRadius: 9)
    }
}

private struct TimelineHoverDetail {
    var id: String
    var title: String
    var lines: [String]
    var tint: Color
    var x: CGFloat
    var y: CGFloat
}

private struct TimelineAxisTick: Identifiable, Hashable {
    var date: Date
    var progress: Double
    var isBoundary: Bool = false

    var id: String {
        "\(Int(date.timeIntervalSince1970))-\(Int((progress * 10_000).rounded()))-\(isBoundary)"
    }
}

private struct TimelineHoverBubble: View {
    var detail: TimelineHoverDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(detail.tint)
                    .frame(width: 8, height: 8)
                Text(detail.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(detail.lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 200, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(detail.tint.opacity(0.20), lineWidth: 1)
                }
                .shadow(color: DashboardPalette.shadow.opacity(0.20), radius: 8, x: 0, y: 4)
        }
    }
}

private struct InputTimelineChart: View {
    var snapshot: InputTimelineSnapshot

    @State private var hoverDetail: TimelineHoverDetail?

    private let labelWidth: CGFloat = 54

    var body: some View {
        GeometryReader { proxy in
            let chartWidth = max(1, proxy.size.width - labelWidth)
            let chartHeight = max(1, proxy.size.height)
            let statusY: CGFloat = 4
            let statusHeight: CGFloat = 34
            let inputY: CGFloat = statusY + statusHeight + 18
            let axisReserve: CGFloat = 34
            let inputHeight = max(24, chartHeight - inputY - axisReserve)
            let markerBottom = inputY + inputHeight
            let axisY = min(markerBottom + 7, max(0, chartHeight - 24))

            ZStack(alignment: .topLeading) {
                rowLabels(statusY: statusY, inputY: inputY, inputHeight: inputHeight)

                ZStack(alignment: .topLeading) {
                    inputGrid(
                        width: chartWidth,
                        top: inputY,
                        height: inputHeight,
                        bottom: markerBottom,
                        ticks: snapshot.hourAxisTicks
                    )

                    stateBand(width: chartWidth, y: statusY, height: statusHeight)

                    ForEach(snapshot.switchMarkers) { marker in
                        let x = chartWidth * CGFloat(marker.progress)
                        let lineWidth = max(1, min(4, CGFloat(marker.count)))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(FPChartPalette.inputSwitch.opacity(0.22))
                            .frame(width: lineWidth, height: inputHeight)
                            .offset(x: x, y: inputY)
                    }

                    ForEach(snapshot.inputBars) { bar in
                        inputBar(bar, chartWidth: chartWidth, y: inputY, height: inputHeight)
                    }

                    timelineHourAxis(ticks: snapshot.hourAxisTicks, width: chartWidth, y: axisY)

                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: chartWidth, height: min(chartHeight, markerBottom + axisReserve))
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverDetail = trackedDetail(
                                    at: location,
                                    chartWidth: chartWidth,
                                    statusY: statusY,
                                    statusHeight: statusHeight,
                                    inputY: inputY,
                                    inputHeight: inputHeight
                                )
                            case .ended:
                                hoverDetail = nil
                            }
                        }
                        .simultaneousGesture(
                            SpatialTapGesture().onEnded { value in
                                hoverDetail = trackedDetail(
                                    at: value.location,
                                    chartWidth: chartWidth,
                                    statusY: statusY,
                                    statusHeight: statusHeight,
                                    inputY: inputY,
                                    inputHeight: inputHeight
                                )
                            }
                        )

                    if let hoverDetail {
                        TimelineHoverBubble(detail: hoverDetail)
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(
                                x: tooltipX(for: hoverDetail, chartWidth: chartWidth),
                                y: tooltipY(for: hoverDetail, chartHeight: chartHeight)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                            .zIndex(50)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: chartWidth, height: chartHeight, alignment: .topLeading)
                .offset(x: labelWidth)
            }
        }
        .animation(.snappy(duration: 0.16, extraBounce: 0), value: hoverDetail?.id)
    }

    private func rowLabels(
        statusY: CGFloat,
        inputY: CGFloat,
        inputHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Text("状态")
                .offset(x: 0, y: statusY + 8)
            Text("输入")
                .offset(x: 0, y: inputY + inputHeight * 0.42)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(DashboardPalette.primaryText)
        .frame(width: labelWidth, alignment: .leading)
    }

    private func inputGrid(
        width: CGFloat,
        top: CGFloat,
        height: CGFloat,
        bottom: CGFloat,
        ticks: [TimelineAxisTick]
    ) -> some View {
        Path { path in
            for index in 0...4 {
                let y = top + height * CGFloat(index) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            for tick in ticks {
                let x = width * CGFloat(tick.progress)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: bottom))
            }
        }
        .stroke(FPChartPalette.gridLine, style: StrokeStyle(lineWidth: 1, dash: [4, 8]))
    }

    private func timelineHourAxis(ticks: [TimelineAxisTick], width: CGFloat, y: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(ticks) { tick in
                VStack(spacing: 3) {
                    Rectangle()
                        .fill(DashboardPalette.innerStroke.opacity(0.72))
                        .frame(width: 1, height: 6)
                    Text(FocusPetFormatters.clock(tick.date))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .fixedSize()
                }
                .frame(width: 34)
                .offset(x: max(0, min(width - 34, width * CGFloat(tick.progress) - 17)), y: y)
            }
        }
        .frame(width: width, height: 24, alignment: .topLeading)
    }

    private func stateBand(width: CGFloat, y: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(FPChartPalette.neutralTrack.opacity(0.70))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.26))
                        .frame(height: 1)
                        .padding(.horizontal, 2)
                }

            ForEach(snapshot.stateRanges) { range in
                let x = width * CGFloat(range.startProgress)
                let rangeWidth = max(2, width * CGFloat(range.endProgress - range.startProgress))
                let tint = range.state.timelineColor
                ZStack {
                    RoundedRectangle(cornerRadius: rangeWidth > 18 ? 10 : 3, style: .continuous)
                        .fill(tint.opacity(0.88))
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: rangeWidth > 18 ? 10 : 3, style: .continuous)
                                .fill(Color.white.opacity(0.22))
                                .frame(height: 1.5)
                                .padding(.horizontal, min(8, max(0, rangeWidth / 6)))
                                .padding(.top, 3)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: rangeWidth > 18 ? 10 : 3, style: .continuous)
                                .stroke(Color.white.opacity(0.26), lineWidth: 0.8)
                        }

                    if rangeWidth > 72 {
                        Text(range.state.title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.94))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(width: rangeWidth, height: height)
                .offset(x: x)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.50), lineWidth: 0.8)
        }
        .offset(y: y)
    }

    private func inputBar(_ bar: InputTimelineInputBar, chartWidth: CGFloat, y: CGFloat, height: CGFloat) -> some View {
        let slotX = chartWidth * CGFloat(bar.startProgress)
        let slotWidth = max(3, chartWidth * CGFloat(bar.endProgress - bar.startProgress))
        let barWidth = max(5, min(14, slotWidth * 0.72))
        let totalRatio = CGFloat(bar.totalCount) / CGFloat(max(1, snapshot.maxInputCount))
        let totalHeight = min(height, max(bar.totalCount > 0 ? 8 : 0, height * 0.90 * totalRatio))
        let pointerRatio = bar.totalCount > 0 ? CGFloat(bar.pointerCount) / CGFloat(bar.totalCount) : 0
        let pointerHeight = totalHeight * pointerRatio
        let keyboardHeight = totalHeight - pointerHeight

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(FPChartPalette.inputTrack.opacity(0.82))
                .frame(width: max(barWidth, 8), height: totalHeight)

            VStack(spacing: 1.5) {
                if bar.keyboardCount > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(FPChartPalette.inputKeyboard.opacity(0.86))
                        .frame(height: max(3, keyboardHeight))
                }
                if bar.pointerCount > 0 {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(FPChartPalette.inputPointer.opacity(0.88))
                        .frame(height: max(3, pointerHeight))
                }
            }
            .frame(width: barWidth, height: totalHeight, alignment: .bottom)
        }
        .offset(x: slotX + (slotWidth - barWidth) / 2, y: y + height - totalHeight)
    }

    private func stateDetail(for range: InputTimelineStateRange, x: CGFloat, y: CGFloat) -> TimelineHoverDetail {
        let start = date(for: range.startProgress)
        let end = date(for: range.endProgress)
        let seconds = max(0, Int(end.timeIntervalSince(start).rounded()))
        return TimelineHoverDetail(
            id: "state-\(range.id)",
            title: range.state.title,
            lines: [
                "\(FocusPetFormatters.clock(start)) - \(FocusPetFormatters.clock(end))",
                "持续 \(FocusPetFormatters.duration(seconds))"
            ],
            tint: range.state.timelineColor,
            x: x,
            y: y
        )
    }

    private func inputDetail(for bar: InputTimelineInputBar, x: CGFloat, y: CGFloat) -> TimelineHoverDetail {
        let start = date(for: bar.startProgress)
        let end = date(for: bar.endProgress)
        let minutes = max(1, end.timeIntervalSince(start) / 60)
        let inputFrequency = Double(bar.totalCount) / minutes
        let frequencyLabel = String(format: "%.1f 次/分钟", inputFrequency)
        return TimelineHoverDetail(
            id: "input-\(bar.id)",
            title: "输入 \(FocusPetFormatters.compactCount(bar.totalCount)) 次",
            lines: [
                "\(FocusPetFormatters.clock(start)) - \(FocusPetFormatters.clock(end))",
                "频率 \(frequencyLabel)",
                "键盘 \(FocusPetFormatters.compactCount(bar.estimatedTypedCharacters)) 次",
                "鼠标 \(FocusPetFormatters.compactCount(bar.pointerActionCount)) 次",
                "切换 \(FocusPetFormatters.compactCount(bar.contextSwitchCount)) 次",
                "本地估算，不记录输入内容"
            ],
            tint: inputDominantTint(for: bar),
            x: x,
            y: y
        )
    }

    private func inputDominantTint(for bar: InputTimelineInputBar) -> Color {
        bar.pointerCount > bar.keyboardCount ? FPChartPalette.inputPointerStrong : FPChartPalette.inputKeyboardStrong
    }

    private func switchDetail(for marker: InputTimelineSwitchMarker, x: CGFloat, y: CGFloat) -> TimelineHoverDetail {
        let date = date(for: marker.progress)
        return TimelineHoverDetail(
            id: "switch-\(marker.id)",
            title: "切换 \(marker.count) 次",
            lines: [
                "约 \(FocusPetFormatters.clock(date))",
                "App 或窗口焦点变化"
            ],
            tint: FPChartPalette.inputSwitch,
            x: x,
            y: y
        )
    }

    private func updateHover(inside: Bool, detail: TimelineHoverDetail) {
        if inside {
            hoverDetail = detail
        } else if hoverDetail?.id == detail.id {
            hoverDetail = nil
        }
    }

    private func trackedDetail(
        at location: CGPoint,
        chartWidth: CGFloat,
        statusY: CGFloat,
        statusHeight: CGFloat,
        inputY: CGFloat,
        inputHeight: CGFloat
    ) -> TimelineHoverDetail? {
        guard location.x >= 0, location.x <= chartWidth else { return nil }
        let progress = Double(max(0, min(1, location.x / max(1, chartWidth))))

        if location.y >= statusY - 8, location.y <= statusY + statusHeight + 10 {
            if let range = snapshot.stateRanges.last(where: { progress >= $0.startProgress && progress <= $0.endProgress }) {
                return stateDetail(for: range, x: location.x, y: statusY + statusHeight + 8)
            }
            return nil
        }

        guard location.y >= inputY - 10, location.y <= inputY + inputHeight + 14 else {
            return nil
        }

        if let bar = nearestInputBar(to: location.x, chartWidth: chartWidth) {
            return inputDetail(for: bar, x: location.x, y: location.y)
        }

        if let marker = nearestSwitchMarker(to: location.x, chartWidth: chartWidth) {
            return switchDetail(for: marker, x: location.x, y: location.y)
        }

        return nil
    }

    private func nearestInputBar(to x: CGFloat, chartWidth: CGFloat) -> InputTimelineInputBar? {
        snapshot.inputBars
            .compactMap { bar -> (bar: InputTimelineInputBar, distance: CGFloat, tolerance: CGFloat) in
                let startX = chartWidth * CGFloat(bar.startProgress)
                let endX = chartWidth * CGFloat(bar.endProgress)
                let centerX = (startX + endX) / 2
                let tolerance = max(10, (endX - startX) / 2 + 8)
                return (bar, abs(centerX - x), tolerance)
            }
            .filter { $0.distance <= $0.tolerance }
            .min { $0.distance < $1.distance }?
            .bar
    }

    private func nearestSwitchMarker(to x: CGFloat, chartWidth: CGFloat) -> InputTimelineSwitchMarker? {
        snapshot.switchMarkers
            .map { marker -> (marker: InputTimelineSwitchMarker, distance: CGFloat, tolerance: CGFloat) in
                let markerX = chartWidth * CGFloat(marker.progress)
                return (marker, abs(markerX - x), max(8, CGFloat(marker.count) + 6))
            }
            .filter { $0.distance <= $0.tolerance }
            .min { $0.distance < $1.distance }?
            .marker
    }

    private func tooltipX(for detail: TimelineHoverDetail, chartWidth: CGFloat) -> CGFloat {
        min(max(0, detail.x + 10), max(0, chartWidth - 210))
    }

    private func tooltipY(for detail: TimelineHoverDetail, chartHeight: CGFloat) -> CGFloat {
        min(max(0, detail.y - 88), max(0, chartHeight - 118))
    }

    private func appBand(width: CGFloat, y: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.trackFill.opacity(0.24))

            ForEach(snapshot.appSegments) { segment in
                let x = width * xProgress(for: segment.start)
                let segmentWidth = max(4, width * (xProgress(for: segment.end) - xProgress(for: segment.start)))
                let tint = appTimelineColor(for: segment)
                HStack(spacing: 7) {
                    if segmentWidth > 54 {
                        AppIconView(appName: segment.appName, bundleID: segment.bundleID, category: segment.category, size: 24)
                    }
                    if segmentWidth > 104 {
                        Text(segment.appName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .padding(.horizontal, segmentWidth > 54 ? 6 : 0)
                .frame(width: segmentWidth, height: height, alignment: .leading)
                .background(tint.opacity(0.86).gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 0.8)
                }
                .offset(x: x)
                .help("\(segment.appName) · \(FocusPetFormatters.duration(Int(segment.duration.rounded())))")
            }
        }
        .frame(width: width, height: height)
        .offset(y: y)
    }

    private func appTimelineColor(for segment: InputTimelineAppSegment) -> Color {
        let identity = segment.identity.lowercased()
        let appName = segment.appName.lowercased()
        if appName.contains("微信") || identity.contains("wechat") {
            return FPChartPalette.rest
        }
        if appName.contains("codex") || identity.contains("codex") {
            return FPChartPalette.focusStrong
        }
        if appName.contains("focuspet") || appName.contains("focus pet") || identity.contains("focuspet") {
            return FPChartPalette.away
        }
        if appName.contains("safari") {
            return FPChartPalette.focus
        }
        if appName.contains("chrome") || appName.contains("edge") {
            return FPChartPalette.distracted
        }

        let palette: [Color] = [
            FPChartPalette.focus,
            FPChartPalette.rest,
            FPChartPalette.away,
            FPChartPalette.distracted,
            FPColor.systemCyan500,
            FPColor.focus600,
            FPColor.rest600,
            FPChartPalette.focusStrong,
            FPColor.warning
        ]
        return palette[stableColorIndex(for: segment.identity, count: palette.count)]
    }

    private func stableColorIndex(for text: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for scalar in text.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }

    private func xProgress(for date: Date) -> CGFloat {
        let span = max(1, snapshot.end.timeIntervalSince(snapshot.start))
        return CGFloat(max(0, min(1, date.timeIntervalSince(snapshot.start) / span)))
    }

    private func date(for progress: Double) -> Date {
        let span = max(1, snapshot.end.timeIntervalSince(snapshot.start))
        return snapshot.start.addingTimeInterval(max(0, min(1, progress)) * span)
    }
}

private extension InputTimelineSnapshot {
    var timeLabels: [String] {
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        return [
            FocusPetFormatters.clock(start),
            FocusPetFormatters.clock(midpoint),
            FocusPetFormatters.clock(end)
        ]
    }

    var rangeLabel: String {
        "\(FocusPetFormatters.clock(start)) - \(FocusPetFormatters.clock(end))"
    }

    var hourAxisTicks: [TimelineAxisTick] {
        let span = max(1, end.timeIntervalSince(start))
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")

        func progress(for date: Date) -> Double {
            max(0, min(1, date.timeIntervalSince(start) / span))
        }

        var ticks: [TimelineAxisTick] = []

        var components = calendar.dateComponents([.year, .month, .day, .hour], from: start)
        components.minute = 0
        components.second = 0
        let startHour = calendar.date(from: components) ?? start
        var cursor = startHour <= start
            ? (calendar.date(byAdding: .hour, value: 1, to: startHour) ?? start.addingTimeInterval(3_600))
            : startHour

        while cursor < end {
            ticks.append(TimelineAxisTick(date: cursor, progress: progress(for: cursor)))
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }

        return ticks
    }
}

struct TimelinePanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        let timeline = StatusStripSnapshot(segments: model.stateSegments, secondsBack: 14_400)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 4 小时")
                    .font(.headline.weight(.semibold))
                Spacer()
                HStack(spacing: 14) {
                    ForEach(timeline.legend) { item in
                        HStack(spacing: 6) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            Text(item.title)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    }
                }
            }
            if !timeline.hasData {
                Text("最近 4 小时暂无状态记录。")
                    .foregroundStyle(DashboardPalette.secondaryText)
            } else {
                StateSegmentBlockStrip(
                    ranges: timeline.ranges,
                    start: timeline.start,
                    end: timeline.end
                )
                .frame(height: 24)
                HStack {
                    TimelineTimeChip(timeline.timeLabels.first ?? "")
                    Spacer()
                    TimelineTimeChip(timeline.timeLabels.dropFirst().first ?? "")
                    Spacer()
                    TimelineTimeChip(timeline.timeLabels.last ?? "")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(12)
    }
}

private struct StateSegmentBlockStrip: View {
    var ranges: [StatusStripRange]
    var start: Date
    var end: Date
    var blockCount = 24

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<blockCount, id: \.self) { index in
                TimelineGlassBlock(color: color(for: index), isEmpty: isEmpty(index))
            }
        }
    }

    private func color(for index: Int) -> Color {
        guard blockCount > 0 else { return DashboardPalette.trackFill }
        let progress = (Double(index) + 0.5) / Double(blockCount)
        let sampleDate = start.addingTimeInterval(end.timeIntervalSince(start) * progress)
        let state = ranges.first { range in
            range.start <= sampleDate && range.end >= sampleDate
        }?.state
        return (state?.timelineColor ?? DashboardPalette.trackFill).opacity(state == nil ? 1 : 0.82)
    }

    private func isEmpty(_ index: Int) -> Bool {
        guard blockCount > 0 else { return true }
        let progress = (Double(index) + 0.5) / Double(blockCount)
        let sampleDate = start.addingTimeInterval(end.timeIntervalSince(start) * progress)
        return ranges.first { range in
            range.start <= sampleDate && range.end >= sampleDate
        } == nil
    }
}

private struct TimelineGlassBlock: View {
    var color: Color
    var isEmpty: Bool

    var body: some View {
        GeometryReader { proxy in
            let cornerRadius = min(proxy.size.height, proxy.size.width) * 0.22
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            shape
                .fill(color)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isEmpty ? 0.18 : 0.38),
                            Color.white.opacity(isEmpty ? 0.12 : 0.18),
                            Color.black.opacity(isEmpty ? 0.01 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(isEmpty ? 0.18 : 0.40))
                        .frame(height: max(2, proxy.size.height * 0.12))
                        .padding(.horizontal, max(3, proxy.size.width * 0.12))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEmpty ? 0.30 : 0.54),
                                    color.opacity(isEmpty ? 0.18 : 0.44)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .overlay {
                    shape
                        .inset(by: 1)
                        .stroke(Color.white.opacity(isEmpty ? 0.12 : 0.24), lineWidth: 0.6)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func orderedStateSegments(_ segments: [StateSegment]) -> [StateSegment] {
    guard !segments.isEmpty else { return [] }
    for index in segments.indices.dropFirst() {
        if segments[index].start < segments[segments.index(before: index)].start {
            return segments.sorted { $0.start < $1.start }
        }
    }
    return segments
}

private struct StatusStripSnapshot {
    var start: Date
    var end: Date
    var ranges: [StatusStripRange]
    var hasData: Bool
    var legend: [StatusTimelineLegendItem]
    var timeLabels: [String]

    init(segments: [StateSegment], secondsBack: TimeInterval) {
        let now = Date()
        let windowEnd = now
        let windowStart = now.addingTimeInterval(-secondsBack)
        let midpoint = windowStart.addingTimeInterval(windowEnd.timeIntervalSince(windowStart) / 2)
        self.start = windowStart
        self.end = windowEnd
        self.timeLabels = [
            FocusPetFormatters.clock(windowStart),
            FocusPetFormatters.clock(midpoint),
            FocusPetFormatters.clock(windowEnd)
        ]

        let orderedSegments = orderedStateSegments(segments)
        var filtered: [StateSegment] = []
        for segment in orderedSegments.reversed() {
            if segment.end <= windowStart { break }
            if segment.start < windowEnd {
                filtered.append(segment)
            }
        }
        filtered.reverse()
        self.hasData = !filtered.isEmpty
        var durations: [FocusPetCore.FocusState: TimeInterval] = [:]
        self.ranges = filtered.compactMap { segment in
            let clippedStart = max(segment.start, windowStart)
            let clippedEnd = min(segment.end, windowEnd)
            guard clippedEnd > clippedStart else { return nil }
            durations[segment.state, default: 0] += clippedEnd.timeIntervalSince(clippedStart)
            return StatusStripRange(start: clippedStart, end: clippedEnd, state: segment.state)
        }
        self.legend = FocusPetCore.FocusState.allCases
            .map { state in
                StatusTimelineLegendItem(
                    state: state,
                    title: "\(state.title) \(FocusPetFormatters.duration(Int(durations[state] ?? 0)))",
                    color: state.timelineColor
                )
            }
            .filter { durations[$0.state] ?? 0 > 0 }
    }
}

private struct StatusStripRange: Identifiable, Hashable {
    var start: Date
    var end: Date
    var state: FocusPetCore.FocusState

    var id: String {
        "\(state.id)-\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
    }
}

private struct StateSegmentStrip: View {
    var ranges: [StatusStripRange]
    var start: Date
    var end: Date
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(DashboardPalette.trackFill)
                ForEach(ranges) { range in
                    let x = xOffset(for: range.start, width: proxy.size.width)
                    let width = segmentWidth(for: range, totalWidth: proxy.size.width)
                    Rectangle()
                        .fill(range.state.timelineColor.gradient)
                        .frame(width: width, height: height)
                        .offset(x: x)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: height / 2))
            .overlay {
                RoundedRectangle(cornerRadius: height / 2)
                    .stroke(DashboardPalette.border, lineWidth: 1)
            }
            .shadow(color: DashboardPalette.shadow.opacity(0.10), radius: 2, y: 1)
        }
    }

    private var span: TimeInterval {
        max(1, end.timeIntervalSince(start))
    }

    private func xOffset(for date: Date, width: CGFloat) -> CGFloat {
        let progress = max(0, min(1, date.timeIntervalSince(start) / span))
        return width * CGFloat(progress)
    }

    private func segmentWidth(for range: StatusStripRange, totalWidth: CGFloat) -> CGFloat {
        let clippedStart = max(range.start, start)
        let clippedEnd = min(range.end, end)
        let progress = max(0, clippedEnd.timeIntervalSince(clippedStart) / span)
        return max(2, totalWidth * CGFloat(progress))
    }
}

private struct TodayTimelineSnapshot {
    var points: [StatusTimelinePoint]
    var ranges: [StatusTimelineRange]
    var hasData: Bool
    var legend: [StatusTimelineLegendItem]
    var timeLabels: [String]

    init(segments: [StateSegment]) {
        let now = Date()
        let start = now.addingTimeInterval(-21_600)
        let end = now
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        timeLabels = [
            FocusPetFormatters.clock(start),
            FocusPetFormatters.clock(midpoint),
            FocusPetFormatters.clock(end)
        ]
        let filtered = segments.filter { segment in
            segment.end > start && segment.start < end
        }

        let hasData = !filtered.isEmpty
        if !hasData {
            points = []
            ranges = []
            legend = FocusPetCore.FocusState.allCases.map { state in
                StatusTimelineLegendItem(state: state, title: state.title, color: state.timelineColor)
            }
            self.hasData = false
            return
        }

        var durations: [FocusPetCore.FocusState: TimeInterval] = [:]
        var generatedPoints: [StatusTimelinePoint] = []
        var generatedRanges: [StatusTimelineRange] = []
        let span = max(1, end.timeIntervalSince(start))

        func progress(for date: Date) -> Double {
            max(0, min(1, date.timeIntervalSince(start) / span))
        }

        for segment in filtered.sorted(by: { $0.start < $1.start }) {
            let clippedStart = max(segment.start, start)
            let clippedEnd = min(segment.end, end)
            guard clippedEnd > clippedStart else { continue }

            let startProgress = progress(for: clippedStart)
            let endProgress = progress(for: clippedEnd)
            let midpointProgress = (startProgress + endProgress) / 2
            generatedRanges.append(StatusTimelineRange(
                startProgress: startProgress,
                endProgress: endProgress,
                state: segment.state
            ))
            if generatedPoints.isEmpty {
                generatedPoints.append(StatusTimelinePoint(progress: startProgress, state: segment.state))
            }
            generatedPoints.append(StatusTimelinePoint(progress: midpointProgress, state: segment.state))
            generatedPoints.append(StatusTimelinePoint(progress: endProgress, state: segment.state))

            durations[segment.state, default: 0] += clippedEnd.timeIntervalSince(clippedStart)
        }

        points = Self.deduplicated(generatedPoints)
        ranges = generatedRanges
        self.hasData = true
        legend = FocusPetCore.FocusState.allCases
            .map { state in
                let seconds = Int(durations[state] ?? 0)
                return StatusTimelineLegendItem(
                    state: state,
                    title: "\(state.title) \(FocusPetFormatters.duration(seconds))",
                    color: state.timelineColor
                )
            }
            .filter { durations[$0.state] ?? 0 > 0 }
    }

    private static func deduplicated(_ points: [StatusTimelinePoint]) -> [StatusTimelinePoint] {
        var result: [StatusTimelinePoint] = []
        for point in points.sorted(by: { $0.progress < $1.progress }) {
            if let last = result.last, abs(last.progress - point.progress) < 0.003 {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        return result
    }
}

private struct StatusTimelinePoint: Identifiable {
    let progress: Double
    let state: FocusPetCore.FocusState

    var id: String {
        "\(state.id)-\(Int((progress * 10_000).rounded()))"
    }

    var level: Double {
        switch state {
        case .focus: 0.82
        case .distracted: 0.58
        case .breakTime: 0.36
        case .away: 0.18
        }
    }
}

private struct StatusTimelineRange: Identifiable {
    let startProgress: Double
    let endProgress: Double
    let state: FocusPetCore.FocusState

    var id: String {
        "\(state.id)-\(Int((startProgress * 10_000).rounded()))-\(Int((endProgress * 10_000).rounded()))"
    }
}

private struct StatusTimelineLegendItem: Identifiable {
    let state: FocusPetCore.FocusState
    let title: String
    let color: Color

    var id: String { "\(state.id)-\(title)" }
}

private struct StatusLineChart: View {
    var points: [StatusTimelinePoint]
    var ranges: [StatusTimelineRange]
    var hasData: Bool
    var timeLabels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack {
                    TimelineStateBands(ranges: ranges)
                    ChartGridLines()

                    if hasData {
                        SmoothTimelineLineShape(points: points)
                            .stroke(Color.white.opacity(0.42), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                        SmoothTimelineLineShape(points: points)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        FocusPetCore.FocusState.focus.timelineColor,
                                        FocusPetCore.FocusState.breakTime.timelineColor,
                                        FocusPetCore.FocusState.away.timelineColor
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                            )
                    } else {
                        Text("暂无今日状态点。")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DashboardPalette.rowFill)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.24), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DashboardPalette.innerStroke, lineWidth: 1)
                    }
            }
        }
        .overlay(
            HStack(spacing: 12) {
                TimelineTimeChip(timeLabels.first ?? "")
                Spacer()
                TimelineTimeChip(timeLabels.dropFirst().first ?? "")
                Spacer()
                TimelineTimeChip(timeLabels.last ?? "")
            }
            .padding(10),
            alignment: .bottomLeading
        )
    }
}

private struct TimelineStateBands: View {
    var ranges: [StatusTimelineRange]

    var body: some View {
        GeometryReader { proxy in
            ForEach(ranges) { range in
                let startX = proxy.size.width * CGFloat(range.startProgress)
                let endX = proxy.size.width * CGFloat(range.endProgress)
                Rectangle()
                    .fill(range.state.timelineColor.opacity(0.10))
                    .frame(width: max(2, endX - startX), height: proxy.size.height)
                    .position(x: startX + max(2, endX - startX) / 2, y: proxy.size.height / 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SmoothTimelineLineShape: Shape {
    var points: [StatusTimelinePoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let positions = points.map { position(for: $0, in: rect.size) }
        guard let first = positions.first else { return path }
        path.move(to: first)
        guard positions.count > 1 else { return path }
        for index in 1..<positions.count {
            let previous = positions[index - 1]
            let current = positions[index]
            let controlX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: controlX, y: previous.y),
                control2: CGPoint(x: controlX, y: current.y)
            )
        }
        return path
    }

    private func position(for point: StatusTimelinePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * CGFloat(point.progress), y: size.height * (1 - point.level))
    }
}

private struct TimelineTimeChip: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(DashboardPalette.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DashboardPalette.controlFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(DashboardPalette.border, lineWidth: 1)
            }
    }
}

private struct ChartGridLines: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                for index in 0...4 {
                    let y = height * CGFloat(index) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }

                for index in stride(from: 1, through: 11, by: 3) {
                    let x = width * CGFloat(index) / 12
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
            }
            .stroke(DashboardPalette.innerStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }
    }
}

private extension FocusPetCore.FocusState {
    var fpStatus: FPStatus {
        switch self {
        case .focus: .focus
        case .distracted: .distracted
        case .breakTime: .rest
        case .away: .away
        }
    }

    var timelineColor: Color {
        switch self {
        case .focus: FPChartPalette.focus
        case .distracted: FPChartPalette.distracted
        case .breakTime: FPChartPalette.rest
        case .away: FPChartPalette.away
        }
    }

}

private extension ActivityCategory {
    var symbolName: String {
        switch self {
        case .work: "hammer.fill"
        case .entertainment: "play.rectangle.fill"
        case .ignore: "eye.slash.fill"
        case .neutral: "circle.dotted"
        }
    }

    var fpStatus: FPStatus {
        switch self {
        case .work: .focus
        case .entertainment: .distracted
        case .ignore, .neutral: .neutral
        }
    }

    var tint: Color {
        switch self {
        case .work: FPColor.focus600
        case .entertainment: FPColor.distracted600
        case .ignore: FPColor.textTertiary
        case .neutral: FPColor.textSecondary
        }
    }
}

private struct AppIconView: View {
    var appName: String
    var bundleID: String?
    var category: ActivityCategory
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            if let image = AppIconResolver.image(appName: appName, bundleID: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Image(systemName: category.symbolName)
                    .font(.system(size: max(13, size * 0.42), weight: .semibold))
                    .foregroundStyle(category.tint)
            }
        }
        .frame(width: size, height: size)
        .background(category.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.border.opacity(0.72), lineWidth: 1)
        }
    }
}

private enum AppIconResolver {
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()
    private nonisolated(unsafe) static var missingKeys: Set<String> = []

    static func image(appName: String, bundleID: String?) -> NSImage? {
        let key = "\(bundleID ?? "")|\(normalized(appName))"
        if missingKeys.contains(key) {
            return nil
        }

        let cacheKey = NSString(string: key)
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        guard let image = resolveImage(appName: appName, bundleID: bundleID) else {
            missingKeys.insert(key)
            return nil
        }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func resolveImage(appName: String, bundleID: String?) -> NSImage? {
        let workspace = NSWorkspace.shared
        if let bundleID,
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return workspace.icon(forFile: url.path)
        }

        for hintedBundleID in hintedBundleIDs(for: appName) {
            if let url = workspace.urlForApplication(withBundleIdentifier: hintedBundleID) {
                return workspace.icon(forFile: url.path)
            }
        }

        if let runningURL = runningApplicationURL(for: appName) {
            return workspace.icon(forFile: runningURL.path)
        }

        for candidate in candidateNames(for: appName) {
            for base in applicationSearchRoots {
                let url = base.appendingPathComponent("\(candidate).app")
                if FileManager.default.fileExists(atPath: url.path) {
                    return workspace.icon(forFile: url.path)
                }
            }
        }

        return nil
    }

    private static let applicationSearchRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
    ]

    private static let bundleHints: [String: [String]] = [
        "微信": ["com.tencent.xinWeChat", "com.tencent.xinwechat"],
        "wechat": ["com.tencent.xinWeChat", "com.tencent.xinwechat"],
        "企业微信": ["com.tencent.WeWorkMac"],
        "wecom": ["com.tencent.WeWorkMac"],
        "microsoftedge": ["com.microsoft.edgemac"],
        "edge": ["com.microsoft.edgemac"],
        "访达": ["com.apple.finder"],
        "finder": ["com.apple.finder"],
        "系统设置": ["com.apple.systempreferences"],
        "systemsettings": ["com.apple.systempreferences"],
        "活动监视器": ["com.apple.ActivityMonitor"],
        "activitymonitor": ["com.apple.ActivityMonitor"],
        "网易云音乐": ["com.netease.163music"],
        "neteasemusic": ["com.netease.163music"],
        "qq": ["com.tencent.qq"],
        "safari": ["com.apple.Safari"],
        "googlechrome": ["com.google.Chrome"],
        "chrome": ["com.google.Chrome"],
        "terminal": ["com.apple.Terminal"],
        "iterm": ["com.googlecode.iterm2"],
        "iterm2": ["com.googlecode.iterm2"],
        "xcode": ["com.apple.dt.Xcode"],
        "obsidian": ["md.obsidian"],
        "figma": ["com.figma.Desktop"],
        "steam": ["com.valvesoftware.steam"]
    ]

    private static let nameAliases: [String: [String]] = [
        "微信": ["WeChat"],
        "访达": ["Finder"],
        "系统设置": ["System Settings"],
        "活动监视器": ["Activity Monitor"],
        "网易云音乐": ["NeteaseMusic", "网易云音乐"],
        "qq": ["QQ"],
        "microsoftedge": ["Microsoft Edge"],
        "googlechrome": ["Google Chrome"]
    ]

    private static func hintedBundleIDs(for appName: String) -> [String] {
        bundleHints[normalized(appName)] ?? []
    }

    private static func candidateNames(for appName: String) -> [String] {
        let key = normalized(appName)
        var names = [appName]
        if let aliases = nameAliases[key] {
            names.append(contentsOf: aliases)
        }
        return Array(Set(names)).filter { !$0.isEmpty }
    }

    private static func runningApplicationURL(for appName: String) -> URL? {
        let key = normalized(appName)
        return NSWorkspace.shared.runningApplications.first { app in
            guard let name = app.localizedName else { return false }
            let runningKey = normalized(name)
            return runningKey == key || runningKey.contains(key) || key.contains(runningKey)
        }?.bundleURL
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

private struct SlidingSegmentOption<Value: Hashable>: Identifiable {
    var value: Value
    var title: String
    var symbol: String
    var tint: Color

    var id: String { String(describing: value) }
}

private struct SlidingSegmentedPicker<Value: Hashable>: View {
    var options: [SlidingSegmentOption<Value>]
    @Binding var selection: Value
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: compact ? 4 : 6) {
                        Image(systemName: option.symbol)
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        Text(option.title)
                            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(selected ? option.tint : DashboardPalette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.vertical, compact ? 6 : 8)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(option.tint.opacity(0.14))
                                .overlay {
                                    FPGlassLayer(
                                        role: .button,
                                        cornerRadius: 7,
                                        tint: option.tint,
                                        isSelected: true,
                                        intensity: 1.04
                                    )
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(option.tint.opacity(0.38), lineWidth: 1)
                                }
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(option.title)
            }
        }
        .padding(3)
        .fpGlassBackground(role: .control, cornerRadius: 9, tint: FPColor.focus500, intensity: 0.86)
    }
}

private struct NumberStepperControl: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String
    var status: FPStatus = .focus

    private var tint: Color {
        status.primary
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(value) \(suffix)")
                    .font(.headline.monospacedDigit())
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                stepButton(symbol: "minus") {
                    value = max(range.lowerBound, value - 1)
                }
                stepButton(symbol: "plus") {
                    value = min(range.upperBound, value + 1)
                }
            }
        }
        .padding(10)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }

    private func stepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DashboardPalette.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct TogglePillButton: View {
    var title: String
    var symbol: String
    @Binding var isOn: Bool
    var status: FPStatus = .focus

    private var tint: Color {
        status.primary
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? tint : DashboardPalette.secondaryText)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Toggle("", isOn: $isOn)
                    .fpToggleTint(status)
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .padding(10)
            .background(FPColor.cardSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(isOn ? tint.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? status.border : FPColor.borderSoft, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct ControlSliderRow: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var suffix: String = ""
    var status: FPStatus = .focus

    private var tint: Color {
        status.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(displayValue)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .fpSliderTint(status)
        }
        .padding(10)
        .background(FPColor.cardSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(status.border.opacity(0.72), lineWidth: 1)
        }
    }

    private var displayValue: String {
        if suffix == "%" {
            "\(Int((value * 100).rounded()))%"
        } else {
            "\(Int(value.rounded()))\(suffix)"
        }
    }
}

private func petPlacementOptions() -> [SlidingSegmentOption<PetPlacementMode>] {
    PetPlacementMode.allCases.map { placement in
        SlidingSegmentOption(
            value: placement,
            title: placement.title,
            symbol: placement.symbolName,
            tint: placement == .custom ? FPColor.petWarm500 : FPColor.focus500
        )
    }
}

private extension PetIntentKind {
    var fpStatus: FPStatus {
        switch self {
        case .quietCompanion, .dashboardGuide:
            return .focus
        case .focusRestHint, .breakCompanion, .breakEnding:
            return .rest
        case .distractedObserve:
            return .distracted
        case .nudgeGentle, .nudgeStrong:
            return .warning
        case .sleep:
            return .away
        case .welcomeBack, .mouseSummon:
            return .pet
        case .moveLeft, .moveRight, .moveUp, .moveDown, .dragged, .landing:
            return .neutral
        }
    }
}

private extension StateReason {
    var title: String {
        switch self {
        case .systemSleep: "系统睡眠"
        case .screenLocked: "屏幕锁定"
        case .longInputIdleAway: "长时间暂离"
        case .inputIdleDistracted: "无输入走神"
        case .activeBreak: "休息中"
        case .activeFocusSession: "专注会话"
        case .workCategory: "工作工具"
        case .entertainmentStable: "分心稳定"
        case .entertainmentGrace: "分心缓冲"
        case .frequentSwitching: "频繁切换"
        case .ignoredActivity: "不参与判断"
        case .previousStateHeld: "保持状态"
        case .neutralDefault: "默认判断"
        case .recentInputRecovery: "输入恢复"
        }
    }
}

struct NudgePanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("提醒记录", systemImage: "bell.badge.fill")
                .font(.headline)
            if model.nudges.isEmpty {
                Text("暂无提醒。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.nudges.suffix(8).reversed()) { nudge in
                    HStack {
                        Text(FocusPetFormatters.clock(nudge.time))
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .leading)
                        Text(nudge.reason.title)
                        Spacer()
                        Text(nudge.message)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .dashboardCard()
    }
}

struct DistributionView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        let spacing = DashboardLayout.cardGap
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                SectionTitle("状态占比")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 180), spacing: spacing), count: 4), spacing: spacing) {
                    RatioTile(state: FocusPetCore.FocusState.focus, seconds: model.summary.focusSeconds, total: model.summary.totalSeconds)
                    RatioTile(state: FocusPetCore.FocusState.distracted, seconds: model.summary.distractedSeconds, total: model.summary.totalSeconds)
                    RatioTile(state: FocusPetCore.FocusState.breakTime, seconds: model.summary.breakSeconds, total: model.summary.totalSeconds)
                    RatioTile(state: FocusPetCore.FocusState.away, seconds: model.summary.awaySeconds, total: model.summary.totalSeconds)
                }
                SectionTitle("识别统计")
                CategoryUsageChartPanel()
                SectionTitle("App 时间排行")
                AppUsageChartPanel()
                SectionTitle("工作量统计")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 180), spacing: spacing), count: 3), spacing: spacing) {
                    MetricTile(
                        title: "键入估算",
                        value: "\(FocusPetFormatters.compactCount(model.todayWorkload.estimatedTypedCharacters)) 次",
                        symbol: "keyboard",
                        tint: DashboardPalette.focusBlue
                    )
                    MetricTile(
                        title: "操作",
                        value: "\(FocusPetFormatters.compactCount(model.todayWorkload.pointerActionCount)) 次",
                        symbol: "cursorarrow.click",
                        tint: FPChartPalette.distracted
                    )
                    MetricTile(
                        title: "上下文切换",
                        value: "\(FocusPetFormatters.compactCount(model.todayWorkload.contextSwitchCount)) 次",
                        symbol: "arrow.triangle.2.circlepath",
                        tint: FPColor.away500
                    )
                }
            }
        }
    }
}

struct CategoryUsageChartPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var total: Int {
        model.summary.categoryUsage.reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ActivityCategory.userFacingClassificationCases) { category in
                CategoryUsageCard(
                    category: category,
                    seconds: model.summary.categorySeconds(category),
                    total: total,
                    appCount: model.summary.categoryUsage.first { $0.category == category }?.appCount ?? 0
                )
            }
        }
        .dashboardCard()
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 184), spacing: 10)]
    }
}

private struct CategoryUsageCard: View {
    var category: ActivityCategory
    var seconds: Int
    var total: Int
    var appCount: Int

    private var ratio: Double {
        total == 0 ? 0 : Double(seconds) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(category.tint)
                    .frame(width: 24, height: 24)
                    .background(category.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                Text(category.title)
                    .font(.headline)
                Spacer()
                Text(FocusPetFormatters.percentage(ratio))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            CompactMeter(ratio: ratio, tint: category.tint, height: 8)
                .frame(maxWidth: 150)

            HStack {
                Text(FocusPetFormatters.duration(seconds))
                    .font(.headline.monospacedDigit())
                Spacer()
                Text("\(appCount) App")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DashboardPalette.controlFill, in: Capsule())
                    .overlay {
                        Capsule().stroke(DashboardPalette.innerStroke, lineWidth: 1)
                    }
            }
            .foregroundStyle(seconds > 0 ? .primary : .secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }
}

private struct CompactMeter: View {
    var ratio: Double
    var tint: Color
    var height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DashboardPalette.trackFill)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(ratio > 0 ? 6 : 0, proxy.size.width * max(0, min(1, ratio))))
            }
        }
        .frame(height: height)
    }
}

private struct MiniMeter: View {
    var ratio: Double
    var tint: Color
    var breakdown: [FocusPetCore.FocusState: Int] = [:]
    var total: Int = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(DashboardPalette.trackFill)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(ratio > 0 ? 8 : 0, proxy.size.width * max(0, min(1, ratio))))
                    if !breakdown.isEmpty {
                        HStack(spacing: 1) {
                            ForEach(FocusPetCore.FocusState.allCases) { state in
                                let seconds = breakdown[state, default: 0]
                                if seconds > 0 {
                                    Rectangle()
                                        .fill(state.timelineColor.opacity(0.9))
                                        .frame(width: max(4, proxy.size.width * ratio * Double(seconds) / Double(max(1, total))))
                                }
                            }
                        }
                        .frame(width: max(ratio > 0 ? 8 : 0, proxy.size.width * max(0, min(1, ratio))), alignment: .leading)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(height: 12)
        .animation(.snappy(duration: 0.36, extraBounce: 0.05), value: ratio)
        .animation(.snappy(duration: 0.36, extraBounce: 0.05), value: total)
    }
}

private struct AppUsageCard: View {
    var item: AppUsageSummary
    var maxSeconds: Int

    private var ratio: Double {
        Double(item.seconds) / Double(max(1, maxSeconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                AppIconView(appName: item.appName, bundleID: item.bundleID, category: item.category, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.appName)
                        .font(.headline)
                        .lineLimit(1)
                    AppCategoryCorrectionMenu(
                        appName: item.appName,
                        bundleID: item.bundleID,
                        category: item.category
                    )
                }
                Spacer(minLength: 0)
                Text(FocusPetFormatters.duration(item.seconds))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            MiniMeter(ratio: ratio, tint: item.category.tint, breakdown: item.stateBreakdown, total: item.seconds)
                .frame(maxWidth: 180)

            if !item.stateBreakdown.isEmpty {
                HStack(spacing: 8) {
                    ForEach(FocusPetCore.FocusState.allCases) { state in
                        if item.stateBreakdown[state, default: 0] > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(state.timelineColor)
                                    .frame(width: 6, height: 6)
                                Text(state.title)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }
}

private struct TodayAppUsageBarChartPanel: View {
    var snapshot: TodayWindowInsightSnapshot

    private var items: [AppUsageDisplayItem] {
        Array(snapshot.appItems.prefix(6))
    }

    private var maxSeconds: Int {
        max(1, items.map(\.seconds).max() ?? 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let nameColumnWidth = clamped(proxy.size.width * 0.22, min: 132, max: 218)
            let durationColumnWidth = clamped(proxy.size.width * 0.10, min: 70, max: 90)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("时间去哪了")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    StatusPill(snapshot.rangeLabel, symbol: "clock")
                    StatusPill("\(items.count) 个应用", symbol: "number")
                }

                if items.isEmpty {
                    Text("暂无应用记录。")
                        .foregroundStyle(DashboardPalette.secondaryText)
                } else {
                    VStack(spacing: 3) {
                        HStack(spacing: 10) {
                            Text("")
                                .frame(width: 26)
                            Text("")
                                .frame(width: 24)
                            Text("App")
                                .frame(width: nameColumnWidth, alignment: .leading)
                            Text("时间分布")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("时长")
                                .frame(width: durationColumnWidth, alignment: .trailing)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)

                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            TodayAppUsageBarRow(
                                item: item,
                                rank: index + 1,
                                maxSeconds: maxSeconds,
                                nameColumnWidth: nameColumnWidth,
                                durationColumnWidth: durationColumnWidth
                            )
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(12)
        .animation(.snappy(duration: 0.36, extraBounce: 0.04), value: snapshot.animationKey)
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

private struct AppUsageDisplayItem: Identifiable {
    var id: String
    var appName: String
    var bundleID: String?
    var category: ActivityCategory
    var seconds: Int
    var stateBreakdown: [FocusPetCore.FocusState: Int]

    static func windowed(
        from stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        bounds: (start: Date, end: Date)
    ) -> [AppUsageDisplayItem] {
        struct Accumulator {
            var appName: String
            var bundleID: String?
            var seconds: Int = 0
            var hasUsageSeconds = false
            var stateBreakdown: [FocusPetCore.FocusState: Int] = [:]
            var categorySeconds: [ActivityCategory: Int] = [:]
        }

        var grouped: [String: Accumulator] = [:]
        for usage in appUsage where todayWindowOverlaps(usage.start, usage.end, bounds: bounds) {
            let category = todayWindowNormalizedCategory(usage.category)
            let seconds = todayWindowClippedSeconds(start: usage.start, end: usage.end, bounds: bounds)
            guard seconds > 0,
                  !todayWindowIsHiddenSystemUsage(appName: usage.appName, bundleID: usage.bundleID) else { continue }
            let key = todayWindowAppKey(appName: usage.appName, bundleID: usage.bundleID)
            var accumulator = grouped[key] ?? Accumulator(appName: usage.appName, bundleID: usage.bundleID)
            accumulator.seconds += seconds
            accumulator.hasUsageSeconds = true
            accumulator.bundleID = accumulator.bundleID ?? usage.bundleID
            accumulator.categorySeconds[category, default: 0] += seconds
            grouped[key] = accumulator
        }

        for segment in orderedStateSegments(stateSegments) where todayWindowOverlaps(segment.start, segment.end, bounds: bounds) {
            let category = todayWindowNormalizedCategory(segment.category)
            let seconds = todayWindowClippedSeconds(start: segment.start, end: segment.end, bounds: bounds)
            guard seconds > 0,
                  !todayWindowIsHiddenSystemUsage(appName: segment.appName, bundleID: segment.bundleID) else { continue }
            let key = todayWindowAppKey(appName: segment.appName, bundleID: segment.bundleID)
            var accumulator = grouped[key] ?? Accumulator(appName: segment.appName, bundleID: segment.bundleID)
            accumulator.bundleID = accumulator.bundleID ?? segment.bundleID
            accumulator.stateBreakdown[segment.state, default: 0] += seconds
            if !accumulator.hasUsageSeconds {
                accumulator.seconds += seconds
                accumulator.categorySeconds[category, default: 0] += seconds
            }
            grouped[key] = accumulator
        }

        return grouped.compactMap { key, accumulator in
            guard accumulator.seconds > 0 else { return nil }
            let category = accumulator.categorySeconds.max { lhs, rhs in lhs.value < rhs.value }?.key ?? .ignore
            return AppUsageDisplayItem(
                id: key,
                appName: accumulator.appName,
                bundleID: accumulator.bundleID,
                category: category,
                seconds: accumulator.seconds,
                stateBreakdown: accumulator.stateBreakdown
            )
        }
        .sorted { lhs, rhs in
            if lhs.seconds == rhs.seconds {
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
            return lhs.seconds > rhs.seconds
        }
    }

    static func merged(from summaries: [AppUsageSummary]) -> [AppUsageDisplayItem] {
        struct Accumulator {
            var appName: String
            var bundleID: String?
            var seconds: Int = 0
            var stateBreakdown: [FocusPetCore.FocusState: Int] = [:]
            var categorySeconds: [ActivityCategory: Int] = [:]
        }

        var grouped: [String: Accumulator] = [:]
        for item in summaries {
            guard !isHiddenSystemUsage(item) else { continue }
            let key = item.bundleID ?? item.appName.lowercased()
            var accumulator = grouped[key] ?? Accumulator(appName: item.appName, bundleID: item.bundleID)
            accumulator.seconds += item.seconds
            accumulator.bundleID = accumulator.bundleID ?? item.bundleID
            accumulator.categorySeconds[item.category == .neutral ? .ignore : item.category, default: 0] += item.seconds
            for (state, seconds) in item.stateBreakdown {
                accumulator.stateBreakdown[state, default: 0] += seconds
            }
            grouped[key] = accumulator
        }

        return grouped.map { key, accumulator in
            let category = accumulator.categorySeconds.max { lhs, rhs in lhs.value < rhs.value }?.key ?? .ignore
            return AppUsageDisplayItem(
                id: key,
                appName: accumulator.appName,
                bundleID: accumulator.bundleID,
                category: category,
                seconds: accumulator.seconds,
                stateBreakdown: accumulator.stateBreakdown
            )
        }
        .sorted { lhs, rhs in
            if lhs.seconds == rhs.seconds {
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
            return lhs.seconds > rhs.seconds
        }
    }

    private static func isHiddenSystemUsage(_ item: AppUsageSummary) -> Bool {
        let appName = item.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bundleID = item.bundleID?.lowercased() ?? ""
        return appName == "sleep"
            || appName == "loginwindow"
            || appName == "locked screen"
            || appName == "break"
            || appName == "away"
            || bundleID.contains("loginwindow")
    }
}

private struct TodayAppUsageBarRow: View {
    var item: AppUsageDisplayItem
    var rank: Int
    var maxSeconds: Int
    var nameColumnWidth: CGFloat
    var durationColumnWidth: CGFloat

    private var ratio: Double {
        Double(item.seconds) / Double(max(1, maxSeconds))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.secondaryText)
                .frame(width: 26, alignment: .leading)

            AppIconView(appName: item.appName, bundleID: item.bundleID, category: item.category, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.appName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                AppCategoryCorrectionMenu(
                    appName: item.appName,
                    bundleID: item.bundleID,
                    category: item.category,
                    compact: true
                )
            }
            .frame(width: nameColumnWidth, alignment: .leading)

            MiniMeter(ratio: ratio, tint: item.category.tint, breakdown: item.stateBreakdown, total: item.seconds)
                .frame(maxWidth: .infinity)
                .frame(height: 16)

            Text(FocusPetFormatters.duration(item.seconds))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.primaryText)
                .contentTransition(.numericText())
                .frame(width: durationColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(rank <= 3 ? DashboardPalette.controlFill : DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(rank <= 3 ? DashboardPalette.border : DashboardPalette.innerStroke, lineWidth: 1)
        }
        .animation(.snappy(duration: 0.36, extraBounce: 0.05), value: item.seconds)
    }
}

private struct AppCategoryCorrectionMenu: View {
    @EnvironmentObject private var model: FocusPetModel

    var appName: String
    var bundleID: String?
    var category: ActivityCategory
    var compact = false

    private var target: ClassificationTarget {
        ClassificationTarget(appName: appName, bundleID: bundleID)
    }

    private var selectedCategory: ActivityCategory {
        let resolvedCategory = model.categoryForRule(pattern: target.pattern, matchKind: target.matchKind) ?? category
        return resolvedCategory == .neutral ? .ignore : resolvedCategory
    }

    var body: some View {
        Menu {
            ForEach(ActivityCategory.userFacingClassificationCases) { category in
                Button {
                    model.setRule(pattern: target.pattern, matchKind: target.matchKind, category: category)
                } label: {
                    Label(category.correctionTitle, systemImage: category.symbolName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                FPBadge(
                    title: selectedCategory.title,
                    systemImage: selectedCategory.symbolName,
                    status: selectedCategory.fpStatus,
                    compact: compact
                )
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 8 : 9, weight: .bold))
                    .foregroundStyle(selectedCategory.fpStatus.strongText.opacity(0.72))
                    .padding(.trailing, compact ? 2 : 0)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("修改 \(appName) 的分类")
    }
}

private struct ClassificationTarget {
    var pattern: String
    var matchKind: RuleMatchKind

    init(appName: String, bundleID: String?) {
        if let bundleID,
           !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.pattern = bundleID
            self.matchKind = .bundleID
        } else {
            self.pattern = appName
            self.matchKind = .appName
        }
    }
}

struct AppUsageChartPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var items: ArraySlice<AppUsageSummary> {
        model.summary.appUsage.prefix(10)
    }

    private var maxSeconds: Int {
        max(1, items.map(\.seconds).max() ?? 1)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            if items.isEmpty {
                Text("暂无 App 使用统计。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items) { item in
                    AppUsageCard(item: item, maxSeconds: maxSeconds)
                }
            }
        }
        .dashboardCard()
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 10)]
    }
}

struct SessionsView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        let historyData = SessionsHistoryData(segments: model.stateSegments)

        ScrollView {
            VStack(alignment: .leading, spacing: DashboardLayout.cardGap) {
                AttentionHeatmapPanel(snapshot: historyData.snapshot)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .zIndex(10)

                FocusHistorySegmentsPanel(snapshot: historyData.workTimeline)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .zIndex(0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SessionsHistoryData {
    var snapshot: AttentionHistorySnapshot
    var workTimeline: WorkTimelineSnapshot

    init(segments: [StateSegment], now: Date = Date()) {
        let orderedSegments = orderedStateSegments(segments)
        snapshot = AttentionHistorySnapshot(orderedSegments: orderedSegments, now: now)
        workTimeline = WorkTimelineSnapshot(orderedSegments: orderedSegments, now: now)
    }
}

private enum AttentionHeatmapScope: Hashable {
    case week
    case month
}

private struct AttentionDurationBreakdown: Hashable {
    var focusSeconds = 0
    var distractedSeconds = 0
    var breakSeconds = 0
    var awaySeconds = 0

    var attentionSeconds: Int {
        focusSeconds + distractedSeconds
    }

    var trackedSeconds: Int {
        focusSeconds + distractedSeconds + breakSeconds + awaySeconds
    }

    var workSeconds: Int {
        focusSeconds + distractedSeconds + breakSeconds
    }

    var focusRatio: Double {
        guard attentionSeconds > 0 else { return 0 }
        return Double(focusSeconds) / Double(attentionSeconds)
    }

    var distractedRatio: Double {
        guard attentionSeconds > 0 else { return 0 }
        return Double(distractedSeconds) / Double(attentionSeconds)
    }

    mutating func add(state: FocusPetCore.FocusState, seconds: Int) {
        let safeSeconds = max(0, seconds)
        switch state {
        case .focus:
            focusSeconds += safeSeconds
        case .distracted:
            distractedSeconds += safeSeconds
        case .breakTime:
            breakSeconds += safeSeconds
        case .away:
            awaySeconds += safeSeconds
        }
    }

    mutating func merge(_ other: AttentionDurationBreakdown) {
        focusSeconds += other.focusSeconds
        distractedSeconds += other.distractedSeconds
        breakSeconds += other.breakSeconds
        awaySeconds += other.awaySeconds
    }
}

private struct AttentionDayBucket: Identifiable, Hashable {
    var date: Date
    var breakdown: AttentionDurationBreakdown

    var id: TimeInterval { date.timeIntervalSince1970 }
    var focusRatio: Double { breakdown.focusRatio }
    var attentionSeconds: Int { breakdown.attentionSeconds }
}

private struct AttentionWeekBucket: Identifiable {
    var start: Date
    var days: [AttentionDayBucket]

    var id: TimeInterval { start.timeIntervalSince1970 }

    var breakdown: AttentionDurationBreakdown {
        var result = AttentionDurationBreakdown()
        for day in days {
            result.merge(day.breakdown)
        }
        return result
    }
}

private struct AttentionMonthCalendar: Identifiable {
    var start: Date
    var title: String
    var days: [AttentionDayBucket?]
    var breakdown: AttentionDurationBreakdown

    var id: TimeInterval { start.timeIntervalSince1970 }
}

private struct AttentionHistorySnapshot {
    var weeks: [AttentionWeekBucket]
    var months: [AttentionMonthCalendar]
    var days: [AttentionDayBucket]
    var total: AttentionDurationBreakdown

    var currentWeekBreakdown: AttentionDurationBreakdown {
        weeks.last?.breakdown ?? AttentionDurationBreakdown()
    }

    var currentMonthBreakdown: AttentionDurationBreakdown {
        months.last?.breakdown ?? AttentionDurationBreakdown()
    }

    var activeDays: Int {
        days.filter { $0.attentionSeconds > 0 }.count
    }

    var averageFocusSecondsPerActiveDay: Int {
        guard activeDays > 0 else { return 0 }
        return total.focusSeconds / activeDays
    }

    var bestFocusDay: AttentionDayBucket? {
        days
            .filter { $0.breakdown.focusSeconds > 0 }
            .max { $0.breakdown.focusSeconds < $1.breakdown.focusSeconds }
    }

    var bestFocusWeek: AttentionWeekBucket? {
        weeks
            .filter { $0.breakdown.focusSeconds > 0 }
            .max { $0.breakdown.focusSeconds < $1.breakdown.focusSeconds }
    }

    func breakdown(for scope: AttentionHeatmapScope) -> AttentionDurationBreakdown {
        switch scope {
        case .week:
            return currentWeekBreakdown
        case .month:
            return currentMonthBreakdown
        }
    }

    func days(for scope: AttentionHeatmapScope) -> [AttentionDayBucket] {
        switch scope {
        case .week:
            return weeks.last?.days ?? []
        case .month:
            return months.last?.days.compactMap { $0 } ?? []
        }
    }

    func activeDays(for scope: AttentionHeatmapScope) -> Int {
        days(for: scope).filter { $0.attentionSeconds > 0 }.count
    }

    func averageFocusSecondsPerActiveDay(for scope: AttentionHeatmapScope) -> Int {
        let activeDays = activeDays(for: scope)
        guard activeDays > 0 else { return 0 }
        return breakdown(for: scope).focusSeconds / activeDays
    }

    func bestFocusDay(for scope: AttentionHeatmapScope) -> AttentionDayBucket? {
        days(for: scope)
            .filter { $0.breakdown.focusSeconds > 0 }
            .max { $0.breakdown.focusSeconds < $1.breakdown.focusSeconds }
    }

    init(orderedSegments: [StateSegment], now: Date = Date()) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2

        let today = calendar.startOfDay(for: now)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let currentMonthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let weekStarts = (0..<12).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0 - 11, to: currentWeekStart)
        }
        let monthStarts = (0..<6).compactMap {
            calendar.date(byAdding: .month, value: $0 - 5, to: currentMonthStart)
        }
        let earliest = min(weekStarts.first ?? today, monthStarts.first ?? today)
        let latest = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)

        var buckets: [Date: AttentionDayBucket] = [:]
        for segment in orderedSegments.reversed() {
            if segment.end <= earliest { break }
            let segmentStart = max(segment.start, earliest)
            let segmentEnd = min(segment.end, latest)
            guard segmentEnd > segmentStart else { continue }

            var cursor = segmentStart
            while cursor < segmentEnd {
                let dayStart = calendar.startOfDay(for: cursor)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
                let clippedEnd = min(dayEnd, segmentEnd)
                guard clippedEnd > cursor else { break }

                let seconds = Int(clippedEnd.timeIntervalSince(cursor).rounded())
                var bucket = buckets[dayStart] ?? AttentionDayBucket(date: dayStart, breakdown: AttentionDurationBreakdown())
                bucket.breakdown.add(state: segment.state, seconds: seconds)
                buckets[dayStart] = bucket
                cursor = clippedEnd
            }
        }

        var orderedDays: [AttentionDayBucket] = []
        var cursorDay = earliest
        while cursorDay < latest {
            orderedDays.append(buckets[cursorDay] ?? AttentionDayBucket(date: cursorDay, breakdown: AttentionDurationBreakdown()))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursorDay) else { break }
            cursorDay = nextDay
        }
        days = orderedDays

        var totalBreakdown = AttentionDurationBreakdown()
        for day in days {
            totalBreakdown.merge(day.breakdown)
        }
        total = totalBreakdown

        weeks = weekStarts.map { weekStart in
            let days = (0..<7).compactMap { offset -> AttentionDayBucket? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
                return buckets[day] ?? AttentionDayBucket(date: day, breakdown: AttentionDurationBreakdown())
            }
            return AttentionWeekBucket(start: weekStart, days: days)
        }

        months = monthStarts.map { monthStart in
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart.addingTimeInterval(31 * 86_400)
            let leadingBlankCount = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
            var cells = Array<AttentionDayBucket?>(repeating: nil, count: leadingBlankCount)
            var monthBreakdown = AttentionDurationBreakdown()
            var day = monthStart
            while day < nextMonth {
                let bucket = buckets[day] ?? AttentionDayBucket(date: day, breakdown: AttentionDurationBreakdown())
                cells.append(bucket)
                monthBreakdown.focusSeconds += bucket.breakdown.focusSeconds
                monthBreakdown.distractedSeconds += bucket.breakdown.distractedSeconds
                monthBreakdown.breakSeconds += bucket.breakdown.breakSeconds
                monthBreakdown.awaySeconds += bucket.breakdown.awaySeconds
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
            while cells.count % 7 != 0 {
                cells.append(nil)
            }
            return AttentionMonthCalendar(
                start: monthStart,
                title: Self.monthTitle(for: monthStart, calendar: calendar),
                days: cells,
                breakdown: monthBreakdown
            )
        }
    }

    private static func monthTitle(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.month], from: date)
        return "\(components.month ?? 0)月"
    }
}

private struct AttentionHeatmapPanel: View {
    var snapshot: AttentionHistorySnapshot
    @State private var scope: AttentionHeatmapScope = .week
    @State private var hoverState: AttentionHeatmapHoverState?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Label("注意力热力图", systemImage: "square.grid.3x3.fill")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 12)
                SlidingSegmentedPicker(options: scopeOptions, selection: $scope, compact: true)
                    .frame(width: 190)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        heatmapBody
                        HeatmapLegend()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(2)

                    AttentionInsightPanel(snapshot: snapshot, scope: scope)
                        .frame(width: 268)
                        .zIndex(0)
                }

                VStack(alignment: .leading, spacing: 12) {
                    heatmapBody
                    HeatmapLegend()
                    AttentionInsightPanel(snapshot: snapshot, scope: scope)
                }
            }
        }
        .dashboardCard(14)
        .coordinateSpace(name: AttentionHeatmapCoordinateSpace.name)
        .overlay(alignment: .topLeading) {
            heatmapHoverOverlay
        }
        .onAppear {
            scope = .week
        }
        .onChange(of: scope) { _, _ in
            hoverState = nil
        }
    }

    @ViewBuilder
    private var heatmapBody: some View {
        if scope == .week {
            WeeklyAttentionHeatmap(weeks: snapshot.weeks, hoverState: $hoverState)
        } else {
            MonthlyAttentionHeatmap(months: snapshot.months, hoverState: $hoverState)
        }
    }

    private var heatmapHoverOverlay: some View {
        GeometryReader { proxy in
            if let hoverState {
                let width: CGFloat = 204
                let origin = hoverOrigin(for: hoverState, panelSize: proxy.size, width: width)
                AttentionHeatmapHoverCard(day: hoverState.day, width: width)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: origin.x, y: origin.y)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    .zIndex(1_000)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.08), value: hoverState?.id)
    }

    private func hoverOrigin(
        for hoverState: AttentionHeatmapHoverState,
        panelSize: CGSize,
        width: CGFloat
    ) -> CGPoint {
        let horizontalPadding: CGFloat = 12
        let idealX: CGFloat
        switch hoverState.placement {
        case .leading:
            idealX = hoverState.cellFrame.minX - width - 8
        case .trailing:
            idealX = hoverState.cellFrame.maxX + 8
        }
        let x = min(
            max(horizontalPadding, idealX),
            max(horizontalPadding, panelSize.width - width - horizontalPadding)
        )
        let y = max(12, hoverState.cellFrame.minY - 10)
        return CGPoint(x: x, y: y)
    }

    private var scopeOptions: [SlidingSegmentOption<AttentionHeatmapScope>] {
        [
            SlidingSegmentOption(value: .week, title: "周视图", symbol: "calendar.badge.clock", tint: FPColor.focus500),
            SlidingSegmentOption(value: .month, title: "月视图", symbol: "calendar", tint: FPColor.away500)
        ]
    }
}

private struct AttentionInsightPanel: View {
    var snapshot: AttentionHistorySnapshot
    var scope: AttentionHeatmapScope

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("历史洞察", systemImage: "chart.xyaxis.line")
                .font(.subheadline.weight(.semibold))

            AttentionInsightRow(
                title: "\(scopeTitle)专注",
                value: FocusPetFormatters.duration(breakdown.focusSeconds),
                detail: FocusPetFormatters.percentage(breakdown.focusRatio),
                symbol: "calendar.badge.clock"
            )
            AttentionInsightRow(
                title: "\(scopePrefix)日均",
                value: FocusPetFormatters.duration(snapshot.averageFocusSecondsPerActiveDay(for: scope)),
                detail: "\(snapshot.activeDays(for: scope)) 天活跃",
                symbol: "sum"
            )
            if let bestDay = snapshot.bestFocusDay(for: scope) {
                AttentionInsightRow(
                    title: "\(scopePrefix)峰值",
                    value: dayTitle(bestDay.date),
                    detail: FocusPetFormatters.duration(bestDay.breakdown.focusSeconds),
                    symbol: "flame.fill"
                )
            }
            AttentionInsightRow(
                title: "\(scopeTitle)走神",
                value: FocusPetFormatters.duration(breakdown.distractedSeconds),
                detail: FocusPetFormatters.percentage(breakdown.distractedRatio),
                symbol: FocusPetCore.FocusState.distracted.symbolName
            )

            AttentionFocusRatioMeter(breakdown: breakdown)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DashboardPalette.focusBlue.opacity(0.16), lineWidth: 1)
        }
    }

    private var breakdown: AttentionDurationBreakdown {
        snapshot.breakdown(for: scope)
    }

    private var scopeTitle: String {
        scope == .week ? "本周" : "本月"
    }

    private var scopePrefix: String {
        scope == .week ? "周内" : "月内"
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}

private struct AttentionInsightRow: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashboardPalette.focusBlue)
                .frame(width: 25, height: 25)
                .background(DashboardPalette.focusBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(detail)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AttentionFocusRatioMeter: View {
    var breakdown: AttentionDurationBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("专注占比")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DashboardPalette.secondaryText)
                Spacer()
                Text(FocusPetFormatters.percentage(breakdown.focusRatio))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardPalette.focusBlue)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardPalette.trackFill.opacity(0.70))
                    Capsule()
                        .fill(DashboardPalette.focusBlue.gradient)
                        .frame(width: max(8, proxy.size.width * breakdown.focusRatio))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct AttentionSummaryPill: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        }
    }
}

private enum HeatmapHoverPlacement {
    case leading
    case trailing
}

private enum AttentionHeatmapCoordinateSpace {
    static let name = "attentionHeatmapPanel"
}

private struct AttentionHeatmapHoverState: Equatable {
    var day: AttentionDayBucket
    var cellFrame: CGRect
    var placement: HeatmapHoverPlacement

    var id: TimeInterval { day.id }
}

private struct WeeklyAttentionHeatmap: View {
    var weeks: [AttentionWeekBucket]
    @Binding var hoverState: AttentionHeatmapHoverState?

    var body: some View {
        VStack(alignment: .center, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                VStack(spacing: 5) {
                    Text("")
                        .frame(width: 24, height: 32)
                    ForEach(weekdayLabels, id: \.self) { label in
                        Text(label)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DashboardPalette.secondaryText)
                            .frame(width: 24, height: 22)
                    }
                }

                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    VStack(spacing: 5) {
                        VStack(spacing: 1) {
                            Text("W\(weekNumber(week.start))")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                            Text(dayLabel(week.start))
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(isCurrentWeek(week.start) ? DashboardPalette.focusBlue : DashboardPalette.secondaryText)
                        .frame(width: 26, height: 32)

                        ForEach(week.days) { day in
                            AttentionHeatmapCell(
                                day: day,
                                size: 22,
                                hoverPlacement: index >= max(0, weeks.count - 2) ? .leading : .trailing,
                                hoverState: $hoverState
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let first = weeks.first?.start,
               let last = weeks.last?.days.last?.date {
                Text("\(dayLabel(first)) - \(dayLabel(last))")
                    .frame(maxWidth: .infinity, alignment: .leading)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var weekdayLabels: [String] {
        ["一", "二", "三", "四", "五", "六", "日"]
    }

    private func weekNumber(_ date: Date) -> Int {
        Calendar(identifier: .gregorian).component(.weekOfYear, from: date)
    }

    private func dayLabel(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    private func isCurrentWeek(_ date: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
}

private struct MonthlyAttentionHeatmap: View {
    var months: [AttentionMonthCalendar]
    @Binding var hoverState: AttentionHeatmapHoverState?

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(months) { month in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(month.title)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(FocusPetFormatters.duration(month.breakdown.focusSeconds))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(DashboardPalette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 5), count: 7), spacing: 5) {
                        ForEach(Array(month.days.enumerated()), id: \.offset) { index, day in
                            AttentionHeatmapCell(
                                day: day,
                                size: 14,
                                hoverPlacement: index % 7 >= 5 ? .leading : .trailing,
                                hoverState: $hoverState
                            )
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DashboardPalette.innerStroke, lineWidth: 1)
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 156), spacing: 12)]
    }
}

private func attentionHeatmapWorkLevel(_ workSeconds: Int) -> Int {
    switch max(0, workSeconds) {
    case 0:
        return 0
    case 1..<1_800:
        return 1
    case 1_800..<7_200:
        return 2
    case 7_200..<14_400:
        return 3
    case 14_400..<21_600:
        return 4
    case 21_600..<28_800:
        return 5
    case 28_800..<36_000:
        return 6
    case 36_000..<43_200:
        return 7
    default:
        return 8
    }
}

private func attentionHeatmapColor(level: Int, focusRatio: Double = 0.78) -> Color {
    let level = min(8, max(0, level))
    guard level > 0 else { return FPColor.insetSurface }

    let intensity = Double(level) / 8
    let ratio = max(0, min(1, focusRatio))
    let hue: Double
    if ratio >= 0.72 {
        hue = 0.58
    } else if ratio >= 0.55 {
        hue = 0.48
    } else if ratio >= 0.38 {
        hue = 0.12
    } else {
        hue = 0.06
    }
    return Color(
        hue: hue,
        saturation: 0.18 + 0.56 * intensity,
        brightness: 0.98 - 0.30 * intensity
    )
}

private func attentionHeatmapColor(for breakdown: AttentionDurationBreakdown) -> Color {
    guard breakdown.workSeconds > 0 else {
        return DashboardPalette.trackFill.opacity(0.55)
    }
    return attentionHeatmapColor(
        level: attentionHeatmapWorkLevel(breakdown.workSeconds),
        focusRatio: breakdown.focusRatio
    )
}

private struct AttentionHeatmapCell: View {
    var day: AttentionDayBucket?
    var size: CGFloat
    var hoverPlacement: HeatmapHoverPlacement = .trailing
    @Binding var hoverState: AttentionHeatmapHoverState?

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous)
                .fill(fillColor)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous)
                        .stroke(isToday ? DashboardPalette.focusBlue : borderColor, lineWidth: isToday ? 1.8 : 0.7)
                }
                .overlay(alignment: .topTrailing) {
                    if isToday {
                        Circle()
                            .fill(DashboardPalette.focusBlue)
                            .frame(width: max(4, size * 0.24), height: max(4, size * 0.24))
                            .offset(x: 2, y: -2)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard let day else { return }
                    switch phase {
                    case .active:
                        let frame = proxy.frame(in: .named(AttentionHeatmapCoordinateSpace.name))
                        if hoverState?.id != day.id || hoverState?.cellFrame != frame {
                            hoverState = AttentionHeatmapHoverState(
                                day: day,
                                cellFrame: frame,
                                placement: hoverPlacement
                            )
                        }
                    case .ended:
                        if hoverState?.id == day.id {
                            hoverState = nil
                        }
                    }
                }
        }
        .frame(width: size, height: size)
        .zIndex(hoverState?.id == day?.id ? 50 : 0)
    }

    private var fillColor: Color {
        guard let day else { return Color.clear }
        return attentionHeatmapColor(for: day.breakdown)
    }

    private var borderColor: Color {
        day == nil ? Color.clear : DashboardPalette.innerStroke
    }

    private var isToday: Bool {
        guard let day else { return false }
        return Calendar(identifier: .gregorian).isDateInToday(day.date)
    }

}

private struct AttentionHeatmapHoverCard: View {
    var day: AttentionDayBucket
    var width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(attentionHeatmapColor(for: day.breakdown))
                    .frame(width: 12, height: 12)
                Text(dayTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(FocusPetFormatters.duration(day.breakdown.workSeconds))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(DashboardPalette.focusBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            HeatmapHoverRatioRow(title: "专注占比", ratio: day.breakdown.focusRatio, tint: DashboardPalette.focusBlue)
            HeatmapHoverLine(title: "专注", value: FocusPetFormatters.duration(day.breakdown.focusSeconds), tint: FocusPetCore.FocusState.focus.timelineColor)
            HeatmapHoverLine(title: "走神", value: FocusPetFormatters.duration(day.breakdown.distractedSeconds), tint: FocusPetCore.FocusState.distracted.timelineColor)
            HeatmapHoverLine(title: "休息", value: FocusPetFormatters.duration(day.breakdown.breakSeconds), tint: FocusPetCore.FocusState.breakTime.timelineColor)
            if day.breakdown.awaySeconds > 0 {
                HeatmapHoverLine(title: "暂离", value: FocusPetFormatters.duration(day.breakdown.awaySeconds), tint: FocusPetCore.FocusState.away.timelineColor)
            }
        }
        .padding(9)
        .frame(width: width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(attentionHeatmapColor(for: day.breakdown).opacity(0.30), lineWidth: 1)
                }
                .shadow(color: DashboardPalette.shadow.opacity(0.20), radius: 10, x: 0, y: 6)
        }
    }

    private var dayTitle: String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.month, .day], from: day.date)
        return "\(components.month ?? 0)月\(components.day ?? 0)日"
    }
}

private struct HeatmapHoverRatioRow: View {
    var title: String
    var ratio: Double
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(FocusPetFormatters.percentage(ratio))
                    .monospacedDigit()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DashboardPalette.secondaryText)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardPalette.trackFill.opacity(0.70))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(6, proxy.size.width * ratio))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct HeatmapHoverLine: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(DashboardPalette.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(DashboardPalette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.caption2.weight(.semibold))
    }
}

private struct HeatmapLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            content
            ScrollView(.horizontal, showsIndicators: false) {
                content
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke.opacity(0.85), lineWidth: 1)
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Text("时长")
                .font(.caption2.weight(.semibold))
            HStack(spacing: 3) {
                ForEach(0..<9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(attentionHeatmapColor(level: index))
                        .frame(width: 10, height: 10)
                }
            }
            Text("0-12h+")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
            Divider()
                .frame(height: 12)
            legendItem("高", color: attentionHeatmapColor(level: 6, focusRatio: 0.82))
            legendItem("稳", color: attentionHeatmapColor(level: 6, focusRatio: 0.62))
            legendItem("波动", color: attentionHeatmapColor(level: 6, focusRatio: 0.48))
            legendItem("偏离", color: attentionHeatmapColor(level: 6, focusRatio: 0.24))
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(DashboardPalette.secondaryText)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
        }
    }
}

private typealias WorkTimelineSnapshot = RecentWorkTimelineSnapshot
private typealias WorkTimelineInterval = FocusPetCore.WorkTimelineInterval
private typealias WorkTimelineRange = FocusPetCore.WorkTimelineRange

private struct FocusHistorySegmentsPanel: View {
    var snapshot: WorkTimelineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label("近24小时工作段", systemImage: "waveform.path.ecg")
                    .font(.headline.weight(.semibold))
                Spacer()
                StatusPill(statusCaption, symbol: "number")
            }

            LazyVGrid(columns: summaryColumns, spacing: 10) {
                AttentionSummaryPill(
                    title: "工作总计",
                    value: FocusPetFormatters.duration(snapshot.summary.workSeconds),
                    symbol: "clock.badge.checkmark",
                    tint: DashboardPalette.focusBlue
                )
                AttentionSummaryPill(
                    title: "专注占比",
                    value: FocusPetFormatters.percentage(snapshot.summary.focusRatio),
                    symbol: "percent",
                    tint: DashboardPalette.focusBlue
                )
                AttentionSummaryPill(
                    title: "走神",
                    value: FocusPetFormatters.duration(snapshot.summary.distractedSeconds),
                    symbol: FocusPetCore.FocusState.distracted.symbolName,
                    tint: FocusPetCore.FocusState.distracted.timelineColor
                )
                AttentionSummaryPill(
                    title: "休息",
                    value: FocusPetFormatters.duration(snapshot.summary.breakSeconds),
                    symbol: FocusPetCore.FocusState.breakTime.symbolName,
                    tint: DashboardPalette.restGreen
                )
            }

            if snapshot.hasData {
                FocusSegmentDurationChart(snapshot: snapshot)
            } else {
                Text(emptyStateText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 132, alignment: .center)
                    .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DashboardPalette.innerStroke, lineWidth: 1)
                    }
            }
        }
        .fpSemanticCard(status: .focus, padding: 14, radius: FPRadius.large)
        .dashboardPetAnchor(.historyWorkTimeline)
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 10)]
    }

    private var statusCaption: String {
        if snapshot.discardedShortIntervalCount > 0 {
            return "\(snapshot.intervals.count) 段 · 已降噪"
        }
        return "\(snapshot.intervals.count) 段 · 仅工作段"
    }

    private var emptyStateText: String {
        if snapshot.discardedShortIntervalCount > 0 {
            return "最近 24 小时暂无有效工作时间，短暂片段已自动过滤。"
        }
        return "最近 24 小时暂无工作时间。"
    }
}

private struct FocusSegmentDurationChart: View {
    var snapshot: WorkTimelineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSessionOverviewStrip(snapshot: snapshot)
                .frame(height: 66)

            LazyVGrid(columns: sessionColumns, spacing: 10) {
                ForEach(displayIntervals) { interval in
                    WorkSessionCard(interval: interval)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }

    private var displayIntervals: [WorkTimelineInterval] {
        snapshot.intervals
    }

    private var sessionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 245), spacing: 10)]
    }
}

private struct WorkSessionOverviewStrip: View {
    var snapshot: WorkTimelineSnapshot

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, snapshot.intervals.reduce(0) { $0 + $1.totalSeconds })
            let ranges = layoutRanges(total: total, width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                    Text("压缩工作段")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.62), in: Capsule())
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardPalette.trackFill.opacity(0.34))
                        .frame(height: 18)

                    ForEach(ranges) { range in
                        Capsule()
                            .fill(range.tint.gradient)
                            .frame(width: range.width, height: 18)
                            .offset(x: range.x)
                    }
                }
                .offset(y: 24)

                ForEach(ranges) { range in
                    if range.showsTimeLabel {
                        Text(range.timeLabel)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DashboardPalette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(width: range.width, alignment: .center)
                            .offset(x: range.x, y: 48)
                    }
                }
            }
        }
    }

    private func layoutRanges(total: Int, width: CGFloat) -> [CompressedWorkSessionRange] {
        var cursor: CGFloat = 0
        let gap: CGFloat = snapshot.intervals.count > 1 ? 4 : 0
        let intervalCount = CGFloat(snapshot.intervals.count)
        let usableWidth = max(0, width - gap * CGFloat(max(0, snapshot.intervals.count - 1)))
        let minimumSegmentWidth: CGFloat = 12
        let canUseMinimumWidth = intervalCount * minimumSegmentWidth <= usableWidth
        let remainingWidth = canUseMinimumWidth ? usableWidth - intervalCount * minimumSegmentWidth : usableWidth
        return snapshot.intervals.map { interval in
            let proportionalWidth = usableWidth * CGFloat(interval.totalSeconds) / CGFloat(max(1, total))
            let segmentWidth = canUseMinimumWidth
                ? minimumSegmentWidth + remainingWidth * CGFloat(interval.totalSeconds) / CGFloat(max(1, total))
                : proportionalWidth
            defer { cursor += segmentWidth + gap }
            return CompressedWorkSessionRange(
                x: cursor,
                width: segmentWidth,
                tint: interval.focusRatio >= 0.72 ? DashboardPalette.focusBlue : FocusPetCore.FocusState.distracted.timelineColor,
                timeLabel: "\(FocusPetFormatters.clock(interval.start))-\(FocusPetFormatters.clock(interval.end))",
                showsTimeLabel: segmentWidth >= 78
            )
        }
    }
}

private struct CompressedWorkSessionRange: Identifiable {
    var x: CGFloat
    var width: CGFloat
    var tint: Color
    var timeLabel: String
    var showsTimeLabel: Bool

    var id: String {
        "\(Int((x * 10).rounded()))-\(Int((width * 10).rounded()))-\(timeLabel)"
    }
}

private struct WorkSessionCard: View {
    var interval: WorkTimelineInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(FocusPetFormatters.clock(interval.start))-\(FocusPetFormatters.clock(interval.end))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(FocusPetFormatters.percentage(interval.focusRatio))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(interval.focusRatio >= 0.72 ? DashboardPalette.focusBlue : DashboardPalette.distractedRed)
            }

            Text(FocusPetFormatters.duration(interval.totalSeconds))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.primaryText)

            WorkSessionRangeBar(interval: interval)
                .frame(height: 12)

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 5) {
                ForEach(metrics) { metric in
                    WorkSessionMetric(title: metric.title, seconds: metric.seconds, tint: metric.tint)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(interval.focusRatio >= 0.72 ? DashboardPalette.focusBlue.opacity(0.20) : DashboardPalette.distractedRed.opacity(0.18), lineWidth: 1)
        }
    }

    private var metrics: [WorkSessionMetricItem] {
        [
            WorkSessionMetricItem(title: "专注", seconds: interval.breakdown.focusSeconds, tint: DashboardPalette.focusBlue),
            WorkSessionMetricItem(title: "走神", seconds: interval.breakdown.distractedSeconds, tint: FocusPetCore.FocusState.distracted.timelineColor),
            WorkSessionMetricItem(title: "休息", seconds: interval.breakdown.breakSeconds, tint: DashboardPalette.restGreen),
            WorkSessionMetricItem(title: "暂离", seconds: interval.breakdown.awaySeconds, tint: FocusPetCore.FocusState.away.timelineColor)
        ]
        .filter { $0.seconds > 0 }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 86), spacing: 6, alignment: .leading)]
    }
}

private struct WorkSessionMetricItem: Identifiable {
    var title: String
    var seconds: Int
    var tint: Color

    var id: String { title }
}

private struct WorkSessionRangeBar: View {
    var interval: WorkTimelineInterval

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DashboardPalette.trackFill.opacity(0.42))

                ForEach(interval.ranges) { range in
                    let x = rangeOffset(range, width: proxy.size.width)
                    let width = rangeWidth(range, width: proxy.size.width)
                    Capsule()
                        .fill(range.state.timelineColor.gradient)
                        .frame(width: max(3, width), height: proxy.size.height)
                        .offset(x: x)
                }
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.40), lineWidth: 0.8)
            }
        }
        .help(helpText)
    }

    private var helpText: String {
        var parts = [
            "专注 \(FocusPetFormatters.duration(interval.breakdown.focusSeconds))",
            "走神 \(FocusPetFormatters.duration(interval.breakdown.distractedSeconds))"
        ]
        if interval.breakdown.breakSeconds > 0 {
            parts.append("休息 \(FocusPetFormatters.duration(interval.breakdown.breakSeconds))")
        }
        if interval.breakdown.awaySeconds > 0 {
            parts.append("暂离 \(FocusPetFormatters.duration(interval.breakdown.awaySeconds))")
        }
        return parts.joined(separator: " · ")
    }

    private var span: TimeInterval {
        max(1, interval.end.timeIntervalSince(interval.start))
    }

    private func rangeOffset(_ range: WorkTimelineRange, width: CGFloat) -> CGFloat {
        width * CGFloat(max(0, range.start.timeIntervalSince(interval.start) / span))
    }

    private func rangeWidth(_ range: WorkTimelineRange, width: CGFloat) -> CGFloat {
        let clippedStart = max(range.start, interval.start)
        let clippedEnd = min(range.end, interval.end)
        return width * CGFloat(max(0, clippedEnd.timeIntervalSince(clippedStart) / span))
    }
}

private struct WorkSessionMetric: View {
    var title: String
    var seconds: Int
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
            Text(FocusPetFormatters.duration(seconds))
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(DashboardPalette.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FocusSegmentTimelineOverview: View {
    var snapshot: WorkTimelineSnapshot

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.34))

                timelineGrid(width: proxy.size.width, height: proxy.size.height)

                Capsule()
                    .fill(DashboardPalette.trackFill.opacity(0.34))
                    .frame(height: 24)
                    .offset(y: 48)

                ForEach(snapshot.intervals) { interval in
                    let intervalX = xOffset(for: interval.start, width: proxy.size.width)
                    let intervalWidth = max(4, xOffset(for: interval.end, width: proxy.size.width) - intervalX)
                    ZStack(alignment: .leading) {
                        ForEach(interval.ranges) { range in
                            let rangeX = rangeOffset(range, interval: interval, width: intervalWidth)
                            let rangeWidth = rangeWidth(range, interval: interval, width: intervalWidth)
                            Rectangle()
                                .fill(range.state.timelineColor.gradient)
                                .frame(width: max(2, rangeWidth), height: 24)
                                .offset(x: rangeX)
                        }
                    }
                    .frame(width: intervalWidth, height: 24, alignment: .leading)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(Color.white.opacity(0.48), lineWidth: 0.7)
                    }
                    .offset(x: intervalX, y: 48)
                    .help("\(FocusPetFormatters.clock(interval.start))-\(FocusPetFormatters.clock(interval.end)) · 工作 \(FocusPetFormatters.duration(interval.totalSeconds))")
                }

                ForEach(axisTicks, id: \.offset) { tick in
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(DashboardPalette.innerStroke.opacity(0.85))
                            .frame(width: 1, height: 36)
                        Text(axisLabel(tick.date))
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(DashboardPalette.secondaryText)
                            .fixedSize()
                    }
                    .offset(x: max(0, min(proxy.size.width - 34, proxy.size.width * tick.offset - 17)), y: 76)
                }

                HStack(spacing: 10) {
                    FocusTimelineLegendDot(title: "专注", tint: FocusPetCore.FocusState.focus.timelineColor)
                    FocusTimelineLegendDot(title: "走神", tint: FocusPetCore.FocusState.distracted.timelineColor)
                    if snapshot.summary.breakSeconds > 0 {
                        FocusTimelineLegendDot(title: "休息", tint: FocusPetCore.FocusState.breakTime.timelineColor)
                    }
                    Spacer(minLength: 8)
                    Text(summaryCaption)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
        }
    }

    private var span: TimeInterval {
        max(1, snapshot.end.timeIntervalSince(snapshot.start))
    }

    private var axisTicks: [(offset: Double, date: Date)] {
        (0...6).map { index in
            let ratio = Double(index) / 6
            return (ratio, snapshot.start.addingTimeInterval(span * ratio))
        }
    }

    private var summaryCaption: String {
        let focus = FocusPetFormatters.duration(snapshot.summary.focusSeconds)
        let distracted = FocusPetFormatters.duration(snapshot.summary.distractedSeconds)
        let rest = FocusPetFormatters.duration(snapshot.summary.breakSeconds)
        return snapshot.summary.breakSeconds > 0 ? "专注 \(focus) · 走神 \(distracted) · 休息 \(rest)" : "专注 \(focus) · 走神 \(distracted)"
    }

    private func xOffset(for date: Date, width: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1, date.timeIntervalSince(snapshot.start) / span))) * width
    }

    private func rangeOffset(_ range: WorkTimelineRange, interval: WorkTimelineInterval, width: CGFloat) -> CGFloat {
        let intervalSpan = max(1, interval.end.timeIntervalSince(interval.start))
        return width * CGFloat(max(0, range.start.timeIntervalSince(interval.start) / intervalSpan))
    }

    private func rangeWidth(_ range: WorkTimelineRange, interval: WorkTimelineInterval, width: CGFloat) -> CGFloat {
        let intervalSpan = max(1, interval.end.timeIntervalSince(interval.start))
        return width * CGFloat(max(0, min(range.end, interval.end).timeIntervalSince(max(range.start, interval.start)) / intervalSpan))
    }

    private func timelineGrid(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            for tick in axisTicks {
                let x = width * tick.offset
                path.move(to: CGPoint(x: x, y: 34))
                path.addLine(to: CGPoint(x: x, y: height - 20))
            }
        }
        .stroke(DashboardPalette.innerStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 7]))
    }

    private func axisLabel(_ date: Date) -> String {
        FocusPetFormatters.clock(date)
    }
}

private struct FocusTimelineLegendDot: View {
    var title: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(DashboardPalette.secondaryText)
        }
    }
}

private struct FocusSegmentHighlightChip: View {
    var interval: WorkTimelineInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(FocusPetFormatters.clock(interval.start))-\(FocusPetFormatters.clock(interval.end))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(FocusPetFormatters.percentage(interval.focusRatio))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(interval.focusRatio >= 0.6 ? DashboardPalette.focusBlue : DashboardPalette.distractedRed)
            }
            Text(FocusPetFormatters.duration(interval.totalSeconds))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(interval.focusRatio >= 0.6 ? DashboardPalette.focusBlue.opacity(0.18) : DashboardPalette.distractedRed.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct RestControlPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                breakTile
                autoJudgeTile
            }

            VStack(alignment: .leading, spacing: 12) {
                breakTile
                autoJudgeTile
            }
        }
    }

    private var breakTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("休息计时", systemImage: "cup.and.saucer.fill")
                .font(.headline)
            Text("休息由用户手动指定。休息结束后，系统自动回到专注/走神判断。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            NumberStepperControl(
                title: "休息",
                value: $model.settings.breakMinutes,
                range: 1...60,
                suffix: "分钟",
                status: .rest
            )
            .onChange(of: model.settings.breakMinutes) { _, _ in model.saveSettings() }
            Button {
                model.toggleBreakFromPet()
            } label: {
                Label(model.activeBreakSession == nil ? "开始休息" : "结束休息", systemImage: model.activeBreakSession == nil ? "play.fill" : "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .liquidGlassButtonStyle(prominent: true)
            .tint(FPColor.rest500)
        }
        .dashboardCard()
    }

    private var autoJudgeTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("自动判定", systemImage: "sparkles")
                .font(.headline)
            HStack(spacing: 10) {
                SessionStatPill(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: FPChartPalette.focus)
                SessionStatPill(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: FPChartPalette.distracted)
            }
            Text("无输入 \(FocusPetFormatters.duration(model.settings.judgment.inputIdleDistractedSeconds)) 后显示走神；持续到 \(FocusPetFormatters.duration(model.settings.judgment.idleAwaySeconds)) 会回填为暂离。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dashboardCard()
    }
}

struct SessionStatPill: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color = .secondary
    var appName: String?

    var body: some View {
        HStack(spacing: 7) {
            if let appName {
                AppIconView(appName: appName, bundleID: nil, category: .ignore, size: 24)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsView: View {
    @State private var expandedModules: Set<SettingsModule> = Set(SettingsModule.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(SettingsModule.allCases) { module in
                    SettingsAccordionCard(
                        module: module,
                        isExpanded: expandedModules.contains(module)
                    ) {
                        toggle(module)
                    } content: {
                        SettingsModuleContent(module: module)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func toggle(_ module: SettingsModule) {
        withAnimation(SettingsAccordionMotion.expandCollapse) {
            if expandedModules.contains(module) {
                expandedModules.remove(module)
            } else {
                expandedModules.insert(module)
            }
        }
    }
}

private enum SettingsAccordionMotion {
    static let expandCollapse = Animation.interactiveSpring(
        response: 0.34,
        dampingFraction: 0.86,
        blendDuration: 0.08
    )
}

private enum SettingsModule: String, CaseIterable, Identifiable, Hashable {
    case desktopWidgets
    case reminders
    case recognition
    case permissions
    case data
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recognition: "识别"
        case .permissions: "权限"
        case .desktopWidgets: "桌面状态卡"
        case .reminders: "提醒"
        case .data: "数据"
        case .about: "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .recognition: "状态判断"
        case .permissions: "系统设置入口"
        case .desktopWidgets: "当前与节奏卡"
        case .reminders: "气泡与系统通知"
        case .data: "本地记录"
        case .about: "应用信息"
        }
    }

    var symbolName: String {
        switch self {
        case .recognition: "slider.horizontal.3"
        case .permissions: "lock.shield.fill"
        case .desktopWidgets: "rectangle.on.rectangle.angled"
        case .reminders: "bell.badge.fill"
        case .data: "internaldrive.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recognition: DashboardPalette.distractedPeach
        case .permissions: FPColor.systemCyan500
        case .desktopWidgets: DashboardPalette.focusBlue
        case .reminders: DashboardPalette.focusBlue
        case .data: FPColor.systemCyan500
        case .about: DashboardPalette.gold
        }
    }

    var status: FPStatus {
        switch self {
        case .recognition: .distracted
        case .permissions: .privacy
        case .desktopWidgets: .focus
        case .reminders: .focus
        case .data: .privacy
        case .about: .warning
        }
    }
}

private struct SettingsAccordionCard<Content: View>: View {
    var module: SettingsModule
    var isExpanded: Bool
    var toggle: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: module.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(module.tint)
                        .frame(width: 30, height: 30)
                        .background(module.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.title)
                            .font(.headline)
                            .foregroundStyle(DashboardPalette.primaryText)
                        Text(module.subtitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(DashboardPalette.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(SettingsAccordionMotion.expandCollapse, value: isExpanded)
                }
            }
            .buttonStyle(.plain)
            .help(module.title)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.vertical, 10)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.985, anchor: .top)),
                        removal: .opacity
                            .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.985, anchor: .top))
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(SettingsAccordionMotion.expandCollapse, value: isExpanded)
        .fpSemanticCard(status: module.status, padding: 12, radius: FPRadius.large)
    }
}

private struct SettingsModuleContent: View {
    var module: SettingsModule

    var body: some View {
        switch module {
        case .recognition:
            RecognitionSettingsPanel()
        case .permissions:
            PermissionSettingsPanel()
        case .desktopWidgets:
            DesktopWidgetSettingsPanel()
        case .reminders:
            ReminderSettingsPanel()
        case .data:
            PrivacyDataSettingsPanel()
        case .about:
            AboutSettingsPanel()
        }
    }
}

private struct DesktopWidgetSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(DesktopWidgetCardKind.allCases) { kind in
                    TogglePillButton(
                        title: kind.title,
                        symbol: kind.symbolName,
                        isOn: binding(for: kind),
                        status: status(for: kind)
                    )
                    .help(kind.subtitle)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近节奏范围")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SlidingSegmentedPicker(
                    options: recentRhythmWindowOptions(),
                    selection: Binding(
                        get: { model.settings.desktopWidget.recentRhythmWindowHours },
                        set: { model.setDesktopWidgetRecentRhythmWindowHours($0) }
                    ),
                    compact: true
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("位置模式")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SlidingSegmentedPicker(
                    options: movementModeOptions(),
                    selection: Binding(
                        get: { model.settings.desktopWidget.movementMode },
                        set: { model.setDesktopWidgetMovementMode($0) }
                    ),
                    compact: true
                )
            }

            HStack(spacing: 8) {
                Button {
                    model.showAllDesktopWidgetCards()
                } label: {
                    Label("全部显示", systemImage: "checkmark.circle.fill")
                }
                Button {
                    model.hideAllDesktopWidgetCards()
                } label: {
                    Label("全部隐藏", systemImage: "rectangle.slash")
                }
                Spacer(minLength: 0)
            }
            .liquidGlassButtonStyle()
        }
    }

    private func binding(for kind: DesktopWidgetCardKind) -> Binding<Bool> {
        Binding(
            get: {
                switch kind {
                case .currentStatus:
                    model.settings.desktopWidget.currentStatusVisible
                case .recentRhythm:
                    model.settings.desktopWidget.recentRhythmVisible
                }
            },
            set: { visible in
                model.setDesktopWidgetCard(kind, visible: visible)
            }
        )
    }

    private func status(for kind: DesktopWidgetCardKind) -> FPStatus {
        switch kind {
        case .currentStatus:
            .focus
        case .recentRhythm:
            .privacy
        }
    }

    private func recentRhythmWindowOptions() -> [SlidingSegmentOption<Int>] {
        DesktopWidgetSettings.supportedRecentRhythmWindowHours.map { hours in
            SlidingSegmentOption(
                value: hours,
                title: "\(hours)h",
                symbol: "clock",
                tint: FPColor.focus500
            )
        }
    }

    private func movementModeOptions() -> [SlidingSegmentOption<DesktopWidgetMovementMode>] {
        [
            SlidingSegmentOption(
                value: .fixed,
                title: "固定位置",
                symbol: "pin.fill",
                tint: FPColor.away500
            ),
            SlidingSegmentOption(
                value: .free,
                title: "自由拖动",
                symbol: "hand.draw.fill",
                tint: FPColor.focus500
            )
        ]
    }
}

struct PetView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PetSettingsPanel()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            model.refreshPetPacks()
        }
    }
}

private enum JudgmentSensitivityPreset: String, CaseIterable, Identifiable, Hashable {
    case relaxed
    case balanced
    case strict
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: "宽松"
        case .balanced: "平衡"
        case .strict: "严格"
        case .custom: "自定义"
        }
    }

    var symbolName: String {
        switch self {
        case .relaxed: "leaf.fill"
        case .balanced: "circle.lefthalf.filled"
        case .strict: "bolt.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .relaxed: DashboardPalette.restGreen
        case .balanced: DashboardPalette.focusBlue
        case .strict: DashboardPalette.distractedRed
        case .custom: FPColor.away500
        }
    }

    var judgmentSettings: JudgmentSettings? {
        switch self {
        case .relaxed:
            JudgmentSettings()
        case .balanced:
            JudgmentSettings(inputIdleDistractedSeconds: 90, entertainmentDistractedSeconds: 30, focusRecoverySeconds: 5, idleAwaySeconds: 300)
        case .strict:
            JudgmentSettings(inputIdleDistractedSeconds: 60, entertainmentDistractedSeconds: 20, focusRecoverySeconds: 3, idleAwaySeconds: 240)
        case .custom:
            nil
        }
    }

    static func matching(_ settings: JudgmentSettings) -> JudgmentSensitivityPreset {
        for preset in [JudgmentSensitivityPreset.relaxed, .balanced, .strict] {
            if preset.judgmentSettings == settings {
                return preset
            }
        }
        return .custom
    }
}

private func judgmentPresetOptions() -> [SlidingSegmentOption<JudgmentSensitivityPreset>] {
    JudgmentSensitivityPreset.allCases.map {
        SlidingSegmentOption(value: $0, title: $0.title, symbol: $0.symbolName, tint: $0.tint)
    }
}

private struct RecognitionSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var selectedPresetOverride: JudgmentSensitivityPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecognitionDiagnosticsPanel()
            SlidingSegmentedPicker(
                options: judgmentPresetOptions(),
                selection: Binding(
                    get: { selectedPresetOverride ?? JudgmentSensitivityPreset.matching(model.settings.judgment) },
                    set: { preset in
                        selectedPresetOverride = preset == .custom ? .custom : nil
                        if let settings = preset.judgmentSettings {
                            model.settings.judgment = settings
                        }
                        model.saveSettings()
                    }
                ),
                compact: true
            )
            VStack(alignment: .leading, spacing: 8) {
                judgmentControls
            }
        }
    }

    @ViewBuilder
    private var judgmentControls: some View {
        NumberStepperControl(
            title: "无输入走神",
            value: $model.settings.judgment.inputIdleDistractedSeconds,
            range: 30...900,
            suffix: "秒",
            status: .distracted
        )
        .onChange(of: model.settings.judgment.inputIdleDistractedSeconds) { _, _ in saveCustomJudgment() }
        NumberStepperControl(
            title: "娱乐走神",
            value: $model.settings.judgment.entertainmentDistractedSeconds,
            range: 15...900,
            suffix: "秒",
            status: .distracted
        )
        .onChange(of: model.settings.judgment.entertainmentDistractedSeconds) { _, _ in saveCustomJudgment() }
        NumberStepperControl(
            title: "输入恢复专注",
            value: $model.settings.judgment.focusRecoverySeconds,
            range: 1...120,
            suffix: "秒",
            status: .focus
        )
        .onChange(of: model.settings.judgment.focusRecoverySeconds) { _, _ in saveCustomJudgment() }
        NumberStepperControl(
            title: "暂离回填",
            value: $model.settings.judgment.idleAwaySeconds,
            range: 180...3600,
            suffix: "秒",
            status: .away
        )
        .onChange(of: model.settings.judgment.idleAwaySeconds) { _, _ in saveCustomJudgment() }
    }

    private func saveCustomJudgment() {
        let matchedPreset = JudgmentSensitivityPreset.matching(model.settings.judgment)
        selectedPresetOverride = matchedPreset == .custom ? .custom : nil
        model.saveSettings()
    }
}

private struct RecognitionDiagnosticsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var diagnostic: RecognitionDiagnosticSnapshot {
        model.recognitionDiagnostic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Label("识别状态", systemImage: "waveform.path.ecg.rectangle")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                Button {
                    model.refreshRecognitionDiagnostics()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DashboardPalette.innerStroke, lineWidth: 1)
                }
                .help("刷新诊断")
            }

            RecognitionDiagnosticSummaryRow(diagnostic: diagnostic)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    DiagnosticPermissionChip(title: "输入监控", status: diagnostic.inputMonitoringStatus)
                }

                VStack(alignment: .leading, spacing: 6) {
                    DiagnosticPermissionChip(title: "输入监控", status: diagnostic.inputMonitoringStatus)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                RecognitionDiagnosticTile(title: "Bundle ID", value: diagnostic.bundleID ?? "未读取到", symbol: "shippingbox.fill", tint: DashboardPalette.appIndigo)
                RecognitionDiagnosticTile(title: "窗口标题", value: diagnostic.windowTitleStatus, symbol: "text.viewfinder", tint: diagnostic.windowTitle == nil ? DashboardPalette.distractedRed : DashboardPalette.restGreen)
                RecognitionDiagnosticTile(title: "规则库", value: "\(diagnostic.catalogEntryCount) 项 / \(diagnostic.defaultRuleCount) 条", symbol: "list.bullet.rectangle", tint: diagnostic.catalogEntryCount >= 20 ? DashboardPalette.restGreen : DashboardPalette.gold)
                RecognitionDiagnosticTile(title: "用户例外", value: "\(diagnostic.userRuleCount) 条", symbol: "slider.horizontal.3", tint: diagnostic.userRuleCount == 0 ? DashboardPalette.restGreen : DashboardPalette.distractedPeach)
            }

            if let windowTitle = diagnostic.windowTitle, !windowTitle.isEmpty {
                Text(windowTitle)
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if diagnostic.recordingPaused {
                Label("本地记录已暂停", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.distractedRed)
            }

            HStack {
                Spacer(minLength: 0)
                Button {
                    model.resetRecognitionRules()
                } label: {
                    Label("清空例外", systemImage: "eraser.fill")
                }
                .liquidGlassButtonStyle()
                .disabled(diagnostic.userRuleCount == 0)
            }
        }
        .padding(10)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
        .onAppear {
            model.refreshRecognitionDiagnostics()
        }
    }
}

private struct RecognitionDiagnosticSummaryRow: View {
    var diagnostic: RecognitionDiagnosticSnapshot

    private var statusTitle: String {
        if diagnostic.recordingPaused {
            return "已暂停"
        }
        if diagnostic.catalogEntryCount < 20 {
            return "规则待检查"
        }
        if !allPermissionsAllowed {
            return "权限待补"
        }
        return "运行中"
    }

    private var statusTint: Color {
        if diagnostic.recordingPaused {
            return DashboardPalette.distractedRed
        }
        if diagnostic.catalogEntryCount < 20 || !allPermissionsAllowed {
            return DashboardPalette.gold
        }
        return DashboardPalette.restGreen
    }

    private var statusSymbol: String {
        if diagnostic.recordingPaused {
            return "pause.circle.fill"
        }
        if diagnostic.catalogEntryCount < 20 || !allPermissionsAllowed {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var allPermissionsAllowed: Bool {
        diagnostic.inputMonitoringStatus == "已允许"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: diagnostic.category.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(diagnostic.category.tint)
                .frame(width: 30, height: 30)
                .background(diagnostic.category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.appName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                HStack(spacing: 6) {
                    Text(diagnostic.category.title)
                    Text(diagnostic.catalogStatus)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(DashboardPalette.secondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(statusTitle)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusTint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(statusTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(statusTint.opacity(0.18), lineWidth: 1)
            }
        }
        .padding(9)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }
}

private struct RecognitionDiagnosticTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DiagnosticPermissionChip: View {
    var title: String
    var status: String

    private var isAllowed: Bool {
        status == "已允许"
    }

    var body: some View {
        FPBadge(
            title: "\(title) \(status)",
            systemImage: isAllowed ? "checkmark.shield.fill" : "exclamationmark.circle.fill",
            status: isAllowed ? .rest : .warning
        )
    }
}

private struct PetSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var selectedIntent: PetIntentKind = .quietCompanion
    @State private var previewSourceActionID: String?
    private let randomActionOptions: [SlidingSegmentOption<Int>] = [
        SlidingSegmentOption(value: 30, title: "30 秒", symbol: "timer", tint: FPColor.petWarm500),
        SlidingSegmentOption(value: 60, title: "1 分钟", symbol: "timer", tint: FPColor.petWarm500),
        SlidingSegmentOption(value: 90, title: "90 秒", symbol: "timer", tint: FPColor.petWarm500),
        SlidingSegmentOption(value: 120, title: "2 分钟", symbol: "timer", tint: FPColor.petWarm500),
        SlidingSegmentOption(value: 300, title: "5 分钟", symbol: "timer", tint: FPColor.petWarm500)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("桌宠设置", systemImage: "pawprint.fill")
                    .font(.headline)
                Spacer()
                Button {
                    model.chooseAndImportPetPack()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                Button {
                    model.refreshPetPacks()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .liquidGlassButtonStyle()

            PetPackSelectionGrid()

            if let message = model.petImportMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = model.petImportErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(FPColor.error)
            }

            let hasPetPacks = !model.availablePetPacks.isEmpty
            if let record = model.availablePetPacks.first(where: { $0.id == model.settings.pet.selectedPackID }) {
                PetPackSummaryView(record: record)
                IntentActionMappingPanel(
                    record: record,
                    selectedIntent: $selectedIntent,
                    previewSourceActionID: $previewSourceActionID
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                TogglePillButton(
                    title: "显示桌宠",
                    symbol: "pawprint.fill",
                    isOn: Binding(
                        get: { !model.settings.pet.hidden },
                        set: { value in
                            guard hasPetPacks else { return }
                            model.settings.pet.hidden = !value
                            model.saveSettings()
                        }
                    ),
                    status: .rest
                )
                .disabled(!hasPetPacks)
                TogglePillButton(title: "动画", symbol: "sparkles", isOn: $model.settings.pet.animationEnabled, status: .pet)
                    .onChange(of: model.settings.pet.animationEnabled) { _, _ in model.saveSettings() }
                TogglePillButton(title: "音效", symbol: "speaker.wave.2.fill", isOn: $model.settings.pet.audioEnabled, status: .neutral)
                    .onChange(of: model.settings.pet.audioEnabled) { _, _ in model.saveSettings() }
                TogglePillButton(title: "悬浮状态弹窗", symbol: "text.bubble.fill", isOn: $model.settings.pet.hoverStatusEnabled, status: .focus)
                    .onChange(of: model.settings.pet.hoverStatusEnabled) { _, _ in model.saveSettings() }
            }

            RandomActionSwitchPanel(options: randomActionOptions)

            VStack(alignment: .leading, spacing: 8) {
                Text("位置")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                SlidingSegmentedPicker(
                    options: petPlacementOptions(),
                    selection: Binding(
                        get: { model.settings.pet.placement },
                        set: { model.setPetPlacement($0) }
                    ),
                    compact: true
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                ControlSliderRow(title: "大小", value: $model.settings.pet.size, range: 96...260, suffix: "px", status: .pet)
                    .onChange(of: model.settings.pet.size) { _, _ in model.saveSettings() }
                ControlSliderRow(title: "透明度", value: $model.settings.pet.opacity, range: 0.35...1, suffix: "%", status: .focus)
                    .onChange(of: model.settings.pet.opacity) { _, _ in model.saveSettings() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fpSemanticCard(status: .pet, padding: 12, radius: FPRadius.large)
        .dashboardPetAnchor(.settingsPetPanel)
    }
}

private struct RandomActionSwitchPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    var options: [SlidingSegmentOption<Int>]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                toggle
                    .frame(minWidth: 176)
                intervalPicker
            }

            VStack(alignment: .leading, spacing: 8) {
                toggle
                intervalPicker
            }
        }
    }

    private var toggle: some View {
        TogglePillButton(
            title: "随机换动作",
            symbol: "shuffle",
            isOn: $model.settings.pet.randomActionSwitchEnabled,
            status: .pet
        )
        .onChange(of: model.settings.pet.randomActionSwitchEnabled) { _, _ in
            model.saveSettings()
        }
    }

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("切换间隔", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.settings.pet.randomActionSwitchEnabled ? FPColor.textSecondary : FPColor.textTertiary)
                Spacer(minLength: 0)
                Text(randomActionIntervalTitle)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(model.settings.pet.randomActionSwitchEnabled ? DashboardPalette.primaryText : FPColor.textTertiary)
            }
            SlidingSegmentedPicker(
                options: options,
                selection: Binding(
                    get: { model.settings.pet.randomActionSwitchSeconds },
                    set: { seconds in
                        model.settings.pet.randomActionSwitchSeconds = seconds
                        model.saveSettings()
                    }
                ),
                compact: true
            )
            .disabled(!model.settings.pet.randomActionSwitchEnabled)
            .opacity(model.settings.pet.randomActionSwitchEnabled ? 1 : 0.48)
        }
        .padding(10)
        .background(FPColor.cardSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FPColor.petWarm500.opacity(model.settings.pet.randomActionSwitchEnabled ? 0.22 : 0.12), lineWidth: 1)
        }
    }

    private var randomActionIntervalTitle: String {
        let seconds = model.settings.pet.randomActionSwitchSeconds
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        if seconds % 60 != 0 {
            return "\(seconds) 秒"
        }
        return "\(seconds / 60) 分钟"
    }
}

private struct IntentActionMappingPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    var record: PetPackRecord
    @Binding var selectedIntent: PetIntentKind
    @Binding var previewSourceActionID: String?

    private var actions: [PetSourceActionSpec] {
        record.playableSourceActions
    }

    private var selectedAction: PetSourceActionSpec? {
        if let previewSourceActionID,
           let selected = actions.first(where: { $0.id == previewSourceActionID }) {
            return selected
        }
        if let resolved = model.resolvedSourceAction(for: selectedIntent, in: record),
           actions.contains(where: { $0.id == resolved.id }) {
            return resolved
        }
        return record.defaultSourceAction(for: selectedIntent) ?? actions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("意图映射台")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let selectedAction {
                        model.setSourceAction(selectedAction.id, for: selectedIntent)
                    }
                } label: {
                    Label(isApplied ? "已映射" : "映射", systemImage: isApplied ? "checkmark.circle.fill" : "link")
                }
                .liquidGlassButtonStyle(prominent: true)
                .disabled(selectedAction == nil)
            }

            SourceActionStageCard(record: record, action: selectedAction)
                .dashboardPetAnchor(.petPreviewStage)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PetIntentKind.userMappingCases) { intent in
                        let selected = intent == selectedIntent
                        Button {
                            selectedIntent = intent
                            previewSourceActionID = model.resolvedSourceAction(for: intent, in: record)?.id
                                ?? record.defaultSourceAction(for: intent)?.id
                                ?? actions.first?.id
                        } label: {
                            FPBadge(title: intent.title, systemImage: intent.symbolName, status: intent.fpStatus, filled: selected)
                        }
                        .buttonStyle(.plain)
                        .help(intent.title)
                    }
                }
                .padding(3)
            }
            .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(DashboardPalette.border, lineWidth: 1)
            }
            .liquidGlassSurface(cornerRadius: 9)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(actions) { action in
                        let selected = action.id == selectedAction?.id
                        Button {
                            previewSourceActionID = action.id
                        } label: {
                            FPBadge(title: action.title, systemImage: "play.fill", status: selected ? .focus : .neutral, filled: selected)
                        }
                        .buttonStyle(.plain)
                        .help(action.title)
                    }
                }
                .padding(3)
            }
            .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(DashboardPalette.border, lineWidth: 1)
            }
            .liquidGlassSurface(cornerRadius: 9)
            .onAppear {
                syncPreviewSelection()
            }
            .onChange(of: record.id) { _, _ in
                previewSourceActionID = nil
                syncPreviewSelection()
            }
            .onChange(of: selectedIntent) { _, _ in
                previewSourceActionID = nil
                syncPreviewSelection()
            }
        }
    }

    private var isApplied: Bool {
        guard let selectedAction else { return false }
        return model.isCustomSourceAction(selectedAction.id, for: selectedIntent, in: record)
    }

    private func syncPreviewSelection() {
        if let selected = previewSourceActionID,
           actions.contains(where: { $0.id == selected }) {
            return
        }
        previewSourceActionID = model.resolvedSourceAction(for: selectedIntent, in: record)?.id
            ?? record.defaultSourceAction(for: selectedIntent)?.id
            ?? actions.first?.id
    }
}

private struct SourceActionStageCard: View {
    var record: PetPackRecord
    var action: PetSourceActionSpec?

    private var frames: [URL] {
        guard let action else { return [] }
        return record.frameURLs(forSourceActionID: action.id)
    }

    private var previewFPS: Double {
        min(6, max(1, action?.fps ?? 6))
    }

    var body: some View {
        if action == nil || frames.isEmpty {
            stageContent(at: Date())
        } else {
            TimelineView(.periodic(from: Date(), by: 1.0 / previewFPS)) { timeline in
                stageContent(at: timeline.date)
            }
        }
    }

    private func stageContent(at date: Date) -> some View {
        ZStack {
            PetPreviewStageBackdrop(tint: FPColor.petWarm500)

            FPGlassLayer(
                role: .stage,
                cornerRadius: FPRadius.large,
                tint: FPColor.petWarm500,
                isSelected: true,
                intensity: 1.06
            )

            VStack {
                Spacer()
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                FPColor.petWarm500.opacity(0.22),
                                FPColor.focus300.opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 116
                        )
                    )
                    .frame(height: 56)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 38)
            }

            if let url = frameURL(at: date),
               let image = DashboardPreviewImageCache.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                    .padding(.bottom, 42)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            VStack {
                Spacer()
                HStack {
                    Text(action?.title ?? "未选择")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if let action {
                        Text("\(Int(min(action.fps, previewFPS).rounded())) fps")
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .fpGlassBackground(role: .control, cornerRadius: 8, tint: FPColor.petWarm500, intensity: 0.86)
                .padding(10)
            }
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.74),
                            FPColor.petWarm300.opacity(0.34),
                            FPColor.borderDefault.opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: FPColor.petWarm500.opacity(0.10), radius: 20, x: 0, y: 12)
    }

    private func frameURL(at date: Date) -> URL? {
        guard !frames.isEmpty else { return nil }
        let fps = previewFPS
        let index = Int(date.timeIntervalSinceReferenceDate * fps) % frames.count
        return frames[index]
    }
}

private struct PetPreviewStageBackdrop: View {
    var tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FPRadius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            FPColor.card.opacity(0.86),
                            FPColor.petWarm100.opacity(0.48),
                            FPColor.focus050.opacity(0.58)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(index == 0 ? Color.white.opacity(0.26) : tint.opacity(0.05))
                        .frame(height: 1)
                        .padding(.horizontal, CGFloat(18 + index * 10))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 22)

            HStack(spacing: 0) {
                StageLightBeam(taper: 0.42)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), tint.opacity(0.07), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 132)
                    .rotationEffect(.degrees(-8))
                    .offset(x: 12)

                Spacer(minLength: 0)

                StageLightBeam(taper: 0.42)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), FPColor.focus300.opacity(0.07), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 132)
                    .rotationEffect(.degrees(8))
                    .offset(x: -12)
            }
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
    }
}

private struct StageLightBeam: Shape {
    var taper: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topInset = rect.width * taper
        path.move(to: CGPoint(x: rect.minX + topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PermissionSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    private let permissionRefreshTimer = Timer.publish(every: 8.0, on: .main, in: .common).autoconnect()

    private let items: [PermissionSettingsItem] = [
        PermissionSettingsItem(
            destination: .inputMonitoring,
            subtitle: "键盘与鼠标事件计数",
            status: .privacy,
            canRequest: true
        ),
        PermissionSettingsItem(
            destination: .notifications,
            subtitle: "系统提醒横幅",
            status: .warning,
            canRequest: true
        ),
        PermissionSettingsItem(
            destination: .privacySecurity,
            subtitle: "macOS 隐私面板",
            status: .privacy,
            canRequest: false
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                PermissionSettingsRow(item: item)
                    .environmentObject(model)
            }
        }
        .onAppear {
            model.refreshSystemPermissionStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemPermissionStatuses()
        }
        .onReceive(permissionRefreshTimer) { _ in
            model.refreshSystemPermissionStatuses(refreshDiagnostics: false)
        }
    }
}

private struct PermissionSettingsItem: Identifiable {
    var destination: SystemSettingsDestination
    var subtitle: String
    var status: FPStatus
    var canRequest: Bool

    var id: SystemSettingsDestination { destination }
}

private struct PermissionSettingsRow: View {
    @EnvironmentObject private var model: FocusPetModel
    var item: PermissionSettingsItem

    var body: some View {
        FPListRow(status: item.status) {
            FPIconBox(systemImage: symbolName, status: item.status)
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.destination.title)
                    .font(FPTypography.bodyMedium)
                    .foregroundStyle(FPColor.textPrimary)
                Text(statusDetail ?? item.subtitle)
                    .font(FPTypography.caption)
                    .foregroundStyle(FPColor.textSecondary)
                    .lineLimit(1)
            }
        } trailing: {
            HStack(spacing: 8) {
                if let statusTitle {
                    FPBadge(title: statusTitle, systemImage: statusSymbol, status: permissionStatus)
                        .help(statusDetail ?? statusTitle)
                }
                if item.canRequest && !statusIsAllowed {
                    Button {
                        model.requestSystemPermission(item.destination)
                    } label: {
                        Label("请求", systemImage: "checkmark.shield.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(FPSoftButtonStyle(status: .privacy))
                    .help("请求\(item.destination.title)权限")
                }
                Button {
                    model.openSystemSettings(item.destination)
                } label: {
                    Label("打开", systemImage: "arrow.up.forward.app")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(FPSoftButtonStyle(status: .focus))
                .help("打开\(item.destination.title)设置")
            }
        }
    }

    private var symbolName: String {
        switch item.destination {
        case .inputMonitoring:
            return "keyboard"
        case .notifications:
            return "bell.badge.fill"
        case .privacySecurity:
            return "lock.shield.fill"
        }
    }

    private var statusTitle: String? {
        model.systemPermissionSnapshot.status(for: item.destination)?.title
    }

    private var statusDetail: String? {
        model.systemPermissionSnapshot.status(for: item.destination)?.detail
    }

    private var statusIsAllowed: Bool {
        model.systemPermissionSnapshot.status(for: item.destination)?.isAllowed ?? false
    }

    private var permissionStatus: FPStatus {
        guard let statusTitle else { return .warning }
        if statusIsAllowed {
            return .rest
        }
        if statusTitle.contains("未") {
            return .error
        }
        return .warning
    }

    private var statusSymbol: String {
        switch permissionStatus {
        case .rest:
            return "checkmark.shield.fill"
        case .error:
            return "xmark.octagon.fill"
        default:
            return "exclamationmark.circle.fill"
        }
    }
}

private struct ReminderSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    private let settingColumns = [GridItem(.adaptive(minimum: 168), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: settingColumns, spacing: 8) {
                TogglePillButton(title: "桌宠提醒", symbol: "bubble.left.and.bubble.right.fill", isOn: $model.settings.reminder.enablePetBubbles, status: .focus)
                    .onChange(of: model.settings.reminder.enablePetBubbles) { _, _ in model.saveSettings() }
                TogglePillButton(title: "系统通知", symbol: "bell.fill", isOn: $model.settings.reminder.enableSystemNotifications, status: .focus)
                    .onChange(of: model.settings.reminder.enableSystemNotifications) { _, _ in model.saveSettings() }
                    .help("系统通知只用于强走神和专注会话完成；长专注和休息结束由桌宠轻提醒。")
                TogglePillButton(title: "走神提醒", symbol: "eye.trianglebadge.exclamationmark", isOn: $model.settings.reminder.enableDistractedNudges, status: .distracted)
                    .onChange(of: model.settings.reminder.enableDistractedNudges) { _, _ in model.saveSettings() }
                TogglePillButton(title: "专注休息提醒", symbol: "figure.cooldown", isOn: $model.settings.reminder.enableFocusRestNudges, status: .rest)
                    .onChange(of: model.settings.reminder.enableFocusRestNudges) { _, _ in model.saveSettings() }
                TogglePillButton(title: "回归提醒", symbol: "hand.wave.fill", isOn: $model.settings.reminder.enableWelcomeBackNudges, status: .pet)
                    .onChange(of: model.settings.reminder.enableWelcomeBackNudges) { _, _ in model.saveSettings() }
            }
            LazyVGrid(columns: settingColumns, spacing: 8) {
                NumberStepperControl(title: "暂停时长", value: $model.settings.reminder.pauseMinutes, range: 5...240, suffix: "分钟", status: .warning)
                    .onChange(of: model.settings.reminder.pauseMinutes) { _, _ in model.saveSettings() }
                NumberStepperControl(title: "温和走神", value: $model.settings.reminder.lightDistractedMinutes, range: 1...60, suffix: "分钟", status: .distracted)
                    .onChange(of: model.settings.reminder.lightDistractedMinutes) { _, _ in model.saveSettings() }
                NumberStepperControl(title: "强提醒", value: $model.settings.reminder.strongDistractedMinutes, range: 2...120, suffix: "分钟", status: .distracted)
                    .onChange(of: model.settings.reminder.strongDistractedMinutes) { _, _ in model.saveSettings() }
                NumberStepperControl(title: "长专注", value: $model.settings.reminder.longFocusMinutes, range: 5...180, suffix: "分钟", status: .focus)
                    .onChange(of: model.settings.reminder.longFocusMinutes) { _, _ in model.saveSettings() }
                NumberStepperControl(title: "超长专注", value: $model.settings.reminder.veryLongFocusMinutes, range: 10...240, suffix: "分钟", status: .focus)
                    .onChange(of: model.settings.reminder.veryLongFocusMinutes) { _, _ in model.saveSettings() }
                NumberStepperControl(title: "提醒冷却", value: $model.settings.reminder.cooldownMinutes, range: 1...60, suffix: "分钟", status: .neutral)
                    .onChange(of: model.settings.reminder.cooldownMinutes) { _, _ in model.saveSettings() }
            }
            HStack {
                Text(model.reminderPauseTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let pauseUntil = model.settings.reminder.pauseUntil, pauseUntil > Date() {
                    Button("恢复") { model.resumeReminders() }
                } else {
                    Button(model.reminderPauseActionTitle) { model.pauseReminders() }
                }
            }
            .liquidGlassButtonStyle()
        }
    }
}

private struct PrivacyDataSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    private let actionColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TogglePillButton(title: "记录本地统计", symbol: "internaldrive.fill", isOn: recordingBinding, status: .privacy)
            HStack(spacing: 9) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FPColor.systemCyan500)
                    .frame(width: 28, height: 28)
                    .background(FPColor.systemCyan100, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("本机数据")
                        .font(.caption.weight(.semibold))
                    Text(model.recordingStatusTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(model.dataSizeTitle)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)
            }
            .padding(10)
            .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DashboardPalette.innerStroke, lineWidth: 1)
            }
            LazyVGrid(columns: actionColumns, spacing: 8) {
                Button {
                    model.exportData(redacted: true)
                } label: {
                    Label("导出脱敏统计", systemImage: "square.and.arrow.up")
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .liquidGlassButtonStyle()
                Button {
                    model.exportData(redacted: false)
                } label: {
                    Label("导出完整统计", systemImage: "doc.text")
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .liquidGlassButtonStyle()
                Button(role: .destructive) {
                    model.deleteAllData()
                } label: {
                    Label("清空数据", systemImage: "trash")
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .liquidGlassButtonStyle()
            }
            if let exportURL = model.exportURL {
                Text(exportURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var recordingBinding: Binding<Bool> {
        Binding(
            get: { !model.settings.privacy.pauseActivityRecording },
            set: { enabled in
                model.settings.privacy.pauseActivityRecording = !enabled
                model.saveSettings()
            }
        )
    }
}

private struct AboutSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus Pet 使用前台 App、窗口标题、输入空闲和专注/休息会话判断状态。所有统计保存在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PetPackSelectionGrid: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var pendingDeletion: PetPackRecord?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 188), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("资源包")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                if model.availablePetPacks.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(FPColor.textSecondary)
                            .frame(width: 38, height: 38)
                            .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("暂无桌宠资源包")
                                .font(.caption.weight(.semibold))
                            Text("导入单个 .zip 或包含 pet.json 的文件夹后再显示桌宠")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 54)
                    .fpInsetCard(status: .neutral)
                } else {
                    ForEach(model.availablePetPacks) { record in
                        PetPackSelectionCard(record: record) {
                            pendingDeletion = record
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "删除桌宠资源包？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDeletion {
                Button("删除 \(pendingDeletion.pack.name)", role: .destructive) {
                    model.deletePetPack(pendingDeletion)
                    self.pendingDeletion = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会从本机移除已导入副本，并在列表中隐藏同 ID 的随应用资源。重新导入资源包可恢复。")
        }
    }
}

private struct PetPackSelectionCard: View {
    @EnvironmentObject private var model: FocusPetModel
    var record: PetPackRecord
    var onDelete: () -> Void

    private var isSelected: Bool {
        model.settings.pet.selectedPackID == record.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.selectPetPack(record)
            } label: {
                HStack(spacing: 10) {
                    PetPackThumbnail(record: record)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.pack.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(record.pack.style)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? FPColor.rest500 : FPColor.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if model.canDeletePetPack(record) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FPColor.error)
                        .frame(width: 30, height: 30)
                        .background(FPColor.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("删除资源包")
            }
        }
        .frame(minHeight: 54)
        .fpInsetCard(status: .focus, isSelected: isSelected)
    }
}

private enum DashboardPreviewImageCache {
    private nonisolated(unsafe) static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = 32 * 1024 * 1024
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
        cache.setObject(image, forKey: key, cost: image.dashboardCacheCost)
        return image
    }
}

private extension NSImage {
    var dashboardCacheCost: Int {
        max(1, Int(size.width * size.height * 4))
    }
}

private struct PetPackThumbnail: View {
    var record: PetPackRecord

    var body: some View {
        ZStack {
            if let url = record.previewURL, let image = DashboardPreviewImageCache.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }
}

struct PetPackSummaryView: View {
    var record: PetPackRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = record.previewURL, let image = DashboardPreviewImageCache.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DashboardPalette.innerStroke, lineWidth: 1)
                    }
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 72)
                    .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DashboardPalette.innerStroke, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.pack.name)
                        .font(.headline)
                    StatusPill(
                        record.validation.isValid ? "可用" : "需修复",
                        symbol: record.validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        status: record.validation.isValid ? .neutral : .error
                    )
                }
                Text("作者 \(record.pack.author) · \(record.pack.style)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("动作 \(record.playableSourceActions.count) 个 · 音效 \(record.pack.audio.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !record.validation.errors.isEmpty {
                    Text("错误：\(record.validation.errors.map(\.title).joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(FPColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !record.validation.warnings.isEmpty {
                    Text("提示：\(record.validation.warnings.map(\.title).joined(separator: "、"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title2)
            Text(value)
                .font(.title2.weight(.semibold))
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }
}

struct RatioTile: View {
    var state: FocusPetCore.FocusState
    var seconds: Int
    var total: Int

    var body: some View {
        let ratio = total == 0 ? 0 : Double(seconds) / Double(total)
        VStack(alignment: .leading, spacing: 8) {
            Label(state.title, systemImage: state.symbolName)
                .font(.headline)
            ProgressView(value: ratio)
            Text("\(FocusPetFormatters.duration(seconds)) · \(Int((ratio * 100).rounded()))%")
                .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }
}

struct CategoryUsageTile: View {
    var category: ActivityCategory
    var seconds: Int
    var total: Int

    var body: some View {
        let ratio = total == 0 ? 0 : Double(seconds) / Double(total)
        VStack(alignment: .leading, spacing: 8) {
            Label(category.title, systemImage: symbolName)
                .font(.headline)
                .foregroundStyle(tint)
            ProgressView(value: ratio)
            Text("\(FocusPetFormatters.duration(seconds)) · \(FocusPetFormatters.percentage(ratio))")
                .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private var symbolName: String {
        switch category {
        case .work: "hammer.fill"
        case .entertainment: "play.rectangle.fill"
        case .ignore: "eye.slash.fill"
        case .neutral: "circle.dotted"
        }
    }

    private var tint: Color {
        switch category {
        case .work: FPColor.focus600
        case .entertainment: FPColor.distracted600
        case .ignore: FPColor.textTertiary
        case .neutral: FPColor.textSecondary
        }
    }
}

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusPill: View {
    var title: String
    var symbol: String
    var status: FPStatus

    init(_ title: String, symbol: String, status: FPStatus = .neutral) {
        self.title = title
        self.symbol = symbol
        self.status = status
    }

    var body: some View {
        FPBadge(title: title, systemImage: symbol, status: status)
    }
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .fpGlassBackground(
                role: interactive ? .button : .control,
                cornerRadius: cornerRadius,
                tint: DashboardPalette.focusBlue,
                isSelected: interactive,
                intensity: interactive ? 1 : 0.86
            )
    }
}

private struct LiquidGlassRefractionLayer: View {
    var cornerRadius: CGFloat
    var intensity: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.42 * intensity),
                        DashboardPalette.glassRefractionBlue.opacity(0.20 * intensity),
                        DashboardPalette.glassInnerShadow.opacity(0.16 * intensity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
            .overlay(alignment: .topLeading) {
                shape
                    .stroke(Color.white.opacity(0.18 * intensity), lineWidth: 0.6)
                    .padding(1)
            }
            .allowsHitTesting(false)
    }
}

extension View {
    func dashboardPetAnchor(_ anchor: DashboardPetAnchor) -> some View {
        modifier(DashboardPetAnchorModifier(anchor: anchor))
    }

    func dashboardCard(_ padding: CGFloat = 16, tint: Color = DashboardPalette.accent) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fpCard(padding: 0, radius: FPRadius.large, background: FPColor.card, border: FPColor.borderDefault)
    }

    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(LiquidGlassSurfaceModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            buttonStyle(FPPrimaryButtonStyle(status: .focus))
        } else {
            buttonStyle(FPSoftButtonStyle(status: .neutral))
        }
    }
}

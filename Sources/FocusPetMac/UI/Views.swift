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
    static let todayCanvasMinHeight: CGFloat = 640
}

private enum DashboardInteraction {
    static let contentSwitchDelayNanoseconds: UInt64 = 45_000_000
}

struct MainDashboardView: View {
    @State private var contentTab: DashboardTab = .today
    @State private var pendingContentTab: DashboardTab?

    var body: some View {
        ZStack {
            DashboardLiquidBackground()
            HStack(spacing: DashboardLayout.cardGap) {
                DashboardSidebar(currentSelection: contentTab) { tab in
                    scheduleContentSwitch(to: tab)
                }
                    .frame(width: DashboardLayout.sidebarWidth)

                VStack(alignment: .leading, spacing: 0) {
                    currentTabView
                        .padding(DashboardLayout.contentInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: DashboardLayout.shellCornerRadius, style: .continuous)
                        .fill(DashboardPalette.contentFill)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(0.52))
                                .frame(height: 1)
                                .padding(.horizontal, 14)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: DashboardLayout.shellCornerRadius, style: .continuous)
                                .stroke(DashboardPalette.border, lineWidth: 1)
                        }
                        .shadow(color: DashboardPalette.shadow.opacity(0.22), radius: 5, x: 0, y: 2)
                }
                .padding(.top, DashboardLayout.titlebarClearance)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .dashboardPetAnchor(.dashboardPanel)
            }

            DashboardEventBridge(contentTab: $contentTab)
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .tint(DashboardPalette.accent)
        .preferredColorScheme(.light)
        .onChange(of: contentTab) { _, tab in
            if pendingContentTab != nil && pendingContentTab != tab {
                pendingContentTab = nil
            }
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
        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow)
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
            NSWindow.didBecomeKeyNotification
        ]
        observerTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reportFrameSoon()
                }
            }
        }
    }
}

private enum DashboardPalette {
    static let backgroundTop = Color(red: 0.96, green: 0.985, blue: 1.0)
    static let backgroundMiddle = Color(red: 0.90, green: 0.95, blue: 1.0)
    static let backgroundBottom = Color(red: 0.96, green: 0.94, blue: 1.0)
    static let sidebarFill = Color.white.opacity(0.46)
    static let contentFill = Color.white.opacity(0.64)
    static let cardFill = Color.white.opacity(0.74)
    static let elevatedCardFill = Color.white.opacity(0.84)
    static let sidebarButtonHoverFill = Color.white.opacity(0.42)
    static let sidebarSelectedGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.92),
            Color(red: 0.88, green: 0.95, blue: 1.0).opacity(0.84),
            Color(red: 0.92, green: 0.96, blue: 0.91).opacity(0.70)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let controlFill = Color.white.opacity(0.58)
    static let rowFill = Color.white.opacity(0.42)
    static let trackFill = Color(red: 0.62, green: 0.68, blue: 0.78).opacity(0.20)
    static let border = Color.white.opacity(0.72)
    static let strongBorder = Color.white.opacity(0.92)
    static let innerStroke = Color(red: 0.48, green: 0.57, blue: 0.70).opacity(0.16)
    static let glassRim = Color.white.opacity(0.94)
    static let glassInnerShadow = Color(red: 0.20, green: 0.32, blue: 0.52).opacity(0.12)
    static let glassRefractionBlue = Color(red: 0.46, green: 0.68, blue: 1.0).opacity(0.24)
    static let glassRefractionViolet = Color(red: 0.67, green: 0.58, blue: 0.96).opacity(0.16)
    static let primaryText = Color(red: 0.15, green: 0.18, blue: 0.24)
    static let secondaryText = Color(red: 0.35, green: 0.40, blue: 0.50).opacity(0.82)
    static let mutedText = Color(red: 0.48, green: 0.54, blue: 0.63).opacity(0.70)
    static let accent = Color(red: 0.14, green: 0.46, blue: 0.92)
    static let gold = Color(red: 0.78, green: 0.49, blue: 0.10)
    static let focusBlue = Color(red: 0.10, green: 0.49, blue: 0.88)
    static let distractedPeach = Color(red: 0.88, green: 0.43, blue: 0.23)
    static let distractedRed = Color(red: 0.88, green: 0.16, blue: 0.19)
    static let restGreen = Color(red: 0.13, green: 0.62, blue: 0.34)
    static let awayPurple = Color(red: 0.47, green: 0.36, blue: 0.84)
    static let pauseGray = Color(red: 0.63, green: 0.68, blue: 0.74)
    static let shadow = Color(red: 0.26, green: 0.34, blue: 0.48).opacity(0.10)
    static let focusTint = Color(red: 0.14, green: 0.52, blue: 0.95)
    static let focusInk = Color(red: 0.05, green: 0.23, blue: 0.45)
    static let warmFocus = Color(red: 0.98, green: 0.70, blue: 0.23)
    static let surfaceHighlight = LinearGradient(
        colors: [
            Color.white.opacity(0.72),
            Color.white.opacity(0.24),
            Color.white.opacity(0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct DashboardLiquidBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        DashboardPalette.backgroundTop,
                        DashboardPalette.backgroundMiddle,
                        DashboardPalette.backgroundBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    let height = proxy.size.height
                    let width = proxy.size.width
                    path.move(to: CGPoint(x: -width * 0.05, y: height * 0.18))
                    path.addCurve(
                        to: CGPoint(x: width * 1.05, y: height * 0.11),
                        control1: CGPoint(x: width * 0.26, y: height * 0.03),
                        control2: CGPoint(x: width * 0.70, y: height * 0.25)
                    )
                    path.addLine(to: CGPoint(x: width * 1.05, y: height * 0.36))
                    path.addCurve(
                        to: CGPoint(x: -width * 0.05, y: height * 0.44),
                        control1: CGPoint(x: width * 0.70, y: height * 0.28),
                        control2: CGPoint(x: width * 0.26, y: height * 0.50)
                    )
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            DashboardPalette.focusBlue.opacity(0.24),
                            Color.white.opacity(0.20),
                            DashboardPalette.awayPurple.opacity(0.12)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(0.68)

                Path { path in
                    let height = proxy.size.height
                    let width = proxy.size.width
                    path.move(to: CGPoint(x: 0, y: height * 0.72))
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.60),
                        control1: CGPoint(x: width * 0.22, y: height * 0.56),
                        control2: CGPoint(x: width * 0.58, y: height * 0.78)
                    )
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            DashboardPalette.restGreen.opacity(0.13),
                            DashboardPalette.focusBlue.opacity(0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.82)
            }
            .ignoresSafeArea()
        }
    }
}

private struct DashboardSidebar: View {
    var currentSelection: DashboardTab
    var onSelect: (DashboardTab) -> Void
    @State private var selection: DashboardTab = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 30)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.86),
                                    DashboardPalette.restGreen.opacity(0.22),
                                    DashboardPalette.focusBlue.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(DashboardPalette.border, lineWidth: 1)
                        }
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DashboardPalette.restGreen)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus Pet")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("专注仪表盘")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
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
                        guard selection != tab else { return }
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        withAnimation(.snappy(duration: 0.16, extraBounce: 0.02)) {
                            selection = tab
                        }
                        onSelect(tab)
                    }
                }
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 24)
        }
        .frame(maxHeight: .infinity, alignment: .leading)
        .background {
            Rectangle()
                .fill(DashboardPalette.sidebarFill)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(DashboardPalette.innerStroke)
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

private struct DashboardSidebarButton: View {
    var tab: DashboardTab
    var isSelected: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(iconFill)
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 34, height: 34)

                Text(tab.title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)

                if isSelected {
                    Circle()
                        .fill(DashboardPalette.accent.opacity(0.78))
                        .frame(width: 6, height: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(isSelected ? DashboardPalette.primaryText : DashboardPalette.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundFill)
                    .opacity(isSelected || isHovering ? 1 : 0)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DashboardPalette.border, lineWidth: 1)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DashboardPalette.surfaceHighlight)
                                .opacity(0.28)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(DashboardPalette.accent.opacity(0.78))
                                .frame(width: 4)
                                .padding(.vertical, 11)
                                .padding(.leading, 2)
                        }
                    }
                    .shadow(color: DashboardPalette.shadow.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 3 : 1, x: 0, y: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuStatusHeader()
            MenuStatusStrip()
            Divider()
            MenuActionGrid()
            Divider()
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
        .onAppear { model.start() }
        .onAppear {
            model.registerOpenDashboardRequest { tab in
                model.selectedTab = tab
                openWindow(id: "dashboard")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPetOpenDashboardRequested)) { notification in
            model.openDashboard(tab: notification.object as? DashboardTab ?? model.selectedTab)
        }
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
            }
        }
    }
}

private struct MenuStatusStrip: View {
    @EnvironmentObject private var model: FocusPetModel

    private var total: Int {
        max(1, model.summary.totalSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                MenuMetricChip(title: "走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), tint: FocusPetCore.FocusState.distracted.timelineColor)
                MenuMetricChip(title: "休息", value: FocusPetFormatters.duration(model.summary.breakSeconds), tint: FocusPetCore.FocusState.breakTime.timelineColor)
                MenuMetricChip(title: "暂离", value: FocusPetFormatters.duration(model.summary.awaySeconds), tint: FocusPetCore.FocusState.away.timelineColor)
            }

            MenuStateStripBar(
                total: total,
                segments: [
                    (model.summary.focusSeconds, FocusPetCore.FocusState.focus.timelineColor),
                    (model.summary.distractedSeconds, FocusPetCore.FocusState.distracted.timelineColor),
                    (model.summary.breakSeconds, FocusPetCore.FocusState.breakTime.timelineColor),
                    (model.summary.awaySeconds, FocusPetCore.FocusState.away.timelineColor)
                ]
            )
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
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
        }
    }
}

private struct MenuStateStripBar: View {
    var total: Int
    var segments: [(seconds: Int, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DashboardPalette.trackFill)
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.seconds > 0 {
                            Capsule()
                                .fill(segment.color.gradient)
                                .frame(width: max(5, proxy.size.width * Double(segment.seconds) / Double(max(1, total))))
                        }
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }
}

private struct MenuActionGrid: View {
    @EnvironmentObject private var model: FocusPetModel

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            MenuActionButton(title: "打开面板", symbol: "macwindow", tint: .accentColor) {
                model.openDashboard(tab: .today)
            }

            MenuActionButton(title: "设置", symbol: "gearshape.fill", tint: .gray) {
                model.openDashboard(tab: .settings)
            }

            if model.activeBreakSession == nil {
                MenuActionButton(title: "休息 \(model.settings.breakMinutes) 分钟", symbol: "cup.and.saucer.fill", tint: DashboardPalette.restGreen) {
                    model.toggleBreakFromPet()
                }
            } else {
                MenuActionButton(title: "结束休息", symbol: "checkmark.circle.fill", tint: DashboardPalette.restGreen) {
                    model.toggleBreakFromPet()
                }
            }

            if let pauseUntil = model.settings.reminder.pauseUntil, pauseUntil > Date() {
                MenuActionButton(title: "恢复提醒", symbol: "bell.fill", tint: .orange) {
                    model.resumeReminders()
                }
            } else {
                MenuActionButton(title: "暂停提醒", symbol: "bell.slash.fill", tint: .orange) {
                    model.pauseReminders()
                }
            }

            MenuActionButton(
                title: model.settings.pet.hidden ? "显示桌宠" : "隐藏桌宠",
                symbol: model.settings.pet.hidden ? "eye.fill" : "eye.slash.fill",
                tint: .purple
            ) {
                model.togglePetHidden()
            }
        }
    }
}

private struct MenuActionButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var action: () -> Void

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
            .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DashboardPalette.innerStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct TodayView: View {
    var body: some View {
        GeometryReader { proxy in
            let canvasHeight = max(proxy.size.height, DashboardLayout.todayCanvasMinHeight)
            ScrollView(.vertical) {
                TodayDashboardCanvas(size: CGSize(width: proxy.size.width, height: canvasHeight))
                    .frame(width: proxy.size.width, height: canvasHeight, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct TodayDashboardCanvas: View {
    @EnvironmentObject private var model: FocusPetModel
    var size: CGSize

    var body: some View {
        let spacing = DashboardLayout.cardGap
        let contentHeight = max(0, size.height)
        let rowSpace = max(0, contentHeight - spacing * 3)
        let topHeight = clamped(rowSpace * 0.34, min: 214, max: 258)
        let stateHeight: CGFloat = 78
        let timelineHeight: CGFloat = 108
        let insightsHeight = max(220, rowSpace - topHeight - stateHeight - timelineHeight)
        let breakWidth = clamped(size.width * 0.31, min: 300, max: 390)

        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .top, spacing: spacing) {
                TodayFocusFeatureCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                BreakDurationControl()
                    .frame(width: min(breakWidth, max(260, size.width * 0.42)), height: topHeight)
            }
            .frame(maxWidth: .infinity, minHeight: topHeight, maxHeight: topHeight)

            HStack(spacing: spacing) {
                TodayStateRibbonCard(item: StateDurationItem(state: .distracted, seconds: model.summary.distractedSeconds))
                TodayStateRibbonCard(item: StateDurationItem(state: .breakTime, seconds: model.summary.breakSeconds))
                TodayStateRibbonCard(item: StateDurationItem(state: .away, seconds: model.summary.awaySeconds))
            }
            .frame(maxWidth: .infinity, minHeight: stateHeight, maxHeight: stateHeight)

            TimelinePanel()
                .frame(maxWidth: .infinity, minHeight: timelineHeight, maxHeight: timelineHeight)
                .dashboardPetAnchor(.todayTimeline)

            TodayInsightsGrid()
                .frame(maxWidth: .infinity, minHeight: insightsHeight, maxHeight: insightsHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(maximum, value))
    }
}

private struct TodayFocusFeatureCard: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ZStack(alignment: .leading) {
            DashboardMoonLandscape()
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("专注")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.focusInk)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(FocusPetFormatters.duration(model.summary.focusSeconds))
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(DashboardPalette.warmFocus)
                            .minimumScaleFactor(0.68)
                            .lineLimit(1)
                    }
                    Text(focusSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 18)

                HStack(spacing: 10) {
                    Label(model.currentDecision.state.title, systemImage: model.currentDecision.state.symbolName)
                        .foregroundStyle(model.currentDecision.state.timelineColor)
                    Text(model.currentSnapshot.appName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("切换 \(model.summary.switchCount) 次")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DashboardPalette.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DashboardPalette.border, lineWidth: 1)
                }
                .liquidGlassSurface(cornerRadius: 8)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(DashboardPalette.focusTint.opacity(0.86))
                .frame(width: 5)
                .padding(.vertical, 18)
                .padding(.leading, 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DashboardPalette.focusTint.opacity(0.42), lineWidth: 1)
        }
        .liquidGlassSurface(cornerRadius: 12)
        .dashboardPetAnchor(.todayFocusCard)
        .shadow(color: DashboardPalette.shadow.opacity(0.14), radius: 3, x: 0, y: 1)
    }

    private var focusSubtitle: String {
        if model.summary.focusSeconds == 0 {
            return "开始记录后会在这里显示今日专注时间"
        }
        return "当前节奏稳定，继续保持"
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
    var body: some View {
        GeometryReader { proxy in
            let spacing = DashboardLayout.cardGap
            let rightWidth = min(max(proxy.size.width * 0.27, 300), 380)
            let rhythmHeight = min(max(104, proxy.size.height * 0.38), proxy.size.height * 0.48)

            HStack(alignment: .top, spacing: spacing) {
                TodayAppUsageBarChartPanel()
                    .layoutPriority(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: spacing) {
                    CurrentRhythmPanel()
                        .frame(maxWidth: .infinity, minHeight: rhythmHeight, maxHeight: rhythmHeight)
                    TodayDistributionPanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: rightWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct CurrentRhythmPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .dashboardCard(12, tint: DashboardPalette.awayPurple)
    }

    private func ratio(for item: StateDurationItem) -> Double {
        guard model.summary.totalSeconds > 0 else { return 0 }
        return Double(item.seconds) / Double(model.summary.totalSeconds)
    }
}

private struct DashboardMoonLandscape: View {
    var compact = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.70),
                        DashboardPalette.focusBlue.opacity(0.22),
                        DashboardPalette.awayPurple.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RoundedRectangle(cornerRadius: compact ? 26 : 54, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.64),
                                DashboardPalette.gold.opacity(0.22),
                                DashboardPalette.focusBlue.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 130 : 280, height: compact ? 58 : 132)
                    .rotationEffect(.degrees(-8))
                    .position(x: proxy.size.width * (compact ? 0.78 : 0.70), y: proxy.size.height * (compact ? 0.42 : 0.50))
                    .opacity(0.82)

                CloudShape()
                    .fill(Color.white.opacity(0.36))
                    .frame(width: compact ? 84 : 132, height: compact ? 34 : 50)
                    .position(x: proxy.size.width * 0.86, y: proxy.size.height * 0.40)

                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    path.move(to: CGPoint(x: 0, y: height * 0.82))
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.68),
                        control1: CGPoint(x: width * 0.22, y: height * 0.62),
                        control2: CGPoint(x: width * 0.58, y: height * 0.88)
                    )
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(DashboardPalette.focusBlue.opacity(0.18))

                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    path.move(to: CGPoint(x: 0, y: height * 0.90))
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.82),
                        control1: CGPoint(x: width * 0.35, y: height * 0.76),
                        control2: CGPoint(x: width * 0.66, y: height * 0.95)
                    )
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            DashboardPalette.restGreen.opacity(0.18),
                            DashboardPalette.focusBlue.opacity(0.16)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
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
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(model.activeBreakSession == nil ? "休息计时" : "正在休息")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: model.activeBreakSession == nil ? "timer" : "pause.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DashboardPalette.restGreen)
                }

                if let subtitle = statusSubtitle(at: date) {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }

            Text(primaryTimeText(at: date))
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(DashboardPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let progress = activeBreakProgress(at: date) {
                CompactMeter(ratio: progress, tint: DashboardPalette.restGreen, height: 8)
            } else {
                BreakMinuteKeySelector(value: breakMinutesKeyBinding)
            }

            Button {
                model.toggleBreakFromPet()
            } label: {
                Text(model.activeBreakSession == nil ? "开始休息" : "结束休息")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .liquidGlassButtonStyle(prominent: true)
            .tint(model.activeBreakSession == nil ? DashboardPalette.restGreen.opacity(0.92) : DashboardPalette.distractedPeach)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DashboardPalette.restGreen.opacity(0.30),
                            DashboardPalette.restGreen.opacity(0.10),
                            DashboardPalette.elevatedCardFill,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DashboardPalette.restGreen.opacity(0.88))
                        .frame(width: 5)
                        .padding(.vertical, 14)
                        .padding(.leading, 2)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DashboardPalette.restGreen.opacity(0.38), lineWidth: 1)
                }
                .shadow(color: DashboardPalette.shadow.opacity(0.10), radius: 2, x: 0, y: 1)
        }
        .liquidGlassSurface(cornerRadius: 12)
    }

    private var breakMinutesKeyBinding: Binding<Int> {
        Binding(
            get: { model.settings.breakMinutes },
            set: { value in
                let next = max(1, min(30, value))
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

    private func statusSubtitle(at date: Date) -> String? {
        guard let rest = model.activeBreakSession else {
            return nil
        }
        let elapsed = max(0, Int(date.timeIntervalSince(rest.start)))
        return "已休息 \(FocusPetFormatters.duration(elapsed))"
    }

    private func activeBreakProgress(at date: Date) -> Double? {
        guard let rest = model.activeBreakSession else { return nil }
        let elapsed = max(0, date.timeIntervalSince(rest.start))
        return min(1, elapsed / Double(max(1, rest.targetDurationSeconds)))
    }
}

private struct BreakMinuteKeySelector: View {
    @Binding var value: Int

    private let options = [1, 3, 5, 10, 15, 20, 25, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(options, id: \.self) { minute in
                    Button {
                        value = minute
                    } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(minute == value ? DashboardPalette.restGreen : Color.white.opacity(0.78))
                                .frame(height: minute == value ? 30 : 25)
                                .overlay(alignment: .top) {
                                    Capsule()
                                        .fill(Color.white.opacity(minute == value ? 0.36 : 0.58))
                                        .frame(height: 3)
                                        .padding(.horizontal, 4)
                                        .padding(.top, 3)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(minute == value ? DashboardPalette.restGreen.opacity(0.45) : DashboardPalette.innerStroke, lineWidth: 1)
                                }

                            Text("\(minute)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(minute == value ? DashboardPalette.restGreen : DashboardPalette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help("\(minute) 分钟")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(DashboardPalette.innerStroke, lineWidth: 1)
            }

            HStack {
                Label("1-30 分钟", systemImage: "pianokeys")
                Spacer()
                Text("\(value) 分钟")
                    .monospacedDigit()
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(DashboardPalette.secondaryText)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("今日状态总览", systemImage: "chart.pie.fill")
                    .font(.headline)
                Spacer()
                StatusPill("切换 \(model.summary.switchCount) 次", symbol: "arrow.triangle.2.circlepath")
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
                    Text("专注占比")
                        .font(.system(size: max(9, side * 0.065), weight: .medium))
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
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
                    RestStatusTile(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: .green)
                    RestStatusTile(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: FocusPetCore.FocusState.distracted.timelineColor)
                    restAction
                }
                VStack(spacing: 10) {
                    RestStatusTile(title: "当前状态", value: model.currentDecision.state.title, symbol: model.currentDecision.state.symbolName, tint: model.currentDecision.state.timelineColor)
                    RestStatusTile(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: .green)
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
    var timelineColor: Color {
        switch self {
        case .focus: DashboardPalette.focusBlue
        case .distracted: DashboardPalette.distractedRed
        case .breakTime: DashboardPalette.restGreen
        case .away: DashboardPalette.pauseGray
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

    var tint: Color {
        switch self {
        case .work: DashboardPalette.restGreen
        case .entertainment: DashboardPalette.distractedPeach
        case .ignore: DashboardPalette.awayPurple
        case .neutral: DashboardPalette.focusBlue.opacity(0.85)
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
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(0.62))
                                .overlay(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(DashboardPalette.surfaceHighlight)
                                        .opacity(0.28)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(option.tint.opacity(0.24), lineWidth: 1)
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
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(DashboardPalette.border, lineWidth: 1)
        }
        .liquidGlassSurface(cornerRadius: 9)
    }
}

private struct NumberStepperControl: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var suffix: String
    var tint: Color = .blue

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
    var tint: Color = .blue

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
                Capsule()
                    .fill(isOn ? tint.opacity(0.70).gradient : DashboardPalette.trackFill.gradient)
                    .frame(width: 34, height: 18)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .padding(2)
                            .shadow(color: DashboardPalette.shadow.opacity(0.12), radius: 1, x: 0, y: 1)
                    }
            }
            .padding(10)
            .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(isOn ? tint.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? tint.opacity(0.22) : DashboardPalette.innerStroke, lineWidth: 1)
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
    var tint: Color = .blue

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
                .tint(tint)
        }
        .padding(10)
        .background(DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)
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
            tint: placement == .custom ? .purple : .blue
        )
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
                SectionTitle("切换统计")
                MetricTile(title: "今日 App 片段", value: "\(model.summary.switchCount)", symbol: "arrow.triangle.2.circlepath", tint: .purple)
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
                    Text(item.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

struct TodayAppUsageBarChartPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var items: [AppUsageDisplayItem] {
        Array(AppUsageDisplayItem.merged(from: model.summary.appUsage).prefix(5))
    }

    private var maxSeconds: Int {
        max(1, items.map(\.seconds).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("应用使用排行（今日）")
                    .font(.headline.weight(.semibold))
                Spacer()
                StatusPill("\(items.count) 个应用", symbol: "number")
            }

            if items.isEmpty {
                Text("暂无 App 使用统计。")
                    .foregroundStyle(DashboardPalette.secondaryText)
            } else {
                VStack(spacing: 5) {
                    HStack(spacing: 10) {
                        Text("")
                            .frame(width: 26)
                        Text("App")
                            .frame(width: 176, alignment: .leading)
                        Text("时间分布")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("时长")
                            .frame(width: 68, alignment: .trailing)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TodayAppUsageBarRow(item: item, rank: index + 1, maxSeconds: maxSeconds)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard(12)
    }
}

private struct AppUsageDisplayItem: Identifiable {
    var id: String
    var appName: String
    var bundleID: String?
    var category: ActivityCategory
    var seconds: Int
    var stateBreakdown: [FocusPetCore.FocusState: Int]

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
            || bundleID.contains("loginwindow")
    }
}

private struct TodayAppUsageBarRow: View {
    var item: AppUsageDisplayItem
    var rank: Int
    var maxSeconds: Int

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
                Text(item.category.title)
                    .font(.caption2)
                    .foregroundStyle(item.category.tint)
            }
            .frame(width: 130, alignment: .leading)

            MiniMeter(ratio: ratio, tint: item.category.tint, breakdown: item.stateBreakdown, total: item.seconds)
                .frame(maxWidth: .infinity)
                .frame(height: 16)

            Text(FocusPetFormatters.duration(item.seconds))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.primaryText)
                .frame(width: 68, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(rank <= 3 ? DashboardPalette.controlFill : DashboardPalette.rowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(rank <= 3 ? DashboardPalette.border : DashboardPalette.innerStroke, lineWidth: 1)
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

                FocusHistorySegmentsPanel(snapshot: historyData.workTimeline)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
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
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        heatmapBody
                        HeatmapLegend()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AttentionInsightPanel(snapshot: snapshot, scope: scope)
                        .frame(width: 268)
                }

                VStack(alignment: .leading, spacing: 14) {
                    heatmapBody
                    AttentionInsightPanel(snapshot: snapshot, scope: scope)
                    HeatmapLegend()
                }
            }
        }
        .dashboardCard(14, tint: DashboardPalette.focusBlue)
        .onAppear {
            scope = .week
        }
    }

    @ViewBuilder
    private var heatmapBody: some View {
        if scope == .week {
            WeeklyAttentionHeatmap(weeks: snapshot.weeks)
        } else {
            MonthlyAttentionHeatmap(months: snapshot.months)
        }
    }

    private var scopeOptions: [SlidingSegmentOption<AttentionHeatmapScope>] {
        [
            SlidingSegmentOption(value: .week, title: "周视图", symbol: "calendar.badge.clock", tint: DashboardPalette.focusBlue),
            SlidingSegmentOption(value: .month, title: "月视图", symbol: "calendar", tint: DashboardPalette.awayPurple)
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

private struct WeeklyAttentionHeatmap: View {
    var weeks: [AttentionWeekBucket]

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

                ForEach(weeks) { week in
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
                            AttentionHeatmapCell(day: day, size: 22)
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
                        ForEach(Array(month.days.enumerated()), id: \.offset) { _, day in
                            AttentionHeatmapCell(day: day, size: 14)
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

private func attentionHeatmapFocusLevel(_ focusSeconds: Int) -> Int {
    switch max(0, focusSeconds) {
    case 0..<900:
        return 0
    case 900..<2_700:
        return 1
    case 2_700..<5_400:
        return 2
    case 5_400..<10_800:
        return 3
    case 10_800..<14_400:
        return 4
    default:
        return 5
    }
}

private func attentionHeatmapBlueColor(_ level: Int) -> Color {
    switch min(5, max(0, level)) {
    case 0:
        return Color(red: 0.88, green: 0.94, blue: 1.00)
    case 1:
        return Color(red: 0.72, green: 0.85, blue: 0.99)
    case 2:
        return Color(red: 0.53, green: 0.74, blue: 0.98)
    case 3:
        return Color(red: 0.33, green: 0.62, blue: 0.95)
    case 4:
        return Color(red: 0.16, green: 0.49, blue: 0.89)
    default:
        return Color(red: 0.06, green: 0.34, blue: 0.72)
    }
}

private struct AttentionHeatmapCell: View {
    var day: AttentionDayBucket?
    var size: CGFloat

    var body: some View {
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
            .help(helpText)
    }

    private var fillColor: Color {
        guard let day else { return Color.clear }
        guard day.attentionSeconds > 0 else {
            return DashboardPalette.trackFill.opacity(0.55)
        }
        let level = attentionHeatmapFocusLevel(day.breakdown.focusSeconds)
        return attentionHeatmapBlueColor(level)
    }

    private var borderColor: Color {
        day == nil ? Color.clear : DashboardPalette.innerStroke
    }

    private var isToday: Bool {
        guard let day else { return false }
        return Calendar(identifier: .gregorian).isDateInToday(day.date)
    }

    private var helpText: String {
        guard let day else { return "" }
        return "\(dayLabel(day.date)) · 专注 \(FocusPetFormatters.duration(day.breakdown.focusSeconds)) · 走神 \(FocusPetFormatters.duration(day.breakdown.distractedSeconds))"
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}

private struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("少")
                .font(.caption2.weight(.medium))
                .foregroundStyle(DashboardPalette.secondaryText)
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(attentionHeatmapBlueColor(index))
                        .frame(width: 15, height: 15)
                }
            }
            Text("多")
                .font(.caption2.weight(.medium))
                .foregroundStyle(DashboardPalette.secondaryText)
            Spacer()
        }
    }
}

private struct WorkTimelineInterval: Identifiable {
    var start: Date
    var end: Date
    var ranges: [StatusStripRange]
    var breakdown: AttentionDurationBreakdown

    var id: String {
        "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))-\(ranges.count)"
    }

    var totalSeconds: Int {
        max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    var activeSeconds: Int {
        breakdown.workSeconds
    }

    var focusRatio: Double {
        breakdown.focusRatio
    }
}

private struct WorkTimelineSnapshot {
    var start: Date
    var end: Date
    var intervals: [WorkTimelineInterval]
    var summary: AttentionDurationBreakdown

    var hasData: Bool {
        !intervals.isEmpty
    }

    var longestInterval: WorkTimelineInterval? {
        intervals.max { $0.totalSeconds < $1.totalSeconds }
    }

    init(orderedSegments: [StateSegment], now: Date = Date()) {
        let windowEnd = now
        let windowStart = now.addingTimeInterval(-86_400)
        let maxSessionBridgeGap: TimeInterval = 20 * 60
        var result: [WorkTimelineInterval] = []
        var currentStart: Date?
        var currentEnd: Date?
        var currentRanges: [StatusStripRange] = []
        var currentBreakdown = AttentionDurationBreakdown()
        var totalBreakdown = AttentionDurationBreakdown()

        func resetCurrent() {
            currentStart = nil
            currentEnd = nil
            currentRanges = []
            currentBreakdown = AttentionDurationBreakdown()
        }

        func flushCurrent() {
            guard let start = currentStart,
                  let end = currentEnd,
                  end > start,
                  !currentRanges.isEmpty else {
                resetCurrent()
                return
            }
            result.append(WorkTimelineInterval(
                start: start,
                end: end,
                ranges: currentRanges,
                breakdown: currentBreakdown
            ))
            totalBreakdown.merge(currentBreakdown)
            resetCurrent()
        }

        func appendRange(_ range: StatusStripRange) {
            guard range.end > range.start else { return }
            if let lastIndex = currentRanges.indices.last {
                let last = currentRanges[lastIndex]
                if last.state == range.state,
                   range.start.timeIntervalSince(last.end) <= 1.5 {
                    currentRanges[lastIndex] = StatusStripRange(
                        start: last.start,
                        end: max(last.end, range.end),
                        state: last.state
                    )
                    return
                }
            }
            currentRanges.append(range)
        }

        for segment in orderedSegments {
            if segment.end <= windowStart { continue }
            if segment.start >= windowEnd { break }

            let clippedStart = max(segment.start, windowStart)
            let clippedEnd = min(segment.end, windowEnd)
            guard clippedEnd > clippedStart else { continue }

            guard Self.isWorkState(segment.state) else {
                if let previousEnd = currentEnd,
                   clippedEnd.timeIntervalSince(previousEnd) > maxSessionBridgeGap {
                    flushCurrent()
                }
                continue
            }

            if let previousEnd = currentEnd,
               clippedStart.timeIntervalSince(previousEnd) > maxSessionBridgeGap {
                flushCurrent()
            }

            if currentStart == nil {
                currentStart = clippedStart
            }
            currentEnd = max(currentEnd ?? clippedEnd, clippedEnd)

            let seconds = max(0, Int(clippedEnd.timeIntervalSince(clippedStart).rounded()))
            currentBreakdown.add(state: segment.state, seconds: seconds)
            appendRange(StatusStripRange(start: clippedStart, end: clippedEnd, state: segment.state))
        }
        flushCurrent()

        start = windowStart
        end = windowEnd
        intervals = result
        summary = totalBreakdown
    }

    private static func isWorkState(_ state: FocusPetCore.FocusState) -> Bool {
        switch state {
        case .focus, .distracted, .breakTime:
            return true
        case .away:
            return false
        }
    }
}

private struct FocusHistorySegmentsPanel: View {
    var snapshot: WorkTimelineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label("近24小时工作段", systemImage: "waveform.path.ecg")
                    .font(.headline.weight(.semibold))
                Spacer()
                StatusPill("\(snapshot.intervals.count) 段 · 仅工作段", symbol: "number")
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
                Text("最近 24 小时暂无工作时间。")
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
        .dashboardCard(14, tint: DashboardPalette.awayPurple)
        .dashboardPetAnchor(.historyWorkTimeline)
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 10)]
    }
}

private struct FocusSegmentDurationChart: View {
    var snapshot: WorkTimelineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkSessionOverviewStrip(snapshot: snapshot)
                .frame(height: 34)

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
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DashboardPalette.trackFill.opacity(0.34))

                ForEach(layoutRanges(total: total, width: proxy.size.width)) { range in
                    Capsule()
                        .fill(range.tint.gradient)
                        .frame(width: range.width, height: 18)
                        .offset(x: range.x)
                }
            }
            .overlay(alignment: .trailing) {
                Text("压缩工作段")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.62), in: Capsule())
                    .padding(.trailing, 5)
            }
        }
    }

    private func layoutRanges(total: Int, width: CGFloat) -> [CompressedWorkSessionRange] {
        var cursor: CGFloat = 0
        let gap: CGFloat = snapshot.intervals.count > 1 ? 4 : 0
        let usableWidth = max(0, width - gap * CGFloat(max(0, snapshot.intervals.count - 1)))
        return snapshot.intervals.map { interval in
            let segmentWidth = max(12, usableWidth * CGFloat(interval.totalSeconds) / CGFloat(max(1, total)))
            defer { cursor += segmentWidth + gap }
            return CompressedWorkSessionRange(
                x: cursor,
                width: segmentWidth,
                tint: interval.focusRatio >= 0.72 ? DashboardPalette.focusBlue : FocusPetCore.FocusState.distracted.timelineColor
            )
        }
    }
}

private struct CompressedWorkSessionRange: Identifiable {
    var x: CGFloat
    var width: CGFloat
    var tint: Color

    var id: String {
        "\(Int((x * 10).rounded()))-\(Int((width * 10).rounded()))"
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

            HStack(spacing: 8) {
                WorkSessionMetric(title: "专注", seconds: interval.breakdown.focusSeconds, tint: DashboardPalette.focusBlue)
                WorkSessionMetric(title: "走神", seconds: interval.breakdown.distractedSeconds, tint: FocusPetCore.FocusState.distracted.timelineColor)
                if interval.breakdown.breakSeconds > 0 {
                    WorkSessionMetric(title: "休息", seconds: interval.breakdown.breakSeconds, tint: DashboardPalette.restGreen)
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
        "专注 \(FocusPetFormatters.duration(interval.breakdown.focusSeconds)) · 走神 \(FocusPetFormatters.duration(interval.breakdown.distractedSeconds)) · 休息 \(FocusPetFormatters.duration(interval.breakdown.breakSeconds))"
    }

    private var span: TimeInterval {
        max(1, interval.end.timeIntervalSince(interval.start))
    }

    private func rangeOffset(_ range: StatusStripRange, width: CGFloat) -> CGFloat {
        width * CGFloat(max(0, range.start.timeIntervalSince(interval.start) / span))
    }

    private func rangeWidth(_ range: StatusStripRange, width: CGFloat) -> CGFloat {
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

    private func rangeOffset(_ range: StatusStripRange, interval: WorkTimelineInterval, width: CGFloat) -> CGFloat {
        let intervalSpan = max(1, interval.end.timeIntervalSince(interval.start))
        return width * CGFloat(max(0, range.start.timeIntervalSince(interval.start) / intervalSpan))
    }

    private func rangeWidth(_ range: StatusStripRange, interval: WorkTimelineInterval, width: CGFloat) -> CGFloat {
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
                tint: .blue
            )
            .onChange(of: model.settings.breakMinutes) { _, _ in model.saveSettings() }
            Button {
                model.toggleBreakFromPet()
            } label: {
                Label(model.activeBreakSession == nil ? "开始休息" : "结束休息", systemImage: model.activeBreakSession == nil ? "play.fill" : "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .liquidGlassButtonStyle(prominent: true)
            .tint(.blue)
        }
        .dashboardCard()
    }

    private var autoJudgeTile: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("自动判定", systemImage: "sparkles")
                .font(.headline)
            HStack(spacing: 10) {
                SessionStatPill(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: .green)
                SessionStatPill(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: .orange)
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
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        let spacing: CGFloat = 10
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: spacing)], spacing: spacing) {
                    JudgmentSettingsPanel()
                        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
                    ReminderSettingsPanel()
                        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
                    PrivacySettingsPanel()
                        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
                    RetentionSettingsPanel()
                        .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

private struct JudgmentSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("判定参数", systemImage: "slider.horizontal.3")
                .font(.headline)
            NumberStepperControl(
                title: "无输入走神",
                value: $model.settings.judgment.inputIdleDistractedSeconds,
                range: 30...900,
                suffix: "秒",
                tint: FocusPetCore.FocusState.distracted.timelineColor
            )
            .onChange(of: model.settings.judgment.inputIdleDistractedSeconds) { _, _ in model.saveSettings() }
            NumberStepperControl(
                title: "娱乐走神",
                value: $model.settings.judgment.entertainmentDistractedSeconds,
                range: 15...900,
                suffix: "秒",
                tint: .orange
            )
            .onChange(of: model.settings.judgment.entertainmentDistractedSeconds) { _, _ in model.saveSettings() }
            NumberStepperControl(
                title: "输入恢复专注",
                value: $model.settings.judgment.focusRecoverySeconds,
                range: 1...120,
                suffix: "秒",
                tint: FocusPetCore.FocusState.focus.timelineColor
            )
            .onChange(of: model.settings.judgment.focusRecoverySeconds) { _, _ in model.saveSettings() }
            NumberStepperControl(
                title: "暂离回填",
                value: $model.settings.judgment.idleAwaySeconds,
                range: 180...3600,
                suffix: "秒",
                tint: FocusPetCore.FocusState.away.timelineColor
            )
            .onChange(of: model.settings.judgment.idleAwaySeconds) { _, _ in model.saveSettings() }
        }
        .dashboardCard(12, tint: DashboardPalette.distractedPeach)
    }
}

private struct PetSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var selectedIntent: PetIntentKind = .quietCompanion
    @State private var previewSourceActionID: String?

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
                    .foregroundStyle(.red)
            }

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
                            model.settings.pet.hidden = !value
                            model.saveSettings()
                        }
                    ),
                    tint: .green
                )
                TogglePillButton(title: "动画", symbol: "sparkles", isOn: $model.settings.pet.animationEnabled, tint: .purple)
                    .onChange(of: model.settings.pet.animationEnabled) { _, _ in model.saveSettings() }
                TogglePillButton(title: "音效", symbol: "speaker.wave.2.fill", isOn: $model.settings.pet.audioEnabled, tint: .orange)
                    .onChange(of: model.settings.pet.audioEnabled) { _, _ in model.saveSettings() }
                TogglePillButton(title: "悬浮状态弹窗", symbol: "text.bubble.fill", isOn: $model.settings.pet.hoverStatusEnabled, tint: .blue)
                    .onChange(of: model.settings.pet.hoverStatusEnabled) { _, _ in model.saveSettings() }
            }

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
                ControlSliderRow(title: "大小", value: $model.settings.pet.size, range: 96...260, suffix: "px", tint: .purple)
                    .onChange(of: model.settings.pet.size) { _, _ in model.saveSettings() }
                ControlSliderRow(title: "透明度", value: $model.settings.pet.opacity, range: 0.35...1, suffix: "%", tint: .blue)
                    .onChange(of: model.settings.pet.opacity) { _, _ in model.saveSettings() }
            }
        }
        .dashboardCard(12, tint: DashboardPalette.restGreen)
        .dashboardPetAnchor(.settingsPetPanel)
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
                            HStack(spacing: 5) {
                                Image(systemName: intent.symbolName)
                                    .font(.caption2.weight(.semibold))
                                Text(intent.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? Color.accentColor : DashboardPalette.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? Color.white.opacity(0.62) : DashboardPalette.controlFill)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selected ? Color.accentColor.opacity(0.24) : DashboardPalette.border, lineWidth: 1)
                            }
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
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill")
                                    .font(.caption2.weight(.semibold))
                                Text(action.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? Color.accentColor : DashboardPalette.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected ? Color.white.opacity(0.62) : DashboardPalette.controlFill)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selected ? Color.accentColor.opacity(0.24) : DashboardPalette.border, lineWidth: 1)
                            }
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
        min(10, max(1, action?.fps ?? 8))
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.rowFill)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.innerStroke, lineWidth: 1)

            if let url = frameURL(at: date),
               let image = DashboardPreviewImageCache.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(18)
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
                .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
            }
        }
        .frame(height: 190)
    }

    private func frameURL(at date: Date) -> URL? {
        guard !frames.isEmpty else { return nil }
        let fps = previewFPS
        let index = Int(date.timeIntervalSinceReferenceDate * fps) % frames.count
        return frames[index]
    }
}

private struct ReminderSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("提醒设置", systemImage: "bell.badge.fill")
                .font(.headline)
            TogglePillButton(title: "桌宠气泡提醒", symbol: "bubble.left.and.bubble.right.fill", isOn: $model.settings.reminder.enablePetBubbles, tint: .blue)
                .onChange(of: model.settings.reminder.enablePetBubbles) { _, _ in model.saveSettings() }
            TogglePillButton(title: "系统通知", symbol: "bell.fill", isOn: $model.settings.reminder.enableSystemNotifications, tint: .orange)
                .onChange(of: model.settings.reminder.enableSystemNotifications) { _, _ in model.saveSettings() }
            HStack {
                Text(model.reminderPauseTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let pauseUntil = model.settings.reminder.pauseUntil, pauseUntil > Date() {
                    Button("恢复") { model.resumeReminders() }
                } else {
                    Button("暂停 30 分钟") { model.pauseReminders() }
                }
            }
        }
        .dashboardCard(12, tint: DashboardPalette.focusBlue)
    }
}

private struct PrivacySettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("隐私设置", systemImage: "lock.shield.fill")
                .font(.headline)
            TogglePillButton(title: "暂停所有记录", symbol: "pause.circle.fill", isOn: $model.settings.privacy.pauseActivityRecording, tint: .orange)
                .onChange(of: model.settings.privacy.pauseActivityRecording) { _, _ in model.saveSettings() }
            if model.settings.privacy.pauseActivityRecording {
                Text("记录已暂停")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            TogglePillButton(title: "只保存识别结果", symbol: "tag.fill", isOn: $model.settings.privacy.storeOnlyCategoryResult, tint: .blue)
                .onChange(of: model.settings.privacy.storeOnlyCategoryResult) { _, enabled in
                    if enabled {
                        model.settings.privacy.storeRawTitle = false
                    }
                    model.saveSettings()
                }
            TogglePillButton(title: "保存完整窗口标题", symbol: "text.alignleft", isOn: $model.settings.privacy.storeRawTitle, tint: .purple)
                .disabled(model.settings.privacy.storeOnlyCategoryResult)
                .opacity(model.settings.privacy.storeOnlyCategoryResult ? 0.45 : 1)
                .onChange(of: model.settings.privacy.storeRawTitle) { _, enabled in
                    if enabled {
                        model.settings.privacy.storeOnlyCategoryResult = false
                    }
                    model.saveSettings()
                }
        }
        .dashboardCard(12, tint: DashboardPalette.pauseGray)
    }
}

private struct RetentionSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("数据留存", systemImage: "externaldrive.fill")
                .font(.headline)
            NumberStepperControl(title: "状态片段", value: $model.settings.retention.stateRetentionDays, range: 1...365, suffix: "天", tint: .blue)
                .onChange(of: model.settings.retention.stateRetentionDays) { _, _ in model.saveSettings() }
            NumberStepperControl(title: "App 统计", value: $model.settings.retention.appUsageRetentionDays, range: 1...365, suffix: "天", tint: .green)
                .onChange(of: model.settings.retention.appUsageRetentionDays) { _, _ in model.saveSettings() }
            NumberStepperControl(title: "会话", value: $model.settings.retention.sessionRetentionDays, range: 1...365, suffix: "天", tint: .purple)
                .onChange(of: model.settings.retention.sessionRetentionDays) { _, _ in model.saveSettings() }
            HStack {
                Button("导出脱敏统计") { model.exportData(redacted: true) }
                Button("导出完整统计") { model.exportData(redacted: false) }
                Button("删除数据", role: .destructive) { model.deleteAllData() }
            }
            .liquidGlassButtonStyle()
            if let exportURL = model.exportURL {
                Text(exportURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .dashboardCard(12, tint: DashboardPalette.awayPurple)
    }
}

private struct AboutSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("关于", systemImage: "info.circle.fill")
                .font(.headline)
            Text("Focus Pet 使用前台 App、窗口标题识别、输入空闲和专注/休息会话判断状态。所有数据保存在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dashboardCard(12, tint: DashboardPalette.gold)
    }
}

private struct PetPackSelectionGrid: View {
    @EnvironmentObject private var model: FocusPetModel

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 188), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("资源包")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(model.availablePetPacks) { record in
                    PetPackSelectionCard(record: record)
                }
            }
        }
    }
}

private struct PetPackSelectionCard: View {
    @EnvironmentObject private var model: FocusPetModel
    var record: PetPackRecord

    private var isSelected: Bool {
        model.settings.pet.selectedPackID == record.id
    }

    var body: some View {
        Button {
            model.settings.pet.selectedPackID = record.id
            model.saveSettings()
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
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(8)
            .frame(minHeight: 54)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.05), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: Color {
        isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.025)
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
                    StatusPill(record.validation.isValid ? "可用" : "需修复", symbol: record.validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
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
                        .foregroundStyle(.red)
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
        case .work: .green
        case .entertainment: .orange
        case .ignore: .blue
        case .neutral: .secondary
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

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DashboardPalette.secondaryText)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(DashboardPalette.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DashboardPalette.controlFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardPalette.border, lineWidth: 1)
        }
    }
}

private struct LiquidGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        content
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
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DashboardPalette.cardFill)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint.opacity(0.82))
                            .frame(width: 4)
                            .padding(.vertical, 12)
                            .padding(.leading, 1)
                    }
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DashboardPalette.surfaceHighlight)
                            .opacity(0.24)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(tint.opacity(0.30), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DashboardPalette.innerStroke, lineWidth: 0.5)
                            .padding(1)
                    }
                    .shadow(color: DashboardPalette.shadow.opacity(0.08), radius: 2, x: 0, y: 1)
            }
            .liquidGlassSurface(cornerRadius: 12)
    }

    @ViewBuilder
    func liquidGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        modifier(LiquidGlassSurfaceModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
                .foregroundStyle(.white)
        } else {
            buttonStyle(.bordered)
        }
    }
}

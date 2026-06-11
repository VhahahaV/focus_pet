import AppKit
import FocusPetCore
import FocusPetResources
import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var model: FocusPetModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView(selection: $model.selectedTab) {
            TodayView()
                .tabItem { Label(DashboardTab.today.title, systemImage: DashboardTab.today.symbolName) }
                .tag(DashboardTab.today)

            DistributionView()
                .tabItem { Label(DashboardTab.distribution.title, systemImage: DashboardTab.distribution.symbolName) }
                .tag(DashboardTab.distribution)

            SessionsView()
                .tabItem { Label(DashboardTab.sessions.title, systemImage: DashboardTab.sessions.symbolName) }
                .tag(DashboardTab.sessions)

            RulesView()
                .tabItem { Label(DashboardTab.rules.title, systemImage: DashboardTab.rules.symbolName) }
                .tag(DashboardTab.rules)

            SettingsView()
                .tabItem { Label(DashboardTab.settings.title, systemImage: DashboardTab.settings.symbolName) }
                .tag(DashboardTab.settings)
        }
        .padding(18)
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
                MenuMetricChip(title: "走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), tint: .orange)
                MenuMetricChip(title: "休息", value: FocusPetFormatters.duration(model.summary.breakSeconds), tint: .blue)
                MenuMetricChip(title: "离开", value: FocusPetFormatters.duration(model.summary.awaySeconds), tint: .indigo)
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
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MenuStateStripBar: View {
    var total: Int
    var segments: [(seconds: Int, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary.opacity(0.45))
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

            if model.activeFocusSession == nil {
                MenuActionButton(title: "开始专注", symbol: "timer", tint: .green) {
                    model.startFocusSession(taskName: "专注任务", minutes: model.settings.focusTargetMinutes)
                }
            } else {
                MenuActionButton(title: "结束专注", symbol: "stop.fill", tint: .green) {
                    model.finishCurrentFocusSession()
                }
            }

            if model.activeBreakSession == nil {
                MenuActionButton(title: "开始休息", symbol: "cup.and.saucer.fill", tint: .blue) {
                    model.startBreak(minutes: model.settings.breakMinutes)
                }
            } else {
                MenuActionButton(title: "结束休息", symbol: "checkmark.circle.fill", tint: .blue) {
                    model.endCurrentBreak()
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
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TodayHeroPanel()
                DailyVisualOverviewPanel()
                FocusSessionCompactPanel()
                TimelinePanel()
                NudgePanel()
            }
        }
    }
}

struct TodayHeroPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var focusRatio: Double {
        guard model.summary.totalSeconds > 0 else { return 0 }
        return Double(model.summary.focusSeconds) / Double(model.summary.totalSeconds)
    }

    private var reasonText: String {
        let reasons = model.currentDecision.reason.map(\.title)
        return reasons.isEmpty ? "默认状态判断" : reasons.joined(separator: " · ")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                heroIdentity
                Divider().frame(height: 74)
                heroMetrics
                Spacer(minLength: 8)
                heroActions
            }

            VStack(alignment: .leading, spacing: 14) {
                heroIdentity
                heroMetrics
                heroActions
            }
        }
        .dashboardCard()
    }

    private var heroIdentity: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.currentDecision.state.timelineColor.opacity(0.14))
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(1, focusRatio))))
                    .stroke(model.currentDecision.state.timelineColor.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                Image(systemName: model.currentDecision.state.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(model.currentDecision.state.timelineColor)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.currentDecision.state.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(FocusPetFormatters.percentage(model.currentDecision.confidence))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.35), in: Capsule())
                }
                Text(model.currentSnapshot.appName)
                    .font(.headline)
                    .lineLimit(1)
                Text(reasonText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(minWidth: 260, alignment: .leading)
        }
    }

    private var heroMetrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 118), spacing: 8), count: 2), alignment: .leading, spacing: 8) {
            TodayHeroMetric(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: .green)
            TodayHeroMetric(title: "专注占比", value: FocusPetFormatters.percentage(focusRatio), symbol: "chart.pie.fill", tint: .blue)
            TodayHeroMetric(title: "空闲", value: FocusPetFormatters.duration(Int(model.currentSnapshot.idleSeconds)), symbol: "keyboard", tint: .orange)
            TodayHeroMetric(title: "切换", value: "\(model.currentSnapshot.switchCountLast5Min) 次", symbol: "arrow.triangle.2.circlepath", tint: .purple)
        }
        .frame(maxWidth: 330)
    }

    private var heroActions: some View {
        HStack(spacing: 9) {
            HeaderActionButton(title: "专注", symbol: "timer", tint: .green) {
                model.startFocusSession(taskName: "专注任务", minutes: model.settings.focusTargetMinutes)
            }
            HeaderActionButton(title: "休息", symbol: "cup.and.saucer.fill", tint: .blue) {
                model.startBreak(minutes: model.settings.breakMinutes)
            }
        }
    }
}

private struct TodayHeroMetric: View {
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
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minHeight: 42)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
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
        ZStack {
            Circle()
                .stroke(.quaternary.opacity(0.65), lineWidth: 22)

            ForEach(slices) { slice in
                Circle()
                    .trim(from: slice.start, to: slice.end)
                    .stroke(slice.state.timelineColor, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 3) {
                Text("\(focusPercent)%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("专注占比")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
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
                    .foregroundStyle(.secondary)
            }

            CompactMeter(ratio: ratio, tint: item.state.timelineColor, height: 8)
                .frame(maxWidth: 128)

            Text(FocusPetFormatters.duration(item.seconds))
                .font(.headline.monospacedDigit())
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FocusSessionCompactPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("当前会话", systemImage: "timer")
                .font(.headline)
            if let session = model.activeFocusSession {
                HStack {
                    VStack(alignment: .leading) {
                        Text(session.taskName)
                            .font(.title3.weight(.semibold))
                        Text("剩余 \(FocusPetFormatters.duration(session.remainingSeconds()))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("结束专注") {
                        model.finishCurrentFocusSession()
                    }
                }
            } else if let rest = model.activeBreakSession {
                HStack {
                    Text("休息中 · 剩余 \(FocusPetFormatters.duration(rest.remainingSeconds()))")
                    Spacer()
                    Button("结束休息") {
                        model.endCurrentBreak()
                    }
                }
            } else {
                Text("还没有正在进行的专注或休息。")
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }
}

struct TimelinePanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        let timeline = TodayTimelineSnapshot(segments: model.stateSegments)
        VStack(alignment: .leading, spacing: 10) {
            Label("今日时间线", systemImage: "list.bullet.rectangle")
                .font(.headline)
            if !timeline.hasData {
                Text("今天暂无状态记录。")
                    .foregroundStyle(.secondary)
            } else {
                StatusLineChart(points: timeline.points, hasData: timeline.hasData)
                    .frame(height: 170)
                    .padding(.bottom, 6)
                HStack(spacing: 12) {
                    ForEach(timeline.legend) { item in
                        Label {
                            Text(item.title)
                        } icon: {
                            Circle().fill(item.color).frame(width: 7, height: 7)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dashboardCard()
    }
}

private struct TodayTimelineSnapshot {
    var points: [StatusTimelinePoint]
    var hasData: Bool
    var legend: [StatusTimelineLegendItem]

    init(segments: [StateSegment]) {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = min(now, start.addingTimeInterval(86_400))
        let filtered = segments.filter { segment in
            segment.end > start && segment.start < end
        }

        let hasData = !filtered.isEmpty
        if !hasData {
            points = []
            legend = FocusPetCore.FocusState.allCases.map { state in
                StatusTimelineLegendItem(state: state, title: state.title, color: state.timelineColor)
            }
            self.hasData = false
            return
        }

        var durations: [FocusPetCore.FocusState: TimeInterval] = [:]
        var generatedPoints: [StatusTimelinePoint] = []
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
            if generatedPoints.last?.progress != startProgress || generatedPoints.last?.state != segment.state {
                generatedPoints.append(StatusTimelinePoint(progress: startProgress, state: segment.state))
            }
            generatedPoints.append(StatusTimelinePoint(progress: endProgress, state: segment.state))

            durations[segment.state, default: 0] += clippedEnd.timeIntervalSince(clippedStart)
        }

        points = generatedPoints
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
}

private struct StatusTimelinePoint: Identifiable {
    let id = UUID()
    let progress: Double
    let state: FocusPetCore.FocusState

    var level: Double {
        switch state {
        case .focus: 0.82
        case .distracted: 0.58
        case .breakTime: 0.36
        case .away: 0.18
        }
    }
}

private struct StatusTimelineLegendItem: Identifiable {
    let id = UUID()
    let state: FocusPetCore.FocusState
    let title: String
    let color: Color
}

private struct StatusLineChart: View {
    var points: [StatusTimelinePoint]
    var hasData: Bool
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack {
                    ChartGridLines()

                    if hasData {
                        TimelineAreaShape(points: points)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        FocusPetCore.FocusState.focus.timelineColor.opacity(0.16),
                                        FocusPetCore.FocusState.breakTime.timelineColor.opacity(0.09),
                                        FocusPetCore.FocusState.away.timelineColor.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(reveal ? 1 : 0)

                        TimelineLineShape(points: points)
                            .trim(from: 0, to: reveal ? 1 : 0)
                            .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                            .blur(radius: 3)

                        TimelineLineShape(points: points)
                        .trim(from: 0, to: reveal ? 1 : 0)
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
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: .primary.opacity(0.1), radius: 5, x: 0, y: 2)

                        ForEach(points) { point in
                            ZStack {
                                Circle()
                                    .fill(.background.opacity(0.8))
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(point.state.timelineColor)
                                    .frame(width: 5, height: 5)
                            }
                                .position(position(for: point, in: proxy.size))
                                .opacity(reveal ? 1 : 0)
                        }
                    } else {
                        Text("暂无今日状态点。")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 0.55)) {
                        reveal = true
                    }
                }
                .onChange(of: points.map(\.id)) { _, _ in
                    reveal = false
                    withAnimation(.easeOut(duration: 0.55)) {
                        reveal = true
                    }
                }
                .drawingGroup()
            }
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay(
            HStack(spacing: 12) {
                TimelineTimeChip("00:00")
                Spacer()
                TimelineTimeChip("12:00")
                Spacer()
                TimelineTimeChip("23:59")
            }
            .padding(10),
            alignment: .bottomLeading
        )
    }

    private func position(for point: StatusTimelinePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * CGFloat(point.progress), y: size.height * (1 - point.level))
    }
}

private struct TimelineLineShape: Shape {
    var points: [StatusTimelinePoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: position(for: first, in: rect.size))
        for point in points.dropFirst() {
            path.addLine(to: position(for: point, in: rect.size))
        }
        return path
    }

    private func position(for point: StatusTimelinePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * CGFloat(point.progress), y: size.height * (1 - point.level))
    }
}

private struct TimelineAreaShape: Shape {
    var points: [StatusTimelinePoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        let firstPosition = position(for: first, in: rect.size)
        let lastPosition = position(for: last, in: rect.size)
        path.move(to: CGPoint(x: firstPosition.x, y: rect.maxY))
        path.addLine(to: firstPosition)
        for point in points.dropFirst() {
            path.addLine(to: position(for: point, in: rect.size))
        }
        path.addLine(to: CGPoint(x: lastPosition.x, y: rect.maxY))
        path.closeSubpath()
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
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
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
            .stroke(.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }
    }
}

private extension FocusPetCore.FocusState {
    var timelineColor: Color {
        switch self {
        case .focus: .green
        case .distracted: .orange
        case .breakTime: .blue
        case .away: .indigo
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
        case .work: .green
        case .entertainment: .orange
        case .ignore: .blue
        case .neutral: .secondary
        }
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
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        selection = option.value
                    }
                } label: {
                    HStack(spacing: compact ? 4 : 6) {
                        Image(systemName: option.symbol)
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        Text(option.title)
                            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(selected ? option.tint : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.vertical, compact ? 6 : 8)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(.regularMaterial)
                                .matchedGeometryEffect(id: "selected", in: namespace)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(option.tint.opacity(0.28), lineWidth: 1)
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
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private func activityCategoryOptions() -> [SlidingSegmentOption<ActivityCategory>] {
    ActivityCategory.allCases.map { category in
        SlidingSegmentOption(
            value: category,
            title: category.title,
            symbol: category.symbolName,
            tint: category.tint
        )
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

private func petActionPreviewOptions() -> [SlidingSegmentOption<PetAction>] {
    PetAction.allCases.map { action in
        SlidingSegmentOption(
            value: action,
            title: action.title,
            symbol: action.symbolName,
            tint: action.tint
        )
    }
}

private extension PetAction {
    var symbolName: String {
        switch self {
        case .idle: "circle.dotted"
        case .blink: "eye"
        case .breath: "wind"
        case .sleep: "moon.zzz.fill"
        case .wake: "sun.max.fill"
        case .focusStart: "timer"
        case .focusStable: "checkmark.circle.fill"
        case .stretch: "figure.flexibility"
        case .distractedLook: "eye.trianglebadge.exclamationmark"
        case .nudgeGentle: "bell.fill"
        case .nudgeStrong: "bell.badge.fill"
        case .breakRelax: "cup.and.saucer.fill"
        case .breakEnd: "arrow.clockwise.circle.fill"
        case .welcomeBack: "hand.wave.fill"
        case .dragged: "hand.draw.fill"
        case .landing: "arrow.down.to.line"
        }
    }

    var tint: Color {
        switch self {
        case .focusStart, .focusStable: .green
        case .distractedLook, .nudgeGentle, .nudgeStrong: .orange
        case .breakRelax, .breakEnd: .blue
        case .sleep, .wake, .welcomeBack: .indigo
        case .dragged, .landing: .purple
        case .idle, .blink, .breath, .stretch: .secondary
        }
    }
}

private extension StateReason {
    var title: String {
        switch self {
        case .idleAway: "空闲暂离"
        case .longAway: "长时间离开"
        case .activeBreak: "休息中"
        case .activeFocusSession: "专注会话"
        case .workCategory: "工作分类"
        case .entertainmentStable: "娱乐稳定"
        case .entertainmentGrace: "娱乐缓冲"
        case .frequentSwitching: "频繁切换"
        case .ignoredActivity: "忽略活动"
        case .previousStateHeld: "保持状态"
        case .neutralDefault: "默认判断"
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle("状态占比")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 180), spacing: 12), count: 4), spacing: 12) {
                    RatioTile(state: FocusPetCore.FocusState.focus, seconds: model.summary.focusSeconds, total: model.summary.totalSeconds)
                    RatioTile(state: FocusPetCore.FocusState.distracted, seconds: model.summary.distractedSeconds, total: model.summary.totalSeconds)
                    RatioTile(state: FocusPetCore.FocusState.breakTime, seconds: model.summary.breakSeconds, total: model.summary.totalSeconds)
                    RatioTile(state: FocusPetCore.FocusState.away, seconds: model.summary.awaySeconds, total: model.summary.totalSeconds)
                }
                SectionTitle("分类统计")
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
            ForEach(ActivityCategory.allCases) { category in
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
                    .background(.quaternary.opacity(0.35), in: Capsule())
            }
            .foregroundStyle(seconds > 0 ? .primary : .secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
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
                    .fill(.quaternary.opacity(0.45))
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
                .fill(.quaternary.opacity(0.45))
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
                Image(systemName: item.category.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.category.tint)
                    .frame(width: 24, height: 24)
                    .background(item.category.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
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
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
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
    @State private var taskName = "专注任务"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("开始专注", systemImage: "timer")
                        .font(.headline)
                    TextField("任务名称", text: $taskName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Stepper("目标 \(model.settings.focusTargetMinutes) 分钟", value: $model.settings.focusTargetMinutes, in: 1...180)
                            .onChange(of: model.settings.focusTargetMinutes) { _, _ in model.saveSettings() }
                        Toggle("完成后自动休息", isOn: $model.settings.autoStartBreak)
                            .onChange(of: model.settings.autoStartBreak) { _, _ in model.saveSettings() }
                        Button("开始") {
                            model.startFocusSession(taskName: taskName, minutes: model.settings.focusTargetMinutes)
                        }
                    }
                }
                .dashboardCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("休息计时", systemImage: "cup.and.saucer.fill")
                        .font(.headline)
                    HStack {
                        Stepper("休息 \(model.settings.breakMinutes) 分钟", value: $model.settings.breakMinutes, in: 1...60)
                            .onChange(of: model.settings.breakMinutes) { _, _ in model.saveSettings() }
                        Button("开始休息") {
                            model.startBreak(minutes: model.settings.breakMinutes)
                        }
                    }
                }
                .dashboardCard()

                VStack(alignment: .leading, spacing: 10) {
                    Label("历史会话", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    if model.focusSessions.isEmpty {
                        Text("还没有专注会话。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.focusSessions.reversed()) { session in
                            FocusSessionRow(session: session)
                        }
                    }
                }
                .dashboardCard()
            }
        }
    }
}

struct FocusSessionRow: View {
    var session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.taskName)
                        .font(.headline)
                    Text("\(FocusPetFormatters.clock(session.start)) · \(statusTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(FocusPetFormatters.percentage(session.completionRatio))
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: session.completionRatio)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 8), count: 4), spacing: 8) {
                SessionStatPill(title: "有效专注", value: FocusPetFormatters.duration(session.effectiveFocusSeconds), symbol: "checkmark.circle.fill")
                SessionStatPill(title: "主用 App", value: session.mainAppName ?? "暂无", symbol: "macwindow")
                SessionStatPill(title: "打断", value: "\(session.interruptionCount) 次", symbol: "exclamationmark.triangle.fill")
                SessionStatPill(title: "切换", value: "\(session.switchCount) 次", symbol: "arrow.triangle.2.circlepath")
            }

            Text("走神 \(FocusPetFormatters.duration(session.distractedSeconds)) · 离开 \(FocusPetFormatters.duration(session.awaySeconds)) · 目标 \(FocusPetFormatters.duration(session.targetDurationSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var statusTitle: String {
        switch session.status {
        case .active: "进行中"
        case .completed: "完成"
        case .cancelled: "已取消"
        }
    }
}

struct SessionStatPill: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
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
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RulesView: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var selectedRuleCategory: ActivityCategory = .work

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RulesHeroPanel(selectedCategory: $selectedRuleCategory)
                AppRuleSelectionPanel(selectedCategory: selectedRuleCategory)
                KeywordRuleSelectionPanel(selectedCategory: selectedRuleCategory)
                OtherRulesPanel()
            }
        }
    }
}

private struct RulesHeroPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    @Binding var selectedCategory: ActivityCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("规则")
                        .font(.title2.weight(.semibold))
                    Text("像系统设置一样为 App 和关键词选择分类。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill("\(model.rules.count) 条规则", symbol: "number")
            }

            SlidingSegmentedPicker(
                options: activityCategoryOptions(),
                selection: $selectedCategory
            )
        }
        .dashboardCard()
    }
}

private struct RuleChoice: Identifiable, Hashable {
    var title: String
    var subtitle: String
    var matchKind: RuleMatchKind
    var defaultCategory: ActivityCategory
    var bundleID: String?
    var seconds: Int

    var id: String { "\(matchKind.rawValue)-\(title.lowercased())" }
}

private struct AppRuleSelectionPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    var selectedCategory: ActivityCategory

    private var choices: [RuleChoice] {
        var result: [String: RuleChoice] = [:]

        func add(_ choice: RuleChoice) {
            let key = choice.title.lowercased()
            if let existing = result[key] {
                result[key] = RuleChoice(
                    title: existing.title,
                    subtitle: choice.seconds > existing.seconds ? choice.subtitle : existing.subtitle,
                    matchKind: existing.matchKind,
                    defaultCategory: existing.defaultCategory,
                    bundleID: existing.bundleID ?? choice.bundleID,
                    seconds: max(existing.seconds, choice.seconds)
                )
            } else {
                result[key] = choice
            }
        }

        for item in model.summary.appUsage.prefix(12) {
            add(RuleChoice(
                title: item.appName,
                subtitle: item.seconds > 0 ? "今日 \(FocusPetFormatters.duration(item.seconds))" : item.category.title,
                matchKind: .appName,
                defaultCategory: item.category,
                bundleID: item.bundleID,
                seconds: item.seconds
            ))
        }

        for rule in model.rules where rule.matchKind == .appName {
            add(RuleChoice(
                title: rule.pattern,
                subtitle: "已配置为\(rule.category.title)",
                matchKind: .appName,
                defaultCategory: rule.category,
                bundleID: nil,
                seconds: 0
            ))
        }

        defaultAppChoices.forEach(add)

        return result.values.sorted { lhs, rhs in
            let lhsCategory = model.categoryForRule(pattern: lhs.title, matchKind: .appName) ?? lhs.defaultCategory
            let rhsCategory = model.categoryForRule(pattern: rhs.title, matchKind: .appName) ?? rhs.defaultCategory
            if lhsCategory == selectedCategory && rhsCategory != selectedCategory { return true }
            if lhsCategory != selectedCategory && rhsCategory == selectedCategory { return false }
            if lhs.seconds == rhs.seconds {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.seconds > rhs.seconds
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("应用分类", systemImage: "app.badge.fill")
                    .font(.headline)
                Spacer()
                StatusPill("最近 + 默认", symbol: "sparkles")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 10)], spacing: 10) {
                ForEach(choices) { choice in
                    RuleChoiceRow(choice: choice, selectedCategory: selectedCategory)
                }
            }
        }
        .dashboardCard()
    }
}

private struct KeywordRuleSelectionPanel: View {
    var selectedCategory: ActivityCategory

    private var choices: [RuleChoice] {
        defaultKeywordChoices.sorted { lhs, rhs in
            if lhs.defaultCategory == selectedCategory && rhs.defaultCategory != selectedCategory { return true }
            if lhs.defaultCategory != selectedCategory && rhs.defaultCategory == selectedCategory { return false }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("窗口关键词", systemImage: "text.magnifyingglass")
                    .font(.headline)
                Spacer()
                StatusPill("点选即可生效", symbol: "hand.tap.fill")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(choices) { choice in
                    RuleChoiceRow(choice: choice, selectedCategory: selectedCategory)
                }
            }
        }
        .dashboardCard()
    }
}

private struct RuleChoiceRow: View {
    @EnvironmentObject private var model: FocusPetModel
    var choice: RuleChoice
    var selectedCategory: ActivityCategory

    private var effectiveCategory: ActivityCategory {
        model.categoryForRule(pattern: choice.title, matchKind: choice.matchKind) ?? choice.defaultCategory
    }

    var body: some View {
        HStack(spacing: 12) {
            RuleChoiceIcon(choice: choice, category: effectiveCategory)

            VStack(alignment: .leading, spacing: 4) {
                Text(choice.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(choice.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)

            SlidingSegmentedPicker(
                options: activityCategoryOptions(),
                selection: Binding(
                    get: { effectiveCategory },
                    set: { category in
                        model.setRule(pattern: choice.title, matchKind: choice.matchKind, category: category)
                    }
                ),
                compact: true
            )
            .frame(width: choice.matchKind == .appName ? 224 : 214)
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(effectiveCategory == selectedCategory ? effectiveCategory.tint.opacity(0.35) : .primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var rowBackground: Color {
        effectiveCategory == selectedCategory ? effectiveCategory.tint.opacity(0.08) : .primary.opacity(0.025)
    }
}

private struct RuleChoiceIcon: View {
    var choice: RuleChoice
    var category: ActivityCategory

    var body: some View {
        ZStack {
            if choice.matchKind == .appName,
               let bundleID = choice.bundleID,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: choice.matchKind == .appName ? "app.fill" : "textformat")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(category.tint)
            }
        }
        .frame(width: 38, height: 38)
        .background(category.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }
}

private let defaultAppChoices: [RuleChoice] = [
    RuleChoice(title: "Cursor", subtitle: "代码编辑", matchKind: .appName, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "Xcode", subtitle: "开发工具", matchKind: .appName, defaultCategory: .work, bundleID: "com.apple.dt.Xcode", seconds: 0),
    RuleChoice(title: "Terminal", subtitle: "终端", matchKind: .appName, defaultCategory: .work, bundleID: "com.apple.Terminal", seconds: 0),
    RuleChoice(title: "iTerm", subtitle: "终端", matchKind: .appName, defaultCategory: .work, bundleID: "com.googlecode.iterm2", seconds: 0),
    RuleChoice(title: "Notion", subtitle: "文档与计划", matchKind: .appName, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "Obsidian", subtitle: "知识库", matchKind: .appName, defaultCategory: .work, bundleID: "md.obsidian", seconds: 0),
    RuleChoice(title: "Figma", subtitle: "设计", matchKind: .appName, defaultCategory: .work, bundleID: "com.figma.Desktop", seconds: 0),
    RuleChoice(title: "Safari", subtitle: "浏览器", matchKind: .appName, defaultCategory: .neutral, bundleID: "com.apple.Safari", seconds: 0),
    RuleChoice(title: "Google Chrome", subtitle: "浏览器", matchKind: .appName, defaultCategory: .neutral, bundleID: "com.google.Chrome", seconds: 0),
    RuleChoice(title: "Microsoft Edge", subtitle: "浏览器", matchKind: .appName, defaultCategory: .neutral, bundleID: "com.microsoft.edgemac", seconds: 0),
    RuleChoice(title: "Steam", subtitle: "游戏", matchKind: .appName, defaultCategory: .entertainment, bundleID: "com.valvesoftware.steam", seconds: 0),
    RuleChoice(title: "Bilibili", subtitle: "视频", matchKind: .appName, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "WeChat", subtitle: "通讯", matchKind: .appName, defaultCategory: .neutral, bundleID: "com.tencent.xinWeChat", seconds: 0),
    RuleChoice(title: "Finder", subtitle: "系统", matchKind: .appName, defaultCategory: .ignore, bundleID: "com.apple.finder", seconds: 0),
    RuleChoice(title: "System Settings", subtitle: "系统", matchKind: .appName, defaultCategory: .ignore, bundleID: "com.apple.systempreferences", seconds: 0),
    RuleChoice(title: "Activity Monitor", subtitle: "系统", matchKind: .appName, defaultCategory: .ignore, bundleID: "com.apple.ActivityMonitor", seconds: 0),
    RuleChoice(title: "1Password", subtitle: "密码管理", matchKind: .appName, defaultCategory: .ignore, bundleID: nil, seconds: 0)
]

private let defaultKeywordChoices: [RuleChoice] = [
    RuleChoice(title: "paper", subtitle: "论文 / 阅读", matchKind: .windowTitle, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "论文", subtitle: "论文 / 阅读", matchKind: .windowTitle, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "draft", subtitle: "写作", matchKind: .windowTitle, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "report", subtitle: "报告", matchKind: .windowTitle, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "project", subtitle: "项目", matchKind: .windowTitle, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "GitHub", subtitle: "代码协作", matchKind: .windowTitle, defaultCategory: .work, bundleID: nil, seconds: 0),
    RuleChoice(title: "YouTube", subtitle: "视频", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "Bilibili", subtitle: "视频", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "Netflix", subtitle: "视频", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "Twitch", subtitle: "直播", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "小红书", subtitle: "内容流", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "抖音", subtitle: "短视频", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "游戏", subtitle: "娱乐", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0),
    RuleChoice(title: "直播", subtitle: "娱乐", matchKind: .windowTitle, defaultCategory: .entertainment, bundleID: nil, seconds: 0)
]

struct OtherRulesPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var otherRules: [ClassificationRule] {
        model.rules
            .filter { rule in
                rule.matchKind == .bundleID
            }
            .sorted { lhs, rhs in
                if lhs.category.rawValue == rhs.category.rawValue {
                    return lhs.pattern.localizedCaseInsensitiveCompare(rhs.pattern) == .orderedAscending
                }
                return lhs.category.rawValue < rhs.category.rawValue
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("其他规则", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text("\(otherRules.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.4), in: Capsule())
            }

            if otherRules.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(otherRules) { rule in
                    HStack(spacing: 8) {
                        Text(rule.pattern)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(rule.category.title) · \(rule.matchKind.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            model.deleteRule(rule)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .dashboardCard()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var previewAction: PetAction = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("桌宠设置", systemImage: "pawprint.fill")
                        .font(.headline)
                    PetPackSelectionGrid()
                    HStack {
                        Button {
                            model.chooseAndImportPetPack()
                        } label: {
                            Label("导入资源包", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            model.refreshPetPacks()
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("动作预览")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    model.previewPetAction(previewAction)
                                } label: {
                                    Label("预览", systemImage: "play.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                SlidingSegmentedPicker(
                                    options: petActionPreviewOptions(),
                                    selection: $previewAction,
                                    compact: true
                                )
                                .frame(minWidth: CGFloat(PetAction.allCases.count) * 78)
                            }
                        }
                        PetPackCoverageMatrix(record: record)
                    }
                    Toggle("显示桌宠", isOn: Binding(
                        get: { !model.settings.pet.hidden },
                        set: { value in
                            model.settings.pet.hidden = !value
                            model.saveSettings()
                        }
                    ))
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
                    if model.settings.pet.placement == .custom,
                       let x = model.settings.pet.customOriginX,
                       let y = model.settings.pet.customOriginY {
                        Text("自定义位置：x \(Int(x)), y \(Int(y))。拖动桌宠可更新。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.settings.pet.size, in: 96...260) {
                        Text("大小")
                    }
                    .onChange(of: model.settings.pet.size) { _, _ in model.saveSettings() }
                    Slider(value: $model.settings.pet.opacity, in: 0.35...1) {
                        Text("透明度")
                    }
                    .onChange(of: model.settings.pet.opacity) { _, _ in model.saveSettings() }
                    Toggle("动画", isOn: $model.settings.pet.animationEnabled)
                        .onChange(of: model.settings.pet.animationEnabled) { _, _ in model.saveSettings() }
                    Toggle("指针悬浮状态弹窗", isOn: $model.settings.pet.hoverStatusEnabled)
                        .onChange(of: model.settings.pet.hoverStatusEnabled) { _, _ in model.saveSettings() }
                }
                .dashboardCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("提醒设置", systemImage: "bell.badge.fill")
                        .font(.headline)
                    Toggle("桌宠气泡提醒", isOn: $model.settings.reminder.enablePetBubbles)
                        .onChange(of: model.settings.reminder.enablePetBubbles) { _, _ in model.saveSettings() }
                    Toggle("系统通知", isOn: $model.settings.reminder.enableSystemNotifications)
                        .onChange(of: model.settings.reminder.enableSystemNotifications) { _, _ in model.saveSettings() }
                    HStack {
                        if let pauseUntil = model.settings.reminder.pauseUntil, pauseUntil > Date() {
                            Text(model.reminderPauseTitle)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复提醒") {
                                model.resumeReminders()
                            }
                        } else {
                            Text("提醒未暂停")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("暂停 30 分钟") {
                                model.pauseReminders()
                            }
                        }
                    }
                }
                .dashboardCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("隐私设置", systemImage: "lock.shield.fill")
                        .font(.headline)
                    Toggle("暂停所有记录", isOn: $model.settings.privacy.pauseActivityRecording)
                        .onChange(of: model.settings.privacy.pauseActivityRecording) { _, _ in model.saveSettings() }
                    Text(model.recordingStatusTitle)
                        .font(.caption)
                        .foregroundStyle(model.settings.privacy.pauseActivityRecording ? .orange : .secondary)
                    Toggle("只保存分类结果", isOn: $model.settings.privacy.storeOnlyCategoryResult)
                        .onChange(of: model.settings.privacy.storeOnlyCategoryResult) { _, enabled in
                            if enabled {
                                model.settings.privacy.storeRawTitle = false
                            }
                            model.saveSettings()
                        }
                    Toggle("保存完整窗口标题", isOn: $model.settings.privacy.storeRawTitle)
                        .disabled(model.settings.privacy.storeOnlyCategoryResult)
                        .onChange(of: model.settings.privacy.storeRawTitle) { _, enabled in
                            if enabled {
                                model.settings.privacy.storeOnlyCategoryResult = false
                            }
                            model.saveSettings()
                        }
                    Text("默认只保存 App、分类、状态和时间，并持久化脱敏标题线索。开启“只保存分类结果”后不会保存标题摘要、脱敏标题或完整标题。")
                        .foregroundStyle(.secondary)
                }
                .dashboardCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("数据留存", systemImage: "externaldrive.fill")
                        .font(.headline)
                    Stepper("状态片段 \(model.settings.retention.stateRetentionDays) 天", value: $model.settings.retention.stateRetentionDays, in: 1...365)
                        .onChange(of: model.settings.retention.stateRetentionDays) { _, _ in model.saveSettings() }
                    Stepper("App 统计 \(model.settings.retention.appUsageRetentionDays) 天", value: $model.settings.retention.appUsageRetentionDays, in: 1...365)
                        .onChange(of: model.settings.retention.appUsageRetentionDays) { _, _ in model.saveSettings() }
                    Stepper("会话 \(model.settings.retention.sessionRetentionDays) 天", value: $model.settings.retention.sessionRetentionDays, in: 1...365)
                        .onChange(of: model.settings.retention.sessionRetentionDays) { _, _ in model.saveSettings() }
                    HStack {
                        Button("导出脱敏统计") {
                            model.exportData(redacted: true)
                        }
                        Button("导出完整本地统计") {
                            model.exportData(redacted: false)
                        }
                        Button("删除所有本地数据", role: .destructive) {
                            model.deleteAllData()
                        }
                    }
                    if let exportURL = model.exportURL {
                        Text(exportURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .dashboardCard()

                VStack(alignment: .leading, spacing: 8) {
                    Label("关于", systemImage: "info.circle.fill")
                        .font(.headline)
                    Text("Focus Pet 使用前台 App、窗口标题分类、输入空闲和专注/休息会话判断状态。所有数据保存在本机。")
                        .foregroundStyle(.secondary)
                }
                .dashboardCard()
            }
        }
        .onAppear {
            model.refreshPetPacks()
        }
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

private struct PetPackThumbnail: View {
    var record: PetPackRecord

    var body: some View {
        ZStack {
            if let url = record.previewURL, let image = NSImage(contentsOf: url) {
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
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PetPackSummaryView: View {
    var record: PetPackRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = record.previewURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 72)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.pack.name)
                        .font(.headline)
                    StatusPill(record.originTitle, symbol: record.isBundled ? "shippingbox.fill" : "folder.fill")
                    StatusPill(record.validation.isValid ? "可用" : "需修复", symbol: record.validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                Text("作者 \(record.pack.author) · \(record.pack.style)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("授权 \(record.pack.license.isEmpty ? "未填写" : record.pack.license) · 分发 \(record.pack.distribution.isEmpty ? "未填写" : record.pack.distribution)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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

struct PetPackCoverageMatrix: View {
    var record: PetPackRecord

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 156), spacing: 8)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("动作覆盖", systemImage: "square.grid.3x3.fill")
                .font(.headline)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(record.coverage()) { item in
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: item.status))
                            .foregroundStyle(color(for: item.status))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.action.title)
                                .font(.caption.weight(.medium))
                            Text(detail(for: item))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func detail(for item: PetActionCoverage) -> String {
        switch item.status {
        case .native:
            "\(item.frameCount) 帧"
        case .fallback:
            "\(item.resolvedAction?.title ?? "Idle") · \(item.frameCount) 帧"
        case .missing:
            "无可用动画"
        }
    }

    private func symbol(for status: PetActionCoverageStatus) -> String {
        switch status {
        case .native: "checkmark.circle.fill"
        case .fallback: "arrow.triangle.branch"
        case .missing: "xmark.circle.fill"
        }
    }

    private func color(for status: PetActionCoverageStatus) -> Color {
        switch status {
        case .native: .green
        case .fallback: .orange
        case .missing: .red
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
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

extension View {
    func dashboardCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

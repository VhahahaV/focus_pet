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
                MenuMetricChip(title: "暂离", value: FocusPetFormatters.duration(model.summary.awaySeconds), tint: .indigo)
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
                MenuActionButton(title: "专注 \(model.settings.focusTargetMinutes) 分钟", symbol: "timer", tint: .green) {
                    model.startFocusSession(taskName: "专注任务", minutes: model.settings.focusTargetMinutes)
                }
            } else {
                MenuActionButton(title: "结束专注", symbol: "stop.fill", tint: .green) {
                    model.finishCurrentFocusSession()
                }
            }

            if model.activeBreakSession == nil {
                MenuActionButton(title: "休息 \(model.settings.breakMinutes) 分钟", symbol: "cup.and.saucer.fill", tint: .blue) {
                    model.toggleBreakFromPet()
                }
            } else {
                MenuActionButton(title: "结束休息", symbol: "checkmark.circle.fill", tint: .blue) {
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
                TimelinePanel()
                TodayAppUsageBarChartPanel()
                NudgePanel()
            }
        }
    }
}

struct TodayHeroPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var stateItems: [StateDurationItem] {
        [
            StateDurationItem(state: .focus, seconds: model.summary.focusSeconds),
            StateDurationItem(state: .distracted, seconds: model.summary.distractedSeconds),
            StateDurationItem(state: .breakTime, seconds: model.summary.breakSeconds),
            StateDurationItem(state: .away, seconds: model.summary.awaySeconds)
        ]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                heroIdentity
                stateDurationGrid
                    .frame(maxWidth: .infinity, alignment: .leading)
                BreakDurationControl()
                    .frame(width: 260)
            }

            VStack(alignment: .leading, spacing: 14) {
                heroIdentity
                stateDurationGrid
                BreakDurationControl()
            }
        }
        .dashboardCard()
    }

    private var heroIdentity: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(model.currentDecision.state.timelineColor.opacity(0.14))
                Image(systemName: model.currentDecision.state.symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(model.currentDecision.state.timelineColor)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.currentDecision.state.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
                Text(model.currentSnapshot.appName)
                    .font(.headline)
                    .lineLimit(1)
                Text("今日状态")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 210, alignment: .leading)
        }
    }

    private var stateDurationGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(stateItems) { item in
                TodayHeroMetric(
                    title: item.state.title,
                    value: FocusPetFormatters.duration(item.seconds),
                    symbol: item.state.symbolName,
                    tint: item.state.timelineColor
                )
            }
        }
        .frame(maxWidth: .infinity)
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
        .frame(minHeight: 48)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BreakDurationControl: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: model.activeBreakSession == nil ? "cup.and.saucer.fill" : "timer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 30, height: 30)
                        .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.activeBreakSession == nil ? "休息计时" : "正在休息")
                            .font(.caption.weight(.semibold))
                        Text(statusSubtitle(at: context.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(primaryTimeText(at: context.date))
                        .font(.title3.monospacedDigit().weight(.semibold))
                }

                if let progress = activeBreakProgress(at: context.date) {
                    CompactMeter(ratio: progress, tint: .blue, height: 8)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: breakMinutesBinding, in: 1...30, step: 1)
                            .tint(.blue)
                        HStack {
                            Text("1")
                            Spacer()
                            Text("15")
                            Spacer()
                            Text("30 分钟")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                Button {
                    model.toggleBreakFromPet()
                } label: {
                    Label(model.activeBreakSession == nil ? "开始休息" : "结束休息", systemImage: model.activeBreakSession == nil ? "play.fill" : "stop.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.activeBreakSession == nil ? .blue : .orange)
            }
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue.opacity(0.16), lineWidth: 1)
            }
        }
    }

    private var breakMinutesBinding: Binding<Double> {
        Binding(
            get: { Double(model.settings.breakMinutes) },
            set: { value in
                let next = max(1, min(30, Int(value.rounded())))
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

    private func statusSubtitle(at date: Date) -> String {
        guard let rest = model.activeBreakSession else {
            return "滑动调整 1-30 分钟"
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
                    RestStatusTile(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: .orange)
                    restAction
                }
                VStack(spacing: 10) {
                    RestStatusTile(title: "当前状态", value: model.currentDecision.state.title, symbol: model.currentDecision.state.symbolName, tint: model.currentDecision.state.timelineColor)
                    RestStatusTile(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: .green)
                    RestStatusTile(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: .orange)
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
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("休息后自动恢复判断")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .padding(12)
            .foregroundStyle(.white)
            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 10))
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
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TimelinePanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        let timeline = StatusStripSnapshot(segments: model.stateSegments, secondsBack: 21_600)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("最近 6 小时", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                StatusPill("状态区间", symbol: "square.split.2x1.fill")
            }
            if !timeline.hasData {
                Text("最近 6 小时暂无状态记录。")
                    .foregroundStyle(.secondary)
            } else {
                StateSegmentStrip(
                    ranges: timeline.ranges,
                    start: timeline.start,
                    end: timeline.end,
                    height: 22
                )
                .frame(height: 38)
                HStack {
                    TimelineTimeChip(timeline.timeLabels.first ?? "")
                    Spacer()
                    TimelineTimeChip(timeline.timeLabels.dropFirst().first ?? "")
                    Spacer()
                    TimelineTimeChip(timeline.timeLabels.last ?? "")
                }
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

        let filtered = segments.filter { $0.end > windowStart && $0.start < windowEnd }
        self.hasData = !filtered.isEmpty
        var durations: [FocusPetCore.FocusState: TimeInterval] = [:]
        self.ranges = filtered
            .sorted { $0.start < $1.start }
            .compactMap { segment in
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
    let id = UUID()
    var start: Date
    var end: Date
    var state: FocusPetCore.FocusState
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
                    .fill(.secondary.opacity(0.13))
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
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
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

private struct StatusTimelineRange: Identifiable {
    let id = UUID()
    let startProgress: Double
    let endProgress: Double
    let state: FocusPetCore.FocusState
}

private struct StatusTimelineLegendItem: Identifiable {
    let id = UUID()
    let state: FocusPetCore.FocusState
    let title: String
    let color: Color
}

private struct StatusLineChart: View {
    var points: [StatusTimelinePoint]
    var ranges: [StatusTimelineRange]
    var hasData: Bool
    var timeLabels: [String]
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack {
                    TimelineStateBands(ranges: ranges)
                    ChartGridLines()

                    if hasData {
                        SmoothTimelineLineShape(points: points)
                            .trim(from: 0, to: reveal ? 1 : 0)
                            .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                            .blur(radius: 3)

                        SmoothTimelineLineShape(points: points)
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
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: .primary.opacity(0.1), radius: 5, x: 0, y: 2)
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
        case .distracted: .red
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
        .background(category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum AppIconResolver {
    static func image(appName: String, bundleID: String?) -> NSImage? {
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
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private func stepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? tint : .secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Capsule()
                    .fill(isOn ? tint.gradient : Color.secondary.opacity(0.22).gradient)
                    .frame(width: 34, height: 18)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.background)
                            .frame(width: 14, height: 14)
                            .padding(2)
                    }
            }
            .padding(10)
            .background(isOn ? tint.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? tint.opacity(0.24) : Color.primary.opacity(0.05), lineWidth: 1)
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
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }

    private var displayValue: String {
        if suffix == "%" {
            "\(Int((value * 100).rounded()))%"
        } else {
            "\(Int(value.rounded()))\(suffix)"
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

private let previewablePetActions: [PetAction] = [
    .idle,
    .distractedLook,
    .nudgeStrong,
    .breakRelax,
    .welcomeBack,
    .stretch,
    .run
]

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
        case .run: "figure.run"
        case .screenTransfer: "arrow.left.arrow.right.circle.fill"
        case .mouseSummon: "cursorarrow.motionlines"
        }
    }

    var tint: Color {
        switch self {
        case .focusStart, .focusStable: .green
        case .distractedLook, .nudgeGentle, .nudgeStrong: .orange
        case .breakRelax, .breakEnd: .blue
        case .sleep, .wake, .welcomeBack: .indigo
        case .dragged, .landing, .run, .screenTransfer, .mouseSummon: .purple
        case .idle, .blink, .breath, .stretch: .secondary
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
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TodayAppUsageBarChartPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var items: [AppUsageDisplayItem] {
        Array(AppUsageDisplayItem.merged(from: model.summary.appUsage).prefix(7))
    }

    private var maxSeconds: Int {
        max(1, items.map(\.seconds).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("App 时间排行", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Spacer()
                StatusPill("柱状图", symbol: "chart.bar.fill")
            }

            if items.isEmpty {
                Text("暂无 App 使用统计。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("App")
                            .frame(width: 176, alignment: .leading)
                        Text("时间分布")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("时长")
                            .frame(width: 68, alignment: .trailing)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        TodayAppUsageBarRow(item: item, rank: index + 1, maxSeconds: maxSeconds)
                    }
                }
            }
        }
        .dashboardCard()
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
            accumulator.categorySeconds[item.category, default: 0] += item.seconds
            for (state, seconds) in item.stateBreakdown {
                accumulator.stateBreakdown[state, default: 0] += seconds
            }
            grouped[key] = accumulator
        }

        return grouped.map { key, accumulator in
            let category = accumulator.categorySeconds.max { lhs, rhs in lhs.value < rhs.value }?.key ?? .neutral
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
            Text("#\(rank)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            AppIconView(appName: item.appName, bundleID: item.bundleID, category: item.category, size: 26)

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
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.primary.opacity(rank <= 3 ? 0.035 : 0.018), in: RoundedRectangle(cornerRadius: 7))
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

    private var sessions: [FocusHistorySession] {
        FocusHistorySession.build(from: model.stateSegments)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FocusSessionControlPanel()
                FocusSessionRecordsPanel()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("自动片段", systemImage: "waveform.path.ecg")
                            .font(.headline)
                        Spacer()
                        StatusPill("\(sessions.count) 段", symbol: "number")
                    }
                    if sessions.isEmpty {
                        Text("暂无连续专注/走神片段。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { session in
                            FocusHistorySessionCard(session: session)
                        }
                    }
                }
                .dashboardCard()
            }
        }
    }
}

private struct FocusSessionControlPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var taskName = "专注任务"

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    identityTile(at: context.date)
                    controls
                }

                VStack(alignment: .leading, spacing: 12) {
                    identityTile(at: context.date)
                    controls
                }
            }
        }
        .dashboardCard()
    }

    private func identityTile(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.activeFocusSession == nil ? "timer" : "timer.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 38, height: 38)
                    .background(.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.activeFocusSession?.taskName ?? "专注任务")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(sessionSubtitle(at: date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(primaryTime(at: date))
                    .font(.title2.monospacedDigit().weight(.semibold))
            }

            MiniMeter(ratio: sessionProgress(at: date), tint: .green)
                .frame(height: 10)

            HStack(spacing: 8) {
                SessionStatPill(title: "今日专注", value: FocusPetFormatters.duration(model.summary.focusSeconds), symbol: "checkmark.circle.fill", tint: .green)
                SessionStatPill(title: "今日走神", value: FocusPetFormatters.duration(model.summary.distractedSeconds), symbol: "eye.trianglebadge.exclamationmark", tint: .orange)
                SessionStatPill(title: "暂离", value: FocusPetFormatters.duration(model.summary.awaySeconds), symbol: FocusPetCore.FocusState.away.symbolName, tint: .indigo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.activeFocusSession == nil {
                TextField("专注任务", text: $taskName)
                    .textFieldStyle(.roundedBorder)
                NumberStepperControl(
                    title: "目标",
                    value: $model.settings.focusTargetMinutes,
                    range: 5...180,
                    suffix: "分钟",
                    tint: .green
                )
                .onChange(of: model.settings.focusTargetMinutes) { _, _ in model.saveSettings() }
                TogglePillButton(title: "完成后自动休息", symbol: "cup.and.saucer.fill", isOn: $model.settings.autoStartBreak, tint: .blue)
                    .onChange(of: model.settings.autoStartBreak) { _, _ in model.saveSettings() }
                Button {
                    model.startFocusSession(taskName: taskName, minutes: model.settings.focusTargetMinutes)
                } label: {
                    Label("开始专注", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Button {
                    model.finishCurrentFocusSession()
                } label: {
                    Label("完成专注", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button(role: .destructive) {
                    model.finishCurrentFocusSession(completed: false)
                } label: {
                    Label("取消会话", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(width: 260, alignment: .top)
    }

    private func sessionSubtitle(at date: Date) -> String {
        guard let session = model.activeFocusSession else {
            return "目标 \(FocusPetFormatters.duration(model.settings.focusTargetMinutes * 60))"
        }
        return "\(FocusPetFormatters.clock(session.start)) 开始 · \(statusTitle(at: date))"
    }

    private func statusTitle(at date: Date) -> String {
        guard let session = model.activeFocusSession else { return "" }
        let remaining = max(0, session.targetDurationSeconds - session.elapsedSeconds(now: date))
        return remaining == 0 ? "可完成" : "剩余 \(FocusPetFormatters.duration(remaining))"
    }

    private func primaryTime(at date: Date) -> String {
        guard let session = model.activeFocusSession else {
            return "\(model.settings.focusTargetMinutes) 分钟"
        }
        return FocusPetFormatters.duration(session.elapsedSeconds(now: date))
    }

    private func sessionProgress(at date: Date) -> Double {
        guard let session = model.activeFocusSession else { return 0 }
        return min(1, Double(session.elapsedSeconds(now: date)) / Double(max(1, session.targetDurationSeconds)))
    }
}

private struct FocusSessionRecordsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    private var sessions: [FocusSession] {
        model.focusSessions.sorted { $0.start > $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("任务记录", systemImage: "list.bullet.rectangle.portrait.fill")
                    .font(.headline)
                Spacer()
                StatusPill("\(sessions.count) 条", symbol: "number")
            }
            if sessions.isEmpty {
                Text("暂无专注任务记录。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions.prefix(8)) { session in
                    FocusSessionHistoryCard(session: session)
                }
            }
        }
        .dashboardCard()
    }
}

private struct FocusHistorySession: Identifiable {
    var id: String
    var start: Date
    var end: Date
    var focusSeconds: Int
    var distractedSeconds: Int
    var ranges: [StatusStripRange]

    var totalSeconds: Int {
        max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    static func build(from segments: [StateSegment]) -> [FocusHistorySession] {
        var result: [FocusHistorySession] = []
        var currentStart: Date?
        var currentEnd: Date?
        var focusSeconds = 0
        var distractedSeconds = 0
        var ranges: [StatusStripRange] = []

        func flush() {
            guard let start = currentStart,
                  let end = currentEnd,
                  end > start,
                  !ranges.isEmpty else {
                currentStart = nil
                currentEnd = nil
                focusSeconds = 0
                distractedSeconds = 0
                ranges = []
                return
            }
            result.append(FocusHistorySession(
                id: "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)",
                start: start,
                end: end,
                focusSeconds: focusSeconds,
                distractedSeconds: distractedSeconds,
                ranges: ranges
            ))
            currentStart = nil
            currentEnd = nil
            focusSeconds = 0
            distractedSeconds = 0
            ranges = []
        }

        for segment in segments.sorted(by: { $0.start < $1.start }) {
            switch segment.state {
            case .focus, .distracted:
                if currentStart == nil {
                    currentStart = segment.start
                }
                currentEnd = max(currentEnd ?? segment.end, segment.end)
                let seconds = max(0, Int(segment.end.timeIntervalSince(segment.start).rounded()))
                if segment.state == .focus {
                    focusSeconds += seconds
                } else {
                    distractedSeconds += seconds
                }
                ranges.append(StatusStripRange(start: segment.start, end: segment.end, state: segment.state))
            case .breakTime, .away:
                flush()
            }
        }
        flush()

        return Array(result.reversed())
    }
}

private struct FocusHistorySessionCard: View {
    var session: FocusHistorySession

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(FocusPetFormatters.clock(session.start)) - \(FocusPetFormatters.clock(session.end))")
                        .font(.headline.monospacedDigit())
                    Text("连续专注/走神片段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(FocusPetFormatters.duration(session.totalSeconds))
                    .font(.title3.monospacedDigit().weight(.semibold))
            }

            StateSegmentStrip(ranges: session.ranges, start: session.start, end: session.end, height: 13)
                .frame(height: 20)

            HStack(spacing: 8) {
                SessionStatPill(title: "专注", value: FocusPetFormatters.duration(session.focusSeconds), symbol: FocusPetCore.FocusState.focus.symbolName, tint: .green)
                SessionStatPill(title: "走神", value: FocusPetFormatters.duration(session.distractedSeconds), symbol: FocusPetCore.FocusState.distracted.symbolName, tint: .red)
                SessionStatPill(title: "总时长", value: FocusPetFormatters.duration(session.totalSeconds), symbol: "clock.fill", tint: .blue)
            }
        }
        .padding(12)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
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
            .buttonStyle(.borderedProminent)
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
            Text("电脑未 sleep 且不在休息时，系统只在专注和走神之间切换；超过 1 分钟无输入会进入走神。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dashboardCard()
    }
}

struct FocusSessionHistoryCard: View {
    var session: FocusSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.taskName)
                        .font(.title3.weight(.semibold))
                    Text("\(FocusPetFormatters.clock(session.start)) · \(statusTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(FocusPetFormatters.percentage(session.completionRatio))
                    .font(.headline.monospacedDigit())
            }

            MiniMeter(ratio: session.completionRatio, tint: statusTint)
                .frame(height: 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 132), spacing: 8), count: 4), spacing: 8) {
                SessionStatPill(title: "有效专注", value: FocusPetFormatters.duration(session.effectiveFocusSeconds), symbol: "checkmark.circle.fill", tint: .green)
                SessionStatPill(title: "主用 App", value: session.mainAppName ?? "暂无", symbol: "macwindow", tint: .blue, appName: session.mainAppName)
                SessionStatPill(title: "打断", value: "\(session.interruptionCount) 次", symbol: "exclamationmark.triangle.fill", tint: .orange)
                SessionStatPill(title: "切换", value: "\(session.switchCount) 次", symbol: "arrow.triangle.2.circlepath", tint: .purple)
            }

            Text("走神 \(FocusPetFormatters.duration(session.distractedSeconds)) · 暂离 \(FocusPetFormatters.duration(session.awaySeconds)) · 目标 \(FocusPetFormatters.duration(session.targetDurationSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusTitle: String {
        switch session.status {
        case .active: "进行中"
        case .completed: "完成"
        case .cancelled: "已取消"
        }
    }

    private var statusTint: Color {
        switch session.status {
        case .active: .blue
        case .completed: .green
        case .cancelled: .orange
        }
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
                AppIconView(appName: appName, bundleID: nil, category: .neutral, size: 24)
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                ForEach(choices) { choice in
                    KeywordRuleCard(choice: choice, selectedCategory: selectedCategory)
                }
            }
        }
        .dashboardCard()
    }
}

private struct KeywordRuleCard: View {
    @EnvironmentObject private var model: FocusPetModel
    var choice: RuleChoice
    var selectedCategory: ActivityCategory

    private var effectiveCategory: ActivityCategory {
        model.categoryForRule(pattern: choice.title, matchKind: choice.matchKind) ?? choice.defaultCategory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: choice.defaultCategory.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(effectiveCategory.tint)
                    .frame(width: 28, height: 28)
                    .background(effectiveCategory.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(choice.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

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
        }
        .padding(10)
        .background(keywordBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(effectiveCategory == selectedCategory ? effectiveCategory.tint.opacity(0.34) : .primary.opacity(0.05), lineWidth: 1)
        }
    }

    private var keywordBackground: Color {
        effectiveCategory == selectedCategory ? effectiveCategory.tint.opacity(0.08) : .primary.opacity(0.025)
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
        if choice.matchKind == .appName {
            AppIconView(appName: choice.title, bundleID: choice.bundleID, category: category, size: 38)
        } else {
            Image(systemName: "textformat")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(category.tint)
                .frame(width: 38, height: 38)
                .background(category.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PetSettingsPanel()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], spacing: 12) {
                    ReminderSettingsPanel()
                    PrivacySettingsPanel()
                    RetentionSettingsPanel()
                    AboutSettingsPanel()
                }
            }
        }
        .onAppear {
            model.refreshPetPacks()
        }
    }
}

private struct PetSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var previewAction: PetAction = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .buttonStyle(.bordered)

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
                ActionPreviewStrip(record: record, previewAction: $previewAction)
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

            if model.settings.pet.placement == .custom,
               let x = model.settings.pet.customOriginX,
               let y = model.settings.pet.customOriginY {
                Text("自定义位置：x \(Int(x)), y \(Int(y))。拖动桌宠可更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8)], spacing: 8) {
                ControlSliderRow(title: "大小", value: $model.settings.pet.size, range: 96...260, suffix: "px", tint: .purple)
                    .onChange(of: model.settings.pet.size) { _, _ in model.saveSettings() }
                ControlSliderRow(title: "透明度", value: $model.settings.pet.opacity, range: 0.35...1, suffix: "%", tint: .blue)
                    .onChange(of: model.settings.pet.opacity) { _, _ in model.saveSettings() }
            }
        }
        .dashboardCard()
    }
}

private struct ActionPreviewStrip: View {
    @EnvironmentObject private var model: FocusPetModel
    var record: PetPackRecord
    @Binding var previewAction: PetAction

    private var options: [SlidingSegmentOption<PetAction>] {
        let available = previewablePetActions.filter { action in
            if record.rootURL == nil {
                return PetActionResolver().animationKey(for: action, in: record.pack) != nil
            }
            return !record.frameURLs(for: action).isEmpty
        }
        let actions = available.isEmpty ? [.idle] : available
        return actions.map { action in
            SlidingSegmentOption(
                value: action,
                title: action.title,
                symbol: action.symbolName,
                tint: action.tint
            )
        }
    }

    var body: some View {
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
                .buttonStyle(.borderedProminent)
            }
            SlidingSegmentedPicker(
                options: options,
                selection: $previewAction,
                compact: true
            )
            .onAppear {
                if !options.map(\.value).contains(previewAction) {
                    previewAction = options.first?.value ?? .idle
                }
            }
        }
    }
}

private struct ReminderSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .dashboardCard()
    }
}

private struct PrivacySettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("隐私设置", systemImage: "lock.shield.fill")
                .font(.headline)
            TogglePillButton(title: "暂停所有记录", symbol: "pause.circle.fill", isOn: $model.settings.privacy.pauseActivityRecording, tint: .orange)
                .onChange(of: model.settings.privacy.pauseActivityRecording) { _, _ in model.saveSettings() }
            Text(model.recordingStatusTitle)
                .font(.caption)
                .foregroundStyle(model.settings.privacy.pauseActivityRecording ? .orange : .secondary)
            TogglePillButton(title: "只保存分类结果", symbol: "tag.fill", isOn: $model.settings.privacy.storeOnlyCategoryResult, tint: .blue)
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
            Text("默认只保存 App、分类、状态和时间，并持久化脱敏标题线索。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }
}

private struct RetentionSettingsPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .buttonStyle(.bordered)
            if let exportURL = model.exportURL {
                Text(exportURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .dashboardCard()
    }
}

private struct AboutSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("关于", systemImage: "info.circle.fill")
                .font(.headline)
            Text("Focus Pet 使用前台 App、窗口标题分类、输入空闲和专注/休息会话判断状态。所有数据保存在本机。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dashboardCard()
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

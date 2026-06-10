import AVFoundation
import FocusPetCore
import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var model: FocusPetModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView(selection: $model.selectedDashboardTab) {
            TodayView()
                .tabItem {
                    Label(DashboardTab.today.title, systemImage: DashboardTab.today.symbolName)
                }
                .tag(DashboardTab.today)

            RulesView()
                .tabItem {
                    Label(DashboardTab.rules.title, systemImage: DashboardTab.rules.symbolName)
                }
                .tag(DashboardTab.rules)

            PetSettingsView()
                .tabItem {
                    Label(DashboardTab.pet.title, systemImage: DashboardTab.pet.symbolName)
                }
                .tag(DashboardTab.pet)

            FaceLogView()
                .tabItem {
                    Label(DashboardTab.faceLog.title, systemImage: DashboardTab.faceLog.symbolName)
                }
                .tag(DashboardTab.faceLog)

            PrivacyView()
                .tabItem {
                    Label(DashboardTab.privacy.title, systemImage: DashboardTab.privacy.symbolName)
                }
                .tag(DashboardTab.privacy)
        }
        .padding(18)
        .onAppear {
            DashboardWindowCoordinator.opener = { tab in
                model.selectedDashboardTab = tab
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .sheet(isPresented: Binding(
            get: { !model.hasCompletedOnboarding },
            set: { if !$0 { model.completeOnboarding() } }
        )) {
            OnboardingView()
                .environmentObject(model)
        }
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.currentState.userState.title, systemImage: model.menuBarSymbolName)
            Text("今日专注 \(FocusPetFormatters.duration(model.todaySummary.focusSeconds))")
            Text("走神 \(FocusPetFormatters.duration(model.todaySummary.distractedSeconds)) · 暂离 \(model.todaySummary.awayCount) 次")
            Divider()

            Button(model.isPaused ? "恢复检测" : "暂停检测") {
                model.togglePause()
            }

            Button(model.petHidden ? "显示桌宠" : "隐藏桌宠") {
                model.togglePetVisibility()
            }

            Button(model.cameraSamplingEnabled ? "关闭视觉辅助" : "开启视觉辅助") {
                model.setCameraSamplingEnabled(!model.cameraSamplingEnabled)
            }

            Button("打开控制台") {
                model.openMainWindow(tab: .today)
            }

            Button("桌宠设置") {
                model.openMainWindow(tab: .pet)
            }

            Button("打开隐私面板") {
                model.openMainWindow(tab: .privacy)
            }

            Divider()
            Button("退出应用") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DashboardHeroHeader()

                CurrentStatePanel()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 180), spacing: 12), count: 3), spacing: 12) {
                    MetricTile(
                        title: "有效专注",
                        value: FocusPetFormatters.duration(model.todaySummary.focusSeconds),
                        symbol: "checkmark.circle.fill",
                        tint: .green
                    )
                    MetricTile(
                        title: "走神时长",
                        value: FocusPetFormatters.duration(model.todaySummary.distractedSeconds),
                        symbol: "eye.slash.fill",
                        tint: .orange
                    )
                    MetricTile(
                        title: "暂离次数",
                        value: "\(model.todaySummary.awayCount) 次",
                        symbol: "moon.zzz.fill",
                        tint: .indigo
                    )
                }

                WorkStatusOverviewView(events: model.stateEvents)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DashboardHeroHeader: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: model.menuBarSymbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(model.isPaused ? Color.secondary : Color.accentColor)
                        .frame(width: 30, height: 30)
                    Text("Focus Pet")
                        .font(.largeTitle.weight(.semibold))
                }

                Text(model.isPaused ? model.pauseStatusTitle : model.recentStateDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 18)

            HStack(spacing: 10) {
                Button {
                    model.togglePause()
                } label: {
                    Label(model.isPaused ? "继续" : "暂停", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button {
                    model.togglePetVisibility()
                } label: {
                    Label(model.petHidden ? "显示桌宠" : "隐藏桌宠", systemImage: model.petHidden ? "eye.fill" : "eye.slash.fill")
                }

                Button {
                    model.openMainWindow(tab: .pet)
                } label: {
                    Label("桌宠", systemImage: "pawprint.fill")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CurrentStatePanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("当前状态", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: model.currentState.userState.statusSymbolName)
                    .font(.system(size: 34))
                    .foregroundStyle(model.isPaused ? Color.secondary : Color.green)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isPaused ? "检测已暂停" : model.currentState.userState.title)
                        .font(.title2.weight(.semibold))
                    Text("前台应用：\(model.frontAppName) · \(model.currentState.context.title)")
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    StatusPill(title: model.localActivitySummary, symbol: "keyboard")
                    StatusPill(title: model.observationSourceTitle, symbol: "tag.fill")
                }

                VStack(alignment: .leading, spacing: 8) {
                    StatusPill(title: model.localActivitySummary, symbol: "keyboard")
                    StatusPill(title: model.observationSourceTitle, symbol: "tag.fill")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .dashboardCard(.regularMaterial)
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .dashboardCard(.thinMaterial)
    }
}

struct StatusPill: View {
    var title: String
    var symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}

extension View {
    func dashboardCard(_ material: Material) -> some View {
        background(material, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct WorkStatusOverviewView: View {
    var events: [StateEvent]

    private var snapshot: WorkStatusSnapshot {
        WorkStatusSnapshot(events: events, hours: 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("最近状态概览", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text("近 4 小时")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    StateLineChart(points: snapshot.points, hasData: snapshot.hasData)
                        .frame(minWidth: 420, minHeight: 190)
                    StateDonutSummary(snapshot: snapshot)
                        .frame(width: 300)
                }

                VStack(alignment: .leading, spacing: 16) {
                    StateLineChart(points: snapshot.points, hasData: snapshot.hasData)
                        .frame(minHeight: 190)
                    StateDonutSummary(snapshot: snapshot)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard(.thinMaterial)
    }
}

private struct StateLineChart: View {
    var points: [StatusChartPoint]
    var hasData: Bool
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("办公节奏")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 10) {
                    ChartLegendDot(title: "专注", color: UserState.focused.chartColor)
                    ChartLegendDot(title: "走神", color: UserState.distracted.chartColor)
                    ChartLegendDot(title: "暂离", color: UserState.away.chartColor)
                }
            }

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    ChartGrid()
                    if hasData {
                        chartPath(size: size)
                            .trim(from: 0, to: reveal ? 1 : 0)
                            .stroke(
                                LinearGradient(
                                    colors: [UserState.focused.chartColor, UserState.distracted.chartColor, UserState.away.chartColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: .primary.opacity(0.08), radius: 5, y: 2)

                        ForEach(points.suffix(18)) { point in
                            Circle()
                                .fill(point.state.chartColor)
                                .frame(width: 7, height: 7)
                                .position(position(for: point, size: size))
                                .opacity(reveal ? 1 : 0)
                        }
                    } else {
                        Text("暂无最近状态")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
    }

    private func chartPath(size: CGSize) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: position(for: first, size: size))
            for point in points.dropFirst() {
                path.addLine(to: position(for: point, size: size))
            }
        }
    }

    private func position(for point: StatusChartPoint, size: CGSize) -> CGPoint {
        let x = size.width * point.progress
        let y = size.height * (1 - point.level)
        return CGPoint(x: x, y: y)
    }
}

private struct ChartGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let height = proxy.size.height
                let width = proxy.size.width
                for index in 0...3 {
                    let y = height * CGFloat(index) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }
    }
}

private struct StateDonutSummary: View {
    var snapshot: WorkStatusSnapshot

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if snapshot.totalSeconds <= 0 {
                    Circle()
                        .stroke(.quaternary, lineWidth: 20)
                } else {
                    ForEach(snapshot.slices) { slice in
                        Circle()
                            .trim(from: slice.start, to: slice.end)
                            .stroke(slice.state.chartColor, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                }

                VStack(spacing: 2) {
                    Text("\(snapshot.focusPercent)%")
                        .font(.title3.weight(.semibold))
                    Text("专注")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 9) {
                Text("时间占比")
                    .font(.subheadline.weight(.semibold))
                ForEach(snapshot.legend) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.state.chartColor)
                            .frame(width: 8, height: 8)
                        Text(item.state.title)
                            .frame(width: 42, alignment: .leading)
                        Text(FocusPetFormatters.duration(item.seconds))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChartLegendDot: View {
    var title: String
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct WorkStatusSnapshot {
    var points: [StatusChartPoint]
    var slices: [StatusShareSlice]
    var legend: [StatusDurationItem]
    var totalSeconds: Int
    var focusPercent: Int
    var hasData: Bool

    init(events: [StateEvent], hours: Int) {
        let now = Date()
        let start = now.addingTimeInterval(TimeInterval(-hours * 60 * 60))
        let timeline = StateTimelineAnalyzer().summarize(
            events: events,
            from: start,
            to: now,
            sourceKind: .live
        )

        let durations = timeline.durations
        totalSeconds = timeline.totalSeconds
        legend = UserState.allCases.map { state in
            StatusDurationItem(state: state, seconds: durations[state, default: 0])
        }
        slices = Self.slices(from: legend, totalSeconds: totalSeconds)
        focusPercent = totalSeconds > 0
            ? Int((Double(durations[.focused, default: 0]) / Double(totalSeconds) * 100).rounded())
            : 0
        hasData = totalSeconds > 0
        points = Self.points(from: timeline.segments, start: start, end: now)
    }

    private static func slices(from items: [StatusDurationItem], totalSeconds: Int) -> [StatusShareSlice] {
        guard totalSeconds > 0 else { return [] }
        var cursor = 0.0
        return items.compactMap { item in
            guard item.seconds > 0 else { return nil }
            let share = Double(item.seconds) / Double(totalSeconds)
            let slice = StatusShareSlice(state: item.state, start: cursor, end: cursor + share)
            cursor += share
            return slice
        }
    }

    private static func points(from segments: [StateTimelineSegment], start: Date, end: Date) -> [StatusChartPoint] {
        guard !segments.isEmpty else { return [] }
        let span = max(1, end.timeIntervalSince(start))
        var points: [StatusChartPoint] = []

        for segment in segments {
            let startProgress = progress(for: segment.startTime, windowStart: start, span: span)
            let endProgress = progress(for: segment.endTime, windowStart: start, span: span)

            if points.last?.progress != startProgress || points.last?.state != segment.userState {
                points.append(StatusChartPoint(progress: startProgress, state: segment.userState))
            }
            points.append(StatusChartPoint(progress: endProgress, state: segment.userState))
        }

        return points
    }

    private static func progress(for date: Date, windowStart: Date, span: TimeInterval) -> Double {
        let value = date.timeIntervalSince(windowStart) / span
        return min(max(value, 0), 1)
    }
}

private struct StatusChartPoint: Identifiable {
    var id: String { "\(state.rawValue)-\(Int((progress * 10_000).rounded()))" }
    var progress: Double
    var state: UserState

    var level: Double {
        switch state {
        case .focused: 0.82
        case .distracted: 0.48
        case .away: 0.16
        }
    }
}

private struct StatusDurationItem: Identifiable {
    var id: UserState { state }
    var state: UserState
    var seconds: Int
}

private struct StatusShareSlice: Identifiable {
    var id: UserState { state }
    var state: UserState
    var start: Double
    var end: Double
}

private extension UserState {
    var chartColor: Color {
        switch self {
        case .focused: .green
        case .distracted: .orange
        case .away: .indigo
        }
    }
}

struct RulesView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("规则")
                        .font(.largeTitle.weight(.semibold))
                    Text("这里展示真实判断逻辑。状态识别以本地输入和前台应用为主，提醒规则只决定什么时候打扰你。")
                        .foregroundStyle(.secondary)
                }

                LogicOverviewCard(cameraSamplingEnabled: model.cameraSamplingEnabled)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 210), spacing: 12), count: 3), spacing: 12) {
                    LogicStateCard(
                        state: .focused,
                        summary: "正在投入当前任务",
                        bullets: [
                            "工作应用里有键盘或鼠标输入",
                            "会议应用短时无输入仍视为专注",
                            "开启视觉辅助时，看屏幕会强化专注判断"
                        ]
                    )
                    LogicStateCard(
                        state: .distracted,
                        summary: "可能偏离当前任务",
                        bullets: [
                            "本地输入空闲超过 60 秒",
                            "娱乐应用或页面持续一段时间",
                            "开启视觉辅助时，离屏或低头会辅助判断"
                        ]
                    )
                    LogicStateCard(
                        state: .away,
                        summary: "较长时间没有电脑操作",
                        bullets: [
                            "无键盘、鼠标或滚动输入超过 180 秒",
                            "会议无输入超过 10 分钟会转为暂离",
                            "开启视觉辅助时，持续无人脸会辅助判断"
                        ]
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Label("提醒设置", systemImage: "bell.badge.fill")
                            .font(.headline)
                        Spacer()
                        PresetButton(title: "安静") {
                            applyPreset(.quiet)
                        }
                        PresetButton(title: "平衡") {
                            applyPreset(.balanced)
                        }
                        PresetButton(title: "积极") {
                            applyPreset(.active)
                        }
                    }

                    ForEach($model.rules) { $rule in
                        ReminderRuleEditor(rule: $rule)
                    }
                }
                .padding(16)
                .dashboardCard(.regularMaterial)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onChange(of: model.rules) { _, _ in
            model.saveRules()
        }
    }

    private func applyPreset(_ preset: ReminderPreset) {
        for index in model.rules.indices {
            switch model.rules[index].id {
            case FocusRule.distractionReminder.id:
                model.rules[index].durationSeconds = preset.distractionSeconds
                model.rules[index].cooldownSeconds = preset.shortCooldownSeconds
            case FocusRule.entertainmentDistraction.id:
                model.rules[index].durationSeconds = preset.entertainmentSeconds
                model.rules[index].cooldownSeconds = preset.longCooldownSeconds
            case FocusRule.awayReminder.id:
                model.rules[index].durationSeconds = preset.awaySeconds
                model.rules[index].cooldownSeconds = preset.longCooldownSeconds
            default:
                break
            }
        }
        model.saveRules()
    }
}

private struct LogicOverviewCard: View {
    var cameraSamplingEnabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("判断流程")
                    .font(.headline)
                Text("本地输入 + 前台应用先形成状态；可选视觉只作为辅助；达到提醒阈值后，桌宠才提示。")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                StatusPill(title: "本地活动", symbol: "keyboard")
                StatusPill(title: cameraSamplingEnabled ? "视觉辅助开启" : "视觉辅助关闭", symbol: cameraSamplingEnabled ? "camera.fill" : "camera.slash.fill")
            }
        }
        .padding(16)
        .dashboardCard(.thinMaterial)
    }
}

private struct LogicStateCard: View {
    var state: UserState
    var summary: String
    var bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: state.statusSymbolName)
                    .font(.title3)
                    .foregroundStyle(state.chartColor)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(.headline)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(bullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .dashboardCard(.thinMaterial)
    }
}

private struct ReminderRuleEditor: View {
    @Binding var rule: FocusRule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Toggle(isOn: $rule.isEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayTitle)
                            .font(.headline)
                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(rule.action.strength.title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    RuleStepper(title: "等待", value: $rule.durationSeconds, range: durationRange, step: durationStep, suffix: "秒")
                    RuleStepper(title: "冷却", value: $rule.cooldownSeconds, range: 120...3600, step: 60, suffix: "秒")
                }

                VStack(alignment: .leading, spacing: 10) {
                    RuleStepper(title: "等待", value: $rule.durationSeconds, range: durationRange, step: durationStep, suffix: "秒")
                    RuleStepper(title: "冷却", value: $rule.cooldownSeconds, range: 120...3600, step: 60, suffix: "秒")
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .opacity(rule.isEnabled ? 1 : 0.58)
    }

    private var displayTitle: String {
        switch rule.id {
        case FocusRule.distractionReminder.id: "本地空闲走神提醒"
        case FocusRule.entertainmentDistraction.id: "娱乐走神提醒"
        case FocusRule.awayReminder.id: "暂离过久提醒"
        default: rule.name
        }
    }

    private var explanation: String {
        switch rule.id {
        case FocusRule.distractionReminder.id:
            "进入走神后，再持续一段时间才提醒。适合调节打扰频率。"
        case FocusRule.entertainmentDistraction.id:
            "识别到娱乐应用或娱乐网站，并持续走神后提醒。"
        case FocusRule.awayReminder.id:
            "较长时间没有电脑操作时提醒你是否暂停记录。"
        default:
            rule.action.message
        }
    }

    private var durationRange: ClosedRange<Double> {
        switch rule.id {
        case FocusRule.awayReminder.id: 60...900
        default: 10...300
        }
    }

    private var durationStep: Double {
        rule.id == FocusRule.awayReminder.id ? 30 : 10
    }
}

private struct RuleStepper: View {
    var title: String
    @Binding var value: TimeInterval
    var range: ClosedRange<Double>
    var step: Double
    var suffix: String

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(formattedValue)
                    .fontWeight(.medium)
            }
            .frame(minWidth: 150, alignment: .leading)
        }
    }

    private var formattedValue: String {
        if value >= 60 {
            return "\(Int(value / 60)) 分钟"
        }
        return "\(Int(value)) \(suffix)"
    }
}

private struct PresetButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

private struct ReminderPreset {
    var distractionSeconds: TimeInterval
    var entertainmentSeconds: TimeInterval
    var awaySeconds: TimeInterval
    var shortCooldownSeconds: TimeInterval
    var longCooldownSeconds: TimeInterval

    static let quiet = ReminderPreset(
        distractionSeconds: 60,
        entertainmentSeconds: 120,
        awaySeconds: 300,
        shortCooldownSeconds: 900,
        longCooldownSeconds: 1_800
    )
    static let balanced = ReminderPreset(
        distractionSeconds: 20,
        entertainmentSeconds: 60,
        awaySeconds: 180,
        shortCooldownSeconds: 300,
        longCooldownSeconds: 900
    )
    static let active = ReminderPreset(
        distractionSeconds: 10,
        entertainmentSeconds: 30,
        awaySeconds: 120,
        shortCooldownSeconds: 180,
        longCooldownSeconds: 600
    )
}

struct FaceLogView: View {
    @EnvironmentObject private var model: FocusPetModel

    private var recentEntries: [FaceDiagnosticEntry] {
        Array(model.faceDiagnostics.suffix(90).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("本地判断日志")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Text("\(model.faceDiagnostics.count) 条")
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    DiagnosticStat(title: "来源", value: model.observationSourceTitle, symbol: "tag.fill")
                    DiagnosticStat(title: "本地输入", value: model.localActivitySummary, symbol: "keyboard")
                    DiagnosticStat(title: "应用", value: model.appStabilitySummary, symbol: "macwindow")
                    DiagnosticStat(title: "状态", value: model.currentState.userState.title, symbol: model.currentState.userState.statusSymbolName)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 140), spacing: 10), count: 2), spacing: 10) {
                    DiagnosticStat(title: "来源", value: model.observationSourceTitle, symbol: "tag.fill")
                    DiagnosticStat(title: "本地输入", value: model.localActivitySummary, symbol: "keyboard")
                    DiagnosticStat(title: "应用", value: model.appStabilitySummary, symbol: "macwindow")
                    DiagnosticStat(title: "状态", value: model.currentState.userState.title, symbol: model.currentState.userState.statusSymbolName)
                }
            }

            HStack {
                Text("时间").frame(width: 84, alignment: .leading)
                Text("阶段").frame(width: 44, alignment: .leading)
                Text("帧").frame(width: 48, alignment: .leading)
                Text("人脸").frame(width: 58, alignment: .leading)
                Text("视线").frame(width: 70, alignment: .leading)
                Text("俯仰").frame(width: 58, alignment: .leading)
                Text("置信").frame(width: 56, alignment: .leading)
                Text("融合状态").frame(width: 72, alignment: .leading)
                Text("原因").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if recentEntries.isEmpty {
                        Text("暂无判断日志。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                    } else {
                        ForEach(recentEntries) { entry in
                            FaceLogRow(entry: entry)
                        }
                    }
                }
            }
            .frame(minHeight: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

struct DiagnosticStat: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FaceLogRow: View {
    var entry: FaceDiagnosticEntry

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .frame(width: 84, alignment: .leading)
            Text(entry.phase.title)
                .frame(width: 44, alignment: .leading)
            Text(entry.frameSequenceNumber.map(String.init) ?? "-")
                .frame(width: 48, alignment: .leading)
            Text(faceTitle(entry.facePresence))
                .frame(width: 58, alignment: .leading)
            Text(gazeTitle(entry.gazeState))
                .frame(width: 70, alignment: .leading)
            Text("\(Int(entry.headPitchDegrees.rounded()))°")
                .frame(width: 58, alignment: .leading)
            Text("\(Int(entry.visionConfidence * 100))%")
                .frame(width: 56, alignment: .leading)
            Text(entry.fusedState?.title ?? "-")
                .frame(width: 72, alignment: .leading)
                .foregroundStyle(entry.fusedState == .distracted ? Color.orange : .primary)
            Text(entry.reason.joined(separator: " · "))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func faceTitle(_ value: FacePresence) -> String {
        switch value {
        case .present: "有人脸"
        case .missing: "无人脸"
        case .unknown: "未知"
        }
    }

    private func gazeTitle(_ value: GazeState) -> String {
        switch value {
        case .screen: "看屏幕"
        case .offScreen: "离屏"
        case .down: "低头"
        case .side: "侧脸"
        case .unknown: "未知"
        }
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("隐私")
                    .font(.largeTitle.weight(.semibold))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        PrivacyStatusCard()
                        LocalDataCard()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        PrivacyStatusCard()
                        LocalDataCard()
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("隐私承诺", systemImage: "lock.shield.fill")
                        .font(.headline)
                    PrivacyCommitmentGrid(items: model.privacyCommitments)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct PrivacyStatusCard: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("视觉辅助", systemImage: "camera.fill")
                .font(.headline)
            Text(model.cameraStatusTitle)
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 130), spacing: 8), count: 2), alignment: .leading, spacing: 8) {
                StatusPill(title: model.observationSourceTitle, symbol: "tag.fill")
                StatusPill(title: model.localActivitySummary, symbol: "keyboard")
                StatusPill(title: model.appStabilitySummary, symbol: "macwindow")
                StatusPill(title: latestFrameTitle, symbol: "timer")
                StatusPill(title: model.pauseStatusTitle, symbol: "pause.circle.fill")
                StatusPill(title: model.currentState.userState.title, symbol: model.currentState.userState.statusSymbolName)
            }

            Text(model.latestFaceDetectionReason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Button {
                    model.setCameraSamplingEnabled(!model.cameraSamplingEnabled)
                } label: {
                    Label(model.cameraSamplingEnabled ? "关闭采集" : "开启采集", systemImage: model.cameraSamplingEnabled ? "camera.slash.fill" : "camera.fill")
                }

                if model.cameraAuthorization != .authorized {
                    Button("请求权限") {
                        model.requestCameraPermission()
                    }
                }

                Button("辅助功能") {
                    model.openAccessibilitySettings()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var latestFrameTitle: String {
        guard model.cameraSamplingEnabled else { return "已关闭" }
        guard let latestCameraFrameAt = model.latestCameraFrameAt else { return "暂无帧" }
        return "\(latestCameraFrameAt.formatted(date: .omitted, time: .standard)) · \(model.cameraFrameCount)"
    }
}

struct LocalDataCard: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("本地数据", systemImage: "externaldrive.fill")
                .font(.headline)
            Text(ByteCountFormatter.string(fromByteCount: Int64(model.localDataBytes), countStyle: .file))
                .font(.title3.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 110), spacing: 8), count: 3), alignment: .leading, spacing: 8) {
                CompactDataMetric(title: "状态", value: "\(model.stateEvents.count)")
                CompactDataMetric(title: "提醒", value: "\(model.reminderHistory.count)")
                CompactDataMetric(title: "日志", value: "\(model.faceDiagnostics.count)")
            }

            Text(model.localDataStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Button("导出数据") {
                    model.exportLocalData()
                }
                Button("删除所有数据", role: .destructive) {
                    model.deleteAllLocalData()
                }
            }
            if let exportedDataURL = model.exportedDataURL {
                Text(exportedDataURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CompactDataMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PrivacyCommitmentGrid: View {
    var items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                StatusPill(title: item, symbol: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Focus Pet")
                .font(.largeTitle.weight(.bold))
            Text("本地运行的 Mac 专注伙伴")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("摄像头只用于本地状态识别", systemImage: "camera.fill")
                Label("默认不保存视频或图片", systemImage: "photo.badge.exclamationmark")
                Label("不做人脸身份识别", systemImage: "person.crop.circle.badge.xmark")
                Label("可以随时暂停和删除本地数据", systemImage: "trash.fill")
            }
            .font(.body)

            HStack {
                Button("先进入原型") {
                    model.completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)

                Button("请求摄像头权限") {
                    model.requestCameraPermission()
                    model.completeOnboarding()
                }
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

import AVFoundation
import FocusPetCore
import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("今日", systemImage: "chart.bar.xaxis")
                }

            RulesView()
                .tabItem {
                    Label("规则", systemImage: "slider.horizontal.3")
                }

            PetSettingsView()
                .tabItem {
                    Label("桌宠", systemImage: "pawprint.fill")
                }

            PrivacyView()
                .tabItem {
                    Label("隐私", systemImage: "lock.shield.fill")
                }
        }
        .padding(18)
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.currentState.userState.title, systemImage: model.menuBarSymbolName)
            Text("今日专注 \(FocusPetFormatters.duration(model.todaySummary.focusSeconds))")
            Text("离屏 \(model.todaySummary.offScreenCount) 次 · 低头 \(FocusPetFormatters.duration(model.todaySummary.lookingDownSeconds))")
            Divider()

            Button(model.isPaused ? "恢复检测" : "暂停检测") {
                model.togglePause()
            }

            Button(model.petHidden ? "显示桌宠" : "隐藏桌宠") {
                model.togglePetVisibility()
            }

            Button("打开控制台") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("查看今日报告") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("打开隐私面板") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
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
                RuntimeModeControl()

                HStack(alignment: .top, spacing: 16) {
                    CurrentStatePanel()
                    ReminderPanel()
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    MetricTile(
                        title: "有效专注",
                        value: FocusPetFormatters.duration(model.todaySummary.focusSeconds),
                        symbol: "checkmark.circle.fill"
                    )
                    MetricTile(
                        title: "离屏次数",
                        value: "\(model.todaySummary.offScreenCount) 次",
                        symbol: "eye.slash.fill"
                    )
                    MetricTile(
                        title: "低头时长",
                        value: FocusPetFormatters.duration(model.todaySummary.lookingDownSeconds),
                        symbol: "figure.mind.and.body"
                    )
                    MetricTile(
                        title: "宠物能量",
                        value: "\(model.todaySummary.petEnergy)",
                        symbol: "bolt.heart.fill"
                    )
                }

                ReportCard(summary: model.todaySummary)
                DemoControlsView()
                EventTimelineView(events: model.stateEvents)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    Text(model.isPaused ? "摄像头已暂停" : model.currentState.userState.title)
                        .font(.title2.weight(.semibold))
                    Text("前台应用：\(model.frontAppName) · \(model.currentState.context.title)")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                StatusPill(title: "置信度 \(Int(model.currentState.confidence * 100))%", symbol: "waveform.path.ecg")
                StatusPill(title: model.cameraStatusTitle, symbol: "camera.fill")
                StatusPill(title: model.runtimeMode.title, symbol: "switch.2")
                StatusPill(title: model.currentObservation.sourceKind.title, symbol: "tag.fill")
            }

            Text(model.currentState.reason.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RuntimeModeControl: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        HStack(spacing: 14) {
            Picker("运行模式", selection: Binding(
                get: { model.runtimeMode },
                set: { model.setRuntimeMode($0) }
            )) {
                ForEach(RuntimeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Text(model.runtimeMode == .live
                ? "默认使用真实检测；没有视觉模型时，视觉字段保持 unknown。"
                : "Demo 事件会单独标记，不计入真实日报指标。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ReminderPanel: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("最近提醒", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)

            Text(model.lastReminderMessage)
                .font(.title3.weight(.medium))
                .lineLimit(3)

            HStack {
                Button("这次是误判") {
                    model.markLatestReminderAsMistake()
                }
                Button(model.isPaused ? "恢复检测" : "暂停 25 分钟") {
                    model.togglePause()
                }
            }

            if let latest = model.reminderHistory.first {
                Text("来自规则：\(latest.ruleID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("默认规则会在走神、低头、娱乐超时时触发。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320, height: 180, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
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

struct ReportCard: View {
    var summary: DailySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("今日报告", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(summary.summaryText)
                .font(.body)
            HStack(spacing: 18) {
                Text("总使用 \(FocusPetFormatters.duration(summary.totalActiveSeconds))")
                Text("娱乐 \(FocusPetFormatters.duration(summary.entertainmentSeconds))")
                Text("最长专注 \(FocusPetFormatters.duration(summary.longestFocusSeconds))")
                Text("提醒 \(summary.reminderCount) 次")
                Text("真实 \(summary.liveEventCount) · Demo \(summary.demoEventCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DemoControlsView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Demo 场景", systemImage: "play.circle.fill")
                .font(.headline)
            Text("点击任意场景会切换到 Demo 模式；这些事件会保存在结构化日志里，但不会计入真实日报指标。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("回到真实检测") { model.setRuntimeMode(.live) }
                Button("专注") { model.simulate(.focused) }
                Button("走神 30 秒") { model.simulate(.possiblyDistracted) }
                Button("低头 2 分钟") { model.simulate(.lookingDown) }
                Button("娱乐超时") { model.simulate(.entertainment) }
                Button("离开") { model.simulate(.away) }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EventTimelineView: View {
    var events: [StateEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("结构化状态事件", systemImage: "list.bullet.rectangle")
                .font(.headline)

            ForEach(events.suffix(8).reversed()) { event in
                HStack {
                    Image(systemName: event.userState.statusSymbolName)
                        .frame(width: 24)
                    Text(event.userState.title)
                        .frame(width: 100, alignment: .leading)
                    Text(event.sourceKind.title)
                        .frame(width: 70, alignment: .leading)
                        .foregroundStyle(event.sourceKind == .live ? .primary : .secondary)
                    Text(event.context.title)
                        .frame(width: 60, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(FocusPetFormatters.duration(event.durationSeconds))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(event.confidence * 100))%")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct RulesView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("规则")
                .font(.largeTitle.weight(.semibold))
            Text("V0 使用四条默认规则，规则由场景、状态、持续时间和提醒方式组成。")
                .foregroundStyle(.secondary)

            List {
                ForEach($model.rules) { $rule in
                    RuleRow(rule: $rule)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 420)
            .onChange(of: model.rules) { _, _ in
                model.saveRules()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RuleRow: View {
    @Binding var rule: FocusRule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: $rule.isEnabled) {
                    Text(rule.name)
                        .font(.headline)
                }
                Spacer()
                Text(rule.action.strength.title)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            Text(rule.action.message)
                .foregroundStyle(.secondary)

            HStack {
                StatusPill(title: "场景 \(rule.contexts.map(\.title).sorted().joined(separator: "、"))", symbol: "macwindow")
                StatusPill(title: "持续 \(Int(rule.durationSeconds)) 秒", symbol: "timer")
                StatusPill(title: "冷却 \(Int(rule.cooldownSeconds / 60)) 分钟", symbol: "snowflake")
            }
        }
        .padding(.vertical, 8)
    }
}

struct PetSettingsView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("桌宠")
                .font(.largeTitle.weight(.semibold))

            HStack(alignment: .top, spacing: 18) {
                PetPreviewCard()

                VStack(alignment: .leading, spacing: 16) {
                    Toggle("显示桌宠窗口", isOn: Binding(
                        get: { !model.petHidden },
                        set: { _ in model.togglePetVisibility() }
                    ))

                    Toggle("开启动画", isOn: $model.petAnimationEnabled)
                        .onChange(of: model.petAnimationEnabled) { _, _ in model.updatePetWindowAppearance() }
                    Toggle("提醒声音", isOn: $model.soundEnabled)
                        .onChange(of: model.soundEnabled) { _, _ in model.updatePetWindowAppearance() }

                    VStack(alignment: .leading) {
                        Text("透明度")
                        Slider(value: $model.petOpacity, in: 0.35...1.0) {
                            Text("透明度")
                        }
                        .onChange(of: model.petOpacity) { _, _ in model.updatePetWindowAppearance() }
                    }

                    VStack(alignment: .leading) {
                        Text("缩放")
                        Slider(value: $model.petScale, in: 0.72...1.34) {
                            Text("缩放")
                        }
                        .onChange(of: model.petScale) { _, _ in model.updatePetWindowAppearance() }
                    }

                    Text("桌宠窗口支持拖动、隐藏、缩放、透明度和关闭动画。")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PetPreviewCard: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(spacing: 16) {
            PetFigureView(state: model.currentState.userState, animated: model.petAnimationEnabled)
                .frame(width: 220, height: 220)
            Text(model.currentState.userState.title)
                .font(.title3.weight(.semibold))
            Text(model.lastReminderMessage)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 300)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PrivacyView: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("隐私")
                    .font(.largeTitle.weight(.semibold))

                HStack(alignment: .top, spacing: 14) {
                    PrivacyStatusCard()
                    LocalDataCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("隐私承诺", systemImage: "lock.shield.fill")
                        .font(.headline)
                    ForEach(model.privacyCommitments, id: \.self) { item in
                        Label(item, systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.primary)
                    }
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
            Label("权限状态", systemImage: "camera.fill")
                .font(.headline)
            Text(model.cameraStatusTitle)
                .font(.title3.weight(.semibold))
            Text("用于判断是否看向屏幕、是否低头、是否离开电脑。V0 不保存画面，只保存结构化状态。")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("运行模式：\(model.runtimeMode.title)")
                Text("视觉检测：\(model.faceDetectorStatus)")
                Text("最近帧：\(model.latestCameraFrameAt?.formatted(date: .omitted, time: .standard) ?? "暂无") · \(model.cameraFrameCount) 帧")
                Text("最近判断：\(model.recentStateDescription)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Button("请求摄像头权限") {
                    model.requestCameraPermission()
                }
                Button("辅助功能设置") {
                    model.openAccessibilitySettings()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LocalDataCard: View {
    @EnvironmentObject private var model: FocusPetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("本地数据", systemImage: "externaldrive.fill")
                .font(.headline)
            Text("\(model.localDataBytes) bytes")
                .font(.title3.weight(.semibold))
            Text("已保存：状态事件、默认规则、本日聚合、提醒记录。不保存视频、图片、人脸特征或屏幕内容。")
                .foregroundStyle(.secondary)
            Text(model.localDataStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

struct PetWindowView: View {
    @EnvironmentObject private var model: FocusPetModel
    @State private var lastDragTranslation = CGSize.zero

    var body: some View {
        VStack(spacing: 8) {
            PetFigureView(state: model.currentState.userState, animated: model.petAnimationEnabled)
                .frame(width: 140 * model.petScale, height: 140 * model.petScale)
            Text(model.lastReminderMessage)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .lineLimit(3)
                .frame(maxWidth: 190)
        }
        .padding(14)
        .opacity(model.petOpacity)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let delta = CGSize(
                        width: value.translation.width - lastDragTranslation.width,
                        height: value.translation.height - lastDragTranslation.height
                    )
                    PetWindowController.shared.moveBy(delta: delta)
                    lastDragTranslation = value.translation
                }
                .onEnded { _ in
                    lastDragTranslation = .zero
                }
        )
    }
}

struct PetFigureView: View {
    var state: UserState
    var animated: Bool
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(radialGradient)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

            VStack(spacing: 6) {
                HStack(spacing: 18) {
                    EyeView(closed: state == .away)
                    EyeView(closed: state == .away)
                }
                .padding(.top, 28)

                MouthView(state: state)
                    .frame(width: 44, height: 24)

                StateAccessoryView(state: state)
                    .frame(width: 54, height: 36)
            }

            if state == .lookingDown {
                Image(systemName: "arrow.up")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.orange)
                    .offset(y: -62)
            }
        }
        .scaleEffect(animated && breathe ? 1.03 : 0.98)
        .animation(animated ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .default, value: breathe)
        .onAppear { breathe = true }
    }

    private var radialGradient: RadialGradient {
        switch state {
        case .focused:
            RadialGradient(colors: [.mint, .teal], center: .topLeading, startRadius: 12, endRadius: 118)
        case .possiblyDistracted, .offScreen:
            RadialGradient(colors: [.yellow, .orange], center: .topLeading, startRadius: 12, endRadius: 118)
        case .lookingDown:
            RadialGradient(colors: [.orange, .red], center: .topLeading, startRadius: 12, endRadius: 118)
        case .away:
            RadialGradient(colors: [.gray, .black.opacity(0.65)], center: .topLeading, startRadius: 12, endRadius: 118)
        case .entertainment:
            RadialGradient(colors: [.pink, .purple], center: .topLeading, startRadius: 12, endRadius: 118)
        case .meeting:
            RadialGradient(colors: [.blue, .cyan], center: .topLeading, startRadius: 12, endRadius: 118)
        default:
            RadialGradient(colors: [.green, .blue], center: .topLeading, startRadius: 12, endRadius: 118)
        }
    }
}

struct EyeView: View {
    var closed: Bool

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 24, height: closed ? 4 : 24)
            .overlay {
                if !closed {
                    Circle()
                        .fill(.black)
                        .frame(width: 9, height: 9)
                }
            }
    }
}

struct MouthView: View {
    var state: UserState

    var body: some View {
        if state == .focused || state == .meeting {
            Capsule()
                .fill(.white.opacity(0.86))
                .frame(width: 28, height: 6)
        } else if state == .away {
            Text("zzz")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        } else {
            Circle()
                .stroke(.white, lineWidth: 4)
                .frame(width: 20, height: 20)
        }
    }
}

struct StateAccessoryView: View {
    var state: UserState

    var body: some View {
        Image(systemName: accessorySymbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
    }

    private var accessorySymbol: String {
        switch state {
        case .focused:
            "book.fill"
        case .possiblyDistracted, .offScreen:
            "hand.tap.fill"
        case .lookingDown:
            "figure.mind.and.body"
        case .away:
            "moon.zzz.fill"
        case .entertainment:
            "takeoutbag.and.cup.and.straw.fill"
        case .meeting:
            "video.fill"
        default:
            "sparkles"
        }
    }
}

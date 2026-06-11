import AppKit
import Combine
import FocusPetCore
import FocusPetRenderer
import FocusPetResources
import FocusPetStorage
import Foundation

@MainActor
final class FocusPetModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var currentSnapshot: ActivitySnapshot
    @Published var currentDecision: StateDecision
    @Published var stateSegments: [StateSegment]
    @Published var appUsage: [AppUsageSegment]
    @Published var focusSessions: [FocusSession]
    @Published var breakSessions: [BreakSession]
    @Published var nudges: [NudgeEvent]
    @Published var summary: DailySummary
    @Published var selectedTab: DashboardTab = .today
    @Published var rules: [ClassificationRule]
    @Published var statusMessage = "Focus Pet 已准备好。"
    @Published var exportURL: URL?
    @Published var availablePetPacks: [PetPackRecord] = []
    @Published var petImportMessage: String?
    @Published var petImportErrorMessage: String?
    @Published var petPreviewAction: PetAction = .idle

    private let store = LocalStore()
    private let engine = StateEngine()
    private let tracker = TimeTracker()
    private let nudgePolicy = NudgePolicy()
    private let behaviorPolicy = PetBehaviorPolicy()
    private let summaryBuilder = DailySummaryBuilder()
    private let foregroundMonitor = ForegroundAppMonitor()
    private let switchTracker = AppSwitchTracker()
    private let mouseScreenTracker = MouseScreenTracker()
    private let petLibrary = PetPackLibrary()
    private let petPanel = PetPanelController()
    private let notificationSender = SystemNotificationSender()
    private var timer: Timer?
    private var lastNudgeAt: [NudgeReason: Date] = [:]
    private var previousState: FocusState?
    private var candidateState: FocusState = .focus
    private var candidateSince = Date()
    private var stableStateSince = Date()
    private var isPetHovering = false
    private var transientPetMessage: String?
    private var transientPetMessageExpiresAt: Date?
    private var transientPetAction: PetAction?
    private var transientPetActionExpiresAt: Date?
    private var petAnimationIdentity: String?
    private var petAnimationStartedAt = Date()
    private var lastTickAt: Date?
    private var sleepStartedAt: Date?
    private var screenLockedStartedAt: Date?
    private var screenLockedRecordedUntil: Date?
    private var screenLockedStateBeforeLock: FocusState?
    private var sleepObserverTokens: [NSObjectProtocol] = []
    private var sessionObserverTokens: [NSObjectProtocol] = []
    private var mouseTimer: Timer?
    private var petScreenHint: ScreenPlacementHint?
    private var openDashboardRequest: (@MainActor (DashboardTab) -> Void)?

    init() {
        let now = Date()
        let snapshot = store.loadSnapshot()
        settings = snapshot.settings
        stateSegments = snapshot.stateSegments
        appUsage = snapshot.appUsage
        focusSessions = snapshot.focusSessions
        breakSessions = snapshot.breakSessions
        nudges = snapshot.nudges
        rules = snapshot.classificationRules.isEmpty ? ActivityClassifier.defaultRules : snapshot.classificationRules

        currentSnapshot = ActivitySnapshot(
            timestamp: now,
            appName: "Focus Pet",
            bundleID: "local.focuspet",
            windowTitle: nil,
            category: .work,
            idleSeconds: 0,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 0,
            isFocusSessionActive: false,
            isBreakActive: false
        )
        currentDecision = StateDecision(
            timestamp: now,
            state: .focus,
            category: .work,
            confidence: 0.6,
            reason: [.neutralDefault],
            stableDuration: 0
        )
        summary = summaryBuilder.summary(
            for: now,
            segments: snapshot.stateSegments,
            appUsage: snapshot.appUsage,
            focusSessions: snapshot.focusSessions,
            breakSessions: snapshot.breakSessions,
            nudges: snapshot.nudges
        )
        refreshPetPacks(saveIfChanged: false)
        configurePetPanelInteractions()
    }

    var activeFocusSession: FocusSession? {
        focusSessions.last { $0.status == .active }
    }

    var activeBreakSession: BreakSession? {
        breakSessions.last { $0.end == nil && !$0.completed }
    }

    var menuTitle: String {
        currentDecision.state.title
    }

    var menuSymbol: String {
        currentDecision.state.symbolName
    }

    var currentPetMessage: String? {
        let now = Date()
        if let transientPetMessage,
           let transientPetMessageExpiresAt,
           transientPetMessageExpiresAt > now {
            return transientPetMessage
        }

        guard settings.reminder.enablePetBubbles,
              let latest = nudges.last,
              now.timeIntervalSince(latest.time) <= 120 else {
            return nil
        }

        return latest.message
    }

    var petHoverMessage: String {
        if let rest = activeBreakSession {
            return "休息中 · 还剩 \(FocusPetFormatters.duration(rest.remainingSeconds()))"
        }
        return "需要休息一下吗？"
    }

    var petHoverDetails: [PetHoverContextItem] {
        [
            PetHoverContextItem(symbol: "cup.and.saucer.fill", title: "上次休息", value: lastBreakDistanceTitle),
            PetHoverContextItem(symbol: "checkmark.circle.fill", title: "今日专注", value: FocusPetFormatters.duration(summary.focusSeconds)),
            PetHoverContextItem(symbol: "eye.trianglebadge.exclamationmark", title: "今日走神", value: FocusPetFormatters.duration(summary.distractedSeconds)),
            PetHoverContextItem(symbol: "keyboard", title: "无输入", value: FocusPetFormatters.duration(Int(currentSnapshot.idleSeconds)))
        ]
    }

    var petHoverBreakButtonTitle: String {
        activeBreakSession == nil ? "休息 \(settings.breakMinutes) 分钟" : "结束休息"
    }

    private var lastBreakDistanceTitle: String {
        if activeBreakSession != nil {
            return "正在休息"
        }
        guard let end = breakSessions.compactMap(\.end).max() else {
            return "暂无"
        }
        return "\(FocusPetFormatters.duration(Int(Date().timeIntervalSince(end))))前"
    }

    var reminderPauseTitle: String {
        guard let pauseUntil = settings.reminder.pauseUntil, pauseUntil > Date() else {
            return "提醒未暂停"
        }
        return "暂停至 \(FocusPetFormatters.clock(pauseUntil))"
    }

    var recordingStatusTitle: String {
        settings.privacy.pauseActivityRecording ? "所有记录已暂停" : "正在记录本地统计"
    }

    func start() {
        guard timer == nil else { return }
        configureSystemSleepObservers()
        configureSessionActivityObservers()
        advanceStateTick()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStateTick()
            }
        }
        timer?.tolerance = 1
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.trackMouseScreen()
                self?.refreshLivePetPresentationIfNeeded()
            }
        }
        mouseTimer?.tolerance = 0.25
        if !settings.pet.hidden {
            petPanel.show()
        }
        if settings.reminder.enableSystemNotifications {
            notificationSender.requestAuthorization()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        mouseTimer?.invalidate()
        mouseTimer = nil
        save()
    }

    func advanceStateTick() {
        let now = Date()
        let elapsedSinceLastTick = lastTickAt.map { now.timeIntervalSince($0) }
        lastTickAt = now
        closeExpiredBreakIfNeeded(now: now)

        let session = SessionActivityMonitor.snapshot()
        if session.isScreenLocked {
            applyScreenLockedSnapshot(now: now)
            return
        }

        let front = foregroundMonitor.snapshot()
        let sanitizedTitle = settings.privacy.sanitize(front.windowTitle)
        let category = ActivityClassifier(rules: rules).classify(
            appName: front.appName,
            bundleID: front.bundleID,
            windowTitle: front.windowTitle
        )
        let identity = "\(front.bundleID ?? "")|\(front.appName)"
        switchTracker.update(identity: identity, category: category, now: now)

        let snapshot = ActivitySnapshot(
            timestamp: now,
            appName: front.appName,
            bundleID: front.bundleID,
            windowTitle: settings.privacy.storeRawTitle && !settings.privacy.storeOnlyCategoryResult ? front.windowTitle : nil,
            titleHash: sanitizedTitle.titleHash,
            titleStored: sanitizedTitle.titleStored,
            titleDisplay: sanitizedTitle.titleDisplay,
            category: category,
            idleSeconds: IdleMonitor.idleSeconds(),
            switchCountLast5Min: switchTracker.switchCount(seconds: 5 * 60, now: now),
            switchCountLast15Min: switchTracker.switchCount(seconds: 15 * 60, now: now),
            activeCategoryDuration: switchTracker.activeCategoryDuration(now: now),
            activeAppDuration: switchTracker.activeAppDuration(now: now),
            isFocusSessionActive: activeFocusSession != nil,
            isBreakActive: activeBreakSession != nil,
            isScreenLocked: session.isScreenLocked
        )

        let stateBeforeTick = currentDecision.state
        let rawDecision = engine.evaluate(snapshot, previousStableState: currentDecision.state)
        let decision = stabilized(rawDecision, now: now)
        currentSnapshot = snapshot
        currentDecision = decision

        if settings.privacy.pauseActivityRecording {
            statusMessage = "所有本地记录已暂停。"
            updatePet()
            return
        }

        let tickSeconds = min(max(tracker.tickSeconds, elapsedSinceLastTick ?? tracker.tickSeconds), 60)
        let tickTracker = TimeTracker(tickSeconds: tickSeconds)
        stateSegments = tickTracker.record(decision: decision, snapshot: snapshot, segments: stateSegments)
        appUsage = decision.state == .away ? appUsage : tickTracker.recordAppUsage(snapshot: snapshot, appUsage: appUsage)
        applySessionAccounting(decision: decision, previousTickState: stateBeforeTick, tickSeconds: tickSeconds)
        triggerNudgeIfNeeded(decision: decision, snapshot: snapshot, now: now)
        refreshSummary()
        save()
        updatePet()
    }

    func startFocusSession(taskName: String, minutes: Int) {
        finishActiveBreak(cancelled: true)
        if let activeFocusSession {
            finishFocusSession(activeFocusSession, status: .completed)
        }
        focusSessions.append(FocusSession(
            taskName: taskName,
            start: Date(),
            targetDurationSeconds: max(1, minutes) * 60,
            autoStartBreak: settings.autoStartBreak,
            breakDurationSeconds: settings.breakMinutes * 60
        ))
        statusMessage = "已开始专注：\(taskName)"
        save()
        updatePet()
    }

    func finishCurrentFocusSession(completed: Bool = true) {
        guard let active = activeFocusSession else { return }
        finishFocusSession(active, status: completed ? .completed : .cancelled)
        if completed && settings.autoStartBreak {
            startBreak(minutes: settings.breakMinutes, source: .afterFocusSession)
        } else {
            updatePet()
        }
    }

    func startBreak(minutes: Int, source: BreakSource = .manual) {
        if let activeBreakSession, activeBreakSession.end == nil {
            return
        }
        let now = Date()
        if let activeFocusSession {
            finishFocusSession(activeFocusSession, status: .completed)
        }
        breakSessions.append(BreakSession(
            start: now,
            targetDurationSeconds: max(1, minutes) * 60,
            source: source
        ))
        statusMessage = "休息开始。"
        applyImmediateBreakDecision(now: now)
        refreshSummary()
        save()
        updatePet()
    }

    func toggleBreakFromPet() {
        if activeBreakSession != nil {
            endCurrentBreak()
        } else {
            startBreak(minutes: settings.breakMinutes)
            showTransientPetMessage("休息 \(settings.breakMinutes) 分钟，我会提醒你回来。", seconds: 5)
        }
    }

    func pauseReminders(minutes: Int = 30) {
        settings.reminder.pauseUntil = Date().addingTimeInterval(Double(max(1, minutes)) * 60)
        statusMessage = "提醒已暂停 \(minutes) 分钟。"
        save()
        showTransientPetMessage("提醒已暂停到 \(FocusPetFormatters.clock(settings.reminder.pauseUntil ?? Date()))", seconds: 4)
    }

    func resumeReminders() {
        settings.reminder.pauseUntil = nil
        statusMessage = "提醒已恢复。"
        save()
        showTransientPetMessage("提醒已恢复。", seconds: 4)
    }

    func endCurrentBreak() {
        finishActiveBreak(cancelled: false)
    }

    func togglePetHidden() {
        settings.pet.hidden.toggle()
        if settings.pet.hidden {
            petPanel.hide()
        } else {
            petPanel.show()
        }
        save()
        updatePet()
    }

    func setPetPlacement(_ placement: PetPlacementMode) {
        settings.pet.placement = placement
        if placement != .custom {
            settings.pet.customOriginX = nil
            settings.pet.customOriginY = nil
        }
        statusMessage = "桌宠位置已设为 \(placement.title)。"
        save()
        updatePet()
    }

    func setPetHovering(_ isHovering: Bool) {
        guard isPetHovering != isHovering else { return }
        isPetHovering = isHovering
        updatePet()
    }

    func showPetStatusBubble() {
        let idleText = FocusPetFormatters.duration(Int(currentSnapshot.idleSeconds))
        showTransientPetMessage("\(currentDecision.state.title) · \(currentSnapshot.appName) · 空闲 \(idleText)", seconds: 6)
    }

    func openDashboard(tab: DashboardTab = .today) {
        selectedTab = tab

        if bringDashboardWindowToFront() {
            return
        }

        if let openDashboardRequest {
            openDashboardRequest(tab)
        } else {
            NotificationCenter.default.post(name: .focusPetOpenDashboardRequested, object: tab)
        }

        Task { @MainActor in
            await Task.yield()
            self.bringDashboardWindowToFront()
        }
    }

    @discardableResult
    func bringDashboardWindowToFront() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if let dashboardWindow = NSApp.windows.first(where: { $0.title == "Focus Pet" || $0.identifier?.rawValue == "dashboard" }) {
            dashboardWindow.makeKeyAndOrderFront(nil)
            return true
        }
        return false
    }

    func registerOpenDashboardRequest(_ request: @escaping @MainActor (DashboardTab) -> Void) {
        openDashboardRequest = request
    }

    func handlePetDragBegan() {
        transientPetAction = .dragged
        transientPetActionExpiresAt = nil
        petAnimationIdentity = nil
        updatePet()
    }

    func handlePetDragEnded(origin: CGPoint) {
        settings.pet.placement = .custom
        settings.pet.customOriginX = origin.x
        settings.pet.customOriginY = origin.y
        transientPetAction = .landing
        transientPetActionExpiresAt = Date().addingTimeInterval(1.5)
        petAnimationIdentity = nil
        statusMessage = "桌宠位置已保存为自定义。"
        save()
        showTransientPetMessage("放在这里。", seconds: 3)
        clearTransientPetAction(after: 1.6)
    }

    func deleteAllData() {
        store.deleteAll()
        stateSegments = []
        appUsage = []
        focusSessions = []
        breakSessions = []
        nudges = []
        summary = summaryBuilder.summary(for: Date(), segments: [], appUsage: [], focusSessions: [], breakSessions: [], nudges: [])
        statusMessage = "本地数据已清空。"
        save()
    }

    func exportData(redacted: Bool = false) {
        exportURL = store.exportSnapshot(snapshot(), redacted: redacted)
        if exportURL == nil {
            statusMessage = "导出失败。"
        } else {
            statusMessage = redacted ? "已导出脱敏统计。" : "已导出本地统计。"
        }
    }

    func saveSettings() {
        if settings.privacy.storeOnlyCategoryResult {
            settings.privacy.storeRawTitle = false
        }
        save()
        if settings.reminder.enableSystemNotifications {
            notificationSender.requestAuthorization()
        }
        updatePet()
    }

    func refreshPetPacks(saveIfChanged: Bool = true) {
        availablePetPacks = PetPackCatalog().availablePacks(userRootURL: petLibrary.installRootURL)
        guard !availablePetPacks.isEmpty else { return }

        if !availablePetPacks.contains(where: { $0.id == settings.pet.selectedPackID }),
           let first = availablePetPacks.first {
            settings.pet.selectedPackID = first.id
            if saveIfChanged {
                save()
            }
        }
    }

    func chooseAndImportPetPack() {
        let panel = NSOpenPanel()
        panel.title = "导入 Focus Pet 资源包"
        panel.message = "选择包含 pet.json 的文件夹，或直接选择 pet.json。"
        panel.prompt = "导入"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPetPack(from: url)
    }

    func importPetPack(from url: URL) {
        do {
            let imported = try petLibrary.importPack(from: url)
            refreshPetPacks(saveIfChanged: false)
            settings.pet.selectedPackID = imported.record.id
            petImportMessage = "已导入：\(imported.record.pack.name)"
            petImportErrorMessage = nil
            statusMessage = "资源包已导入。"
            save()
            updatePet()
        } catch {
            petImportMessage = nil
            petImportErrorMessage = error.localizedDescription
            statusMessage = "资源包导入失败。"
        }
    }

    func previewPetAction(_ action: PetAction) {
        petPreviewAction = action
        transientPetAction = action
        transientPetActionExpiresAt = Date().addingTimeInterval(3)
        petAnimationIdentity = nil
        showTransientPetMessage("预览动作：\(action.title)", seconds: 3)
        clearTransientPetAction(after: 3)
    }

    func addRule(pattern: String, matchKind: RuleMatchKind, category: ActivityCategory) {
        let cleaned = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        rules.append(ClassificationRule(
            matchKind: matchKind,
            pattern: cleaned,
            category: category,
            priority: 200
        ))
        statusMessage = "规则已添加。"
        save()
    }

    func categoryForRule(pattern: String, matchKind: RuleMatchKind) -> ActivityCategory? {
        let cleaned = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        return rules
            .filter { rule in
                rule.matchKind == matchKind
                    && rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                        .localizedCaseInsensitiveCompare(cleaned) == .orderedSame
            }
            .sorted { $0.priority > $1.priority }
            .first?
            .category
    }

    func setRule(pattern: String, matchKind: RuleMatchKind, category: ActivityCategory) {
        let cleaned = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        rules.removeAll { rule in
            rule.matchKind == matchKind
                && rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(cleaned) == .orderedSame
        }
        rules.append(ClassificationRule(
            matchKind: matchKind,
            pattern: cleaned,
            category: category,
            priority: 240
        ))
        statusMessage = "\(cleaned) 已设为\(category.title)。"
        save()
    }

    func deleteRule(_ rule: ClassificationRule) {
        rules.removeAll { $0.id == rule.id }
        if rules.isEmpty {
            rules = ActivityClassifier.defaultRules
        }
        statusMessage = "规则已删除。"
        save()
    }

    private func stabilized(_ decision: StateDecision, now: Date) -> StateDecision {
        if shouldApplyImmediately(decision) || (currentDecision.state == .breakTime && decision.state != .breakTime) {
            if decision.state != currentDecision.state {
                previousState = currentDecision.state
            }
            candidateState = decision.state
            candidateSince = now
            stableStateSince = now.addingTimeInterval(-decision.stableDuration)
            return decision
        }

        if decision.state != candidateState {
            candidateState = decision.state
            candidateSince = now
        }

        guard decision.state != currentDecision.state else {
            return decisionWithStableDuration(decision, since: stableStateSince, now: now)
        }

        if now.timeIntervalSince(candidateSince) >= StateEngineThresholds().uiStabilitySeconds {
            previousState = currentDecision.state
            stableStateSince = candidateSince
            return decisionWithStableDuration(decision, since: stableStateSince, now: now)
        }

        return StateDecision(
            timestamp: decision.timestamp,
            state: currentDecision.state,
            category: decision.category,
            confidence: max(0.4, decision.confidence - 0.2),
            reason: [.previousStateHeld],
            stableDuration: now.timeIntervalSince(stableStateSince)
        )
    }

    private func shouldApplyImmediately(_ decision: StateDecision) -> Bool {
        decision.reason.contains(.inputIdleDistracted)
            || decision.reason.contains(.systemSleep)
            || decision.reason.contains(.screenLocked)
            || decision.reason.contains(.longInputIdleAway)
            || decision.reason.contains(.activeBreak)
    }

    private func decisionWithStableDuration(_ decision: StateDecision, since: Date, now: Date) -> StateDecision {
        StateDecision(
            timestamp: decision.timestamp,
            state: decision.state,
            category: decision.category,
            confidence: decision.confidence,
            reason: decision.reason,
            stableDuration: now.timeIntervalSince(since)
        )
    }

    private func triggerNudgeIfNeeded(decision: StateDecision, snapshot: ActivitySnapshot, now: Date) {
        if let pauseUntil = settings.reminder.pauseUntil {
            if pauseUntil > now {
                return
            }
            settings.reminder.pauseUntil = nil
        }

        guard settings.reminder.enablePetBubbles || settings.reminder.enableSystemNotifications else {
            return
        }

        let state = FocusStateSnapshot(
            timestamp: now,
            state: decision.state,
            category: decision.category,
            stableDuration: decision.stableDuration,
            appName: snapshot.appName,
            bundleID: snapshot.bundleID,
            reason: decision.reason
        )
        guard let event = nudgePolicy.nudge(
            for: state,
            previousState: previousState,
            now: now,
            lastTriggeredAt: lastNudgeAt
        ) else { return }

        recordNudge(event)
        lastNudgeAt[event.reason] = event.time
    }

    private func applySessionAccounting(decision: StateDecision, previousTickState: FocusState, tickSeconds: TimeInterval) {
        guard let activeIndex = focusSessions.lastIndex(where: { $0.status == .active }) else { return }
        let seconds = max(1, Int(tickSeconds.rounded()))
        switch decision.state {
        case .focus:
            focusSessions[activeIndex].effectiveFocusSeconds += seconds
        case .distracted:
            focusSessions[activeIndex].distractedSeconds += seconds
        case .away:
            focusSessions[activeIndex].awaySeconds += seconds
        case .breakTime:
            break
        }
        if previousTickState == .focus && (decision.state == .distracted || decision.state == .away) {
            focusSessions[activeIndex].interruptionCount += 1
        }
        focusSessions[activeIndex].switchCount = max(focusSessions[activeIndex].switchCount, currentSnapshot.switchCountLast15Min)
        focusSessions[activeIndex].mainAppName = dominantAppName(during: focusSessions[activeIndex])
    }

    private func dominantAppName(during session: FocusSession) -> String? {
        let end = session.end ?? Date()
        var secondsByApp: [String: Int] = [:]

        for usage in appUsage where usage.end > session.start && usage.start < end {
            let start = max(usage.start, session.start)
            let clippedEnd = min(usage.end, end)
            let seconds = max(0, Int(clippedEnd.timeIntervalSince(start)))
            guard seconds > 0 else { continue }
            secondsByApp[usage.appName, default: 0] += seconds
        }

        if let dominant = secondsByApp.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) {
            return dominant.key
        }

        return currentSnapshot.appName
    }

    private func finishFocusSession(_ session: FocusSession, status: FocusSessionStatus) {
        guard let index = focusSessions.firstIndex(where: { $0.id == session.id }) else { return }
        focusSessions[index].end = Date()
        focusSessions[index].status = status
        focusSessions[index].completed = status == .completed
        statusMessage = status == .completed ? "专注会话已完成。" : "专注会话已取消。"
        save()
    }

    private func configureSystemSleepObservers() {
        guard sleepObserverTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObserverTokens.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemWillSleep()
            }
        })
        sleepObserverTokens.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSystemDidWake()
            }
        })
    }

    private func configureSessionActivityObservers() {
        guard sessionObserverTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionObserverTokens.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenDidLock()
            }
        })
        sessionObserverTokens.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenDidUnlock()
            }
        })
        sessionObserverTokens.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenDidLock()
            }
        })
        sessionObserverTokens.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenDidUnlock()
            }
        })
    }

    private func handleScreenDidLock() {
        let now = Date()
        if screenLockedStartedAt == nil {
            screenLockedStartedAt = now
            screenLockedRecordedUntil = now
            screenLockedStateBeforeLock = currentDecision.state
        }
        applyScreenLockedSnapshot(now: now)
        statusMessage = "屏幕已锁定，暂离计时开始。"
        save()
    }

    private func handleScreenDidUnlock() {
        let now = Date()
        if let start = screenLockedStartedAt {
            recordAwayInterval(
                start: screenLockedRecordedUntil ?? start,
                end: now,
                appName: "Locked Screen",
                source: [.screenLock]
            )
        }
        screenLockedStartedAt = nil
        screenLockedRecordedUntil = nil
        screenLockedStateBeforeLock = nil
        lastTickAt = now
        statusMessage = "屏幕已解锁，回到活跃判断。"
        showTransientPetMessage("欢迎回来。", seconds: 4)
        advanceStateTick()
    }

    private func applyScreenLockedSnapshot(now: Date) {
        if screenLockedStartedAt == nil {
            screenLockedStartedAt = now
            screenLockedRecordedUntil = now
            screenLockedStateBeforeLock = currentDecision.state
        }
        let snapshot = ActivitySnapshot(
            timestamp: now,
            appName: "Locked Screen",
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: IdleMonitor.idleSeconds(),
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: screenLockedStartedAt.map { now.timeIntervalSince($0) } ?? 0,
            activeAppDuration: 0,
            isFocusSessionActive: activeFocusSession != nil,
            isBreakActive: activeBreakSession != nil,
            isScreenLocked: true,
            source: [.screenLock, .idleTime]
        )
        let previous = currentDecision.state
        currentSnapshot = snapshot
        currentDecision = engine.evaluate(snapshot, previousStableState: previous)
        if previous != currentDecision.state {
            previousState = previous
            candidateState = currentDecision.state
            candidateSince = now
            stableStateSince = screenLockedStartedAt ?? now
        }

        guard !settings.privacy.pauseActivityRecording else {
            statusMessage = "所有本地记录已暂停。"
            updatePet()
            return
        }

        if let recordedUntil = screenLockedRecordedUntil {
            let tickSeconds = max(0, now.timeIntervalSince(recordedUntil))
            if tickSeconds >= 1 {
                stateSegments = TimeTracker(tickSeconds: tickSeconds).record(
                    decision: currentDecision,
                    snapshot: snapshot,
                    segments: stateSegments
                )
                applySessionAccounting(
                    decision: currentDecision,
                    previousTickState: screenLockedStateBeforeLock ?? previous,
                    tickSeconds: tickSeconds
                )
                screenLockedStateBeforeLock = nil
                screenLockedRecordedUntil = now
            }
        } else {
            screenLockedRecordedUntil = now
        }
        refreshSummary()
        save()
        updatePet()
    }

    private func handleSystemWillSleep() {
        let now = Date()
        if let lockedStart = screenLockedStartedAt {
            recordAwayInterval(
                start: screenLockedRecordedUntil ?? lockedStart,
                end: now,
                appName: "Locked Screen",
                source: [.screenLock]
            )
            screenLockedStartedAt = nil
            screenLockedRecordedUntil = nil
            screenLockedStateBeforeLock = nil
        }
        sleepStartedAt = now
        let snapshot = ActivitySnapshot(
            timestamp: now,
            appName: "Sleep",
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: 0,
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: 0,
            isFocusSessionActive: activeFocusSession != nil,
            isBreakActive: activeBreakSession != nil,
            isSystemSleeping: true,
            source: [.systemSleep]
        )
        currentSnapshot = snapshot
        currentDecision = engine.evaluate(snapshot, previousStableState: currentDecision.state)
        statusMessage = "电脑即将睡眠，暂离计时开始。"
        updatePet()
        save()
    }

    private func handleSystemDidWake() {
        let now = Date()
        let start = sleepStartedAt ?? lastTickAt ?? now
        sleepStartedAt = nil
        recordSystemSleepInterval(start: start, end: now)
        lastTickAt = now
        statusMessage = "电脑已唤醒，回到活跃判断。"
        showTransientPetMessage("欢迎回来。", seconds: 4)
        advanceStateTick()
    }

    private func recordSystemSleepInterval(start: Date, end: Date) {
        recordAwayInterval(start: start, end: end, appName: "Sleep", source: [.systemSleep])
    }

    private func recordAwayInterval(start: Date, end: Date, appName: String, source: Set<ActivitySignalSource>) {
        guard end.timeIntervalSince(start) >= 5 else { return }
        let awaySnapshot = ActivitySnapshot(
            timestamp: end,
            appName: appName,
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: end.timeIntervalSince(start),
            switchCountLast5Min: 0,
            switchCountLast15Min: 0,
            activeCategoryDuration: end.timeIntervalSince(start),
            isFocusSessionActive: activeFocusSession != nil,
            isBreakActive: activeBreakSession != nil,
            isSystemSleeping: source.contains(.systemSleep),
            isScreenLocked: source.contains(.screenLock),
            source: source
        )
        let awayDecision = engine.evaluate(awaySnapshot, previousStableState: currentDecision.state)
        stateSegments = TimeTracker(tickSeconds: end.timeIntervalSince(start)).record(
            decision: awayDecision,
            snapshot: awaySnapshot,
            segments: stateSegments
        )
        if let activeIndex = focusSessions.lastIndex(where: { $0.status == .active }) {
            focusSessions[activeIndex].awaySeconds += max(0, Int(end.timeIntervalSince(start).rounded()))
        }
        currentSnapshot = awaySnapshot
        currentDecision = awayDecision
        refreshSummary()
        save()
    }

    private func trackMouseScreen() {
        guard !settings.pet.hidden else { return }
        guard let hint = mouseScreenTracker.update() else { return }
        let hadScreenHint = petScreenHint != nil
        let previousHint = petScreenHint
        petScreenHint = hint
        guard hadScreenHint else {
            updatePet()
            return
        }
        if settings.pet.placement == .custom {
            remapCustomPetOrigin(from: previousHint, to: hint)
            save()
        }
        transientPetAction = .screenTransfer
        transientPetActionExpiresAt = Date().addingTimeInterval(1.6)
        petAnimationIdentity = nil
        showTransientPetMessage("我切到这块屏幕。", seconds: 2)
        clearTransientPetAction(after: 1.7)
    }

    private func closeExpiredBreakIfNeeded(now: Date) {
        guard let index = breakSessions.lastIndex(where: { $0.end == nil && !$0.completed }) else { return }
        if breakSessions[index].remainingSeconds(now: now) == 0 {
            breakSessions[index].end = now
            breakSessions[index].completed = true
            transientPetAction = .mouseSummon
            transientPetActionExpiresAt = now.addingTimeInterval(6)
            petAnimationIdentity = nil
            recordNudge(NudgeEvent(
                time: now,
                reason: .breakEnding,
                state: .breakTime,
                appName: "Break",
                category: .ignore,
                petAction: .breakEnd,
                cooldownSeconds: 0,
                message: "休息时间结束啦。"
            ))
            petPanel.summonNearMouse(duration: 12)
            showTransientPetMessage("休息结束，回来工作啦。", seconds: 6)
            statusMessage = "休息结束。"
            refreshSummary()
            save()
            updatePet()
        }
    }

    private func finishActiveBreak(cancelled: Bool) {
        let now = Date()
        guard let index = breakSessions.lastIndex(where: { $0.end == nil && !$0.completed }) else { return }
        breakSessions[index].end = now
        breakSessions[index].completed = !cancelled
        statusMessage = cancelled ? "休息已结束。" : "休息完成。"
        save()
        advanceStateTick()
    }

    private func refreshLivePetPresentationIfNeeded() {
        if activeBreakSession != nil || isPetHovering {
            refreshSummary()
            updatePet()
        }
    }

    private func applyImmediateBreakDecision(now: Date) {
        let previous = currentDecision.state
        let snapshot = ActivitySnapshot(
            timestamp: now,
            appName: "Break",
            bundleID: nil,
            windowTitle: nil,
            category: .ignore,
            idleSeconds: IdleMonitor.idleSeconds(),
            switchCountLast5Min: currentSnapshot.switchCountLast5Min,
            switchCountLast15Min: currentSnapshot.switchCountLast15Min,
            activeCategoryDuration: 0,
            activeAppDuration: 0,
            isFocusSessionActive: activeFocusSession != nil,
            isBreakActive: true,
            source: [.breakSession]
        )
        currentSnapshot = snapshot
        currentDecision = engine.evaluate(snapshot, previousStableState: previous)
        previousState = previous == .breakTime ? previousState : previous
        candidateState = .breakTime
        candidateSince = now
        stableStateSince = now
        petAnimationIdentity = nil
    }

    private func remapCustomPetOrigin(from previousHint: ScreenPlacementHint?, to nextHint: ScreenPlacementHint) {
        let panelSize = currentPetPanelSize()
        let previousVisible = previousHint?.visibleFrame
            ?? visibleFrameContainingCustomOrigin()
            ?? nextHint.visibleFrame
        let nextVisible = nextHint.visibleFrame
        let currentOrigin = CGPoint(
            x: settings.pet.customOriginX ?? previousVisible.maxX - panelSize.width - 24,
            y: settings.pet.customOriginY ?? previousVisible.minY + 24
        )
        let xRatio = normalizedPosition(
            value: currentOrigin.x,
            lower: previousVisible.minX,
            upper: previousVisible.maxX - panelSize.width
        )
        let yRatio = normalizedPosition(
            value: currentOrigin.y,
            lower: previousVisible.minY,
            upper: previousVisible.maxY - panelSize.height
        )
        settings.pet.customOriginX = mappedPosition(
            ratio: xRatio,
            lower: nextVisible.minX,
            upper: nextVisible.maxX - panelSize.width
        )
        settings.pet.customOriginY = mappedPosition(
            ratio: yRatio,
            lower: nextVisible.minY,
            upper: nextVisible.maxY - panelSize.height
        )
    }

    private func currentPetPanelSize() -> CGSize {
        let size = CGFloat(settings.pet.size)
        return CGSize(width: max(size, min(280, size + 110)), height: size + 128)
    }

    private func visibleFrameContainingCustomOrigin() -> CGRect? {
        guard let x = settings.pet.customOriginX,
              let y = settings.pet.customOriginY else {
            return nil
        }
        let origin = CGPoint(x: x, y: y)
        return NSScreen.screens.first { $0.frame.contains(origin) }?.visibleFrame
    }

    private func normalizedPosition(value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper > lower else { return 0.5 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }

    private func mappedPosition(ratio: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper > lower else { return lower }
        return lower + ratio * (upper - lower)
    }

    private func refreshSummary() {
        let pruned = DataRetentionManager().prune(
            now: Date(),
            settings: settings.retention,
            stateSegments: stateSegments,
            appUsage: appUsage,
            focusSessions: focusSessions,
            breakSessions: breakSessions,
            nudges: nudges
        )
        stateSegments = pruned.stateSegments
        appUsage = pruned.appUsage
        focusSessions = pruned.focusSessions
        breakSessions = pruned.breakSessions
        nudges = pruned.nudges
        summary = summaryBuilder.summary(
            for: Date(),
            segments: stateSegments,
            appUsage: appUsage,
            focusSessions: focusSessions,
            breakSessions: breakSessions,
            nudges: nudges
        )
    }

    private func updatePet() {
        guard !settings.pet.hidden else {
            petPanel.hide()
            return
        }
        if availablePetPacks.isEmpty {
            refreshPetPacks(saveIfChanged: false)
        }
        let selectedRecord = availablePetPacks.first { $0.id == settings.pet.selectedPackID }
            ?? availablePetPacks.first
            ?? PetPackRecord(pack: PetPackCatalog.fallbackPack, rootURL: nil, isBundled: true)
        let now = Date()
        let policyAction = behaviorPolicy.action(
            for: currentDecision.state,
            previousState: previousState,
            latestNudge: nudges.last,
            now: now
        )
        let transientAction = currentTransientAction()
        let baseAction = transientAction ?? policyAction
        let action = baseAction
        let hoverAction = hoverAction(for: baseAction)
        let resolvedAction = PetActionResolver().animationKey(for: action, in: selectedRecord.pack) ?? .idle
        let resolvedHoverAction = PetActionResolver().animationKey(for: hoverAction, in: selectedRecord.pack) ?? resolvedAction
        let animation = selectedRecord.pack.animations[resolvedAction]
        let hoverAnimation = selectedRecord.pack.animations[resolvedHoverAction]
        let nextAnimationIdentity = [
            selectedRecord.id,
            action.rawValue,
            hoverAction.rawValue,
            resolvedAction.rawValue,
            resolvedHoverAction.rawValue
        ].joined(separator: "|")
        if petAnimationIdentity != nextAnimationIdentity {
            petAnimationIdentity = nextAnimationIdentity
            petAnimationStartedAt = now
        }
        petPanel.update(PetRenderState(
            focusState: currentDecision.state,
            action: action,
            message: currentPetMessage,
            hoverMessage: petHoverMessage,
            hoverStatusEnabled: settings.pet.hoverStatusEnabled,
            hoverDetails: petHoverDetails,
            hoverBreakButtonTitle: petHoverBreakButtonTitle,
            breakEndsAt: activeBreakSession.map { $0.start.addingTimeInterval(Double($0.targetDurationSeconds)) },
            size: settings.pet.size,
            opacity: settings.pet.opacity,
            animationEnabled: settings.pet.animationEnabled,
            packName: selectedRecord.pack.name,
            placement: settings.pet.placement,
            customOriginX: settings.pet.customOriginX,
            customOriginY: settings.pet.customOriginY,
            frameURLs: selectedRecord.frameURLs(for: resolvedAction),
            framesPerSecond: animation?.fps ?? 8,
            loops: animation?.loop ?? true,
            hoverAction: hoverAction,
            hoverFrameURLs: selectedRecord.frameURLs(for: resolvedHoverAction),
            hoverFramesPerSecond: hoverAnimation?.fps ?? 8,
            hoverLoops: hoverAnimation?.loop ?? false,
            animationStartedAt: petAnimationStartedAt,
            screenHint: petScreenHint.map {
                PetScreenHint(screenFrame: $0.screenFrame, visibleFrame: $0.visibleFrame)
            }
        ))
        petPanel.show()
    }

    private func save() {
        store.saveSnapshot(snapshot())
    }

    private func recordNudge(_ event: NudgeEvent) {
        nudges.append(event)
        if nudges.count > 200 {
            nudges.removeFirst(nudges.count - 200)
        }
        if settings.reminder.enableSystemNotifications,
           settings.reminder.pauseUntil.map({ $0 <= Date() }) ?? true {
            notificationSender.deliver(event)
        }
    }

    private func snapshot() -> LocalStoreSnapshot {
        LocalStoreSnapshot(
            settings: settings,
            classificationRules: rules,
            stateSegments: stateSegments,
            appUsage: appUsage,
            focusSessions: focusSessions,
            breakSessions: breakSessions,
            nudges: nudges
        )
    }

    private func configurePetPanelInteractions() {
        petPanel.setInteractions(PetPanelInteractions(
            showStatusBubble: { [weak self] in self?.showPetStatusBubble() },
            openDashboard: { [weak self] in self?.openDashboard(tab: .today) },
            openSettings: { [weak self] in self?.openDashboard(tab: .settings) },
            startBreak: { [weak self] in self?.toggleBreakFromPet() },
            pauseReminders: { [weak self] in self?.pauseReminders() },
            setHovering: { [weak self] in self?.setPetHovering($0) },
            toggleHidden: { [weak self] in self?.togglePetHidden() },
            setPlacement: { [weak self] placement in self?.setPetPlacement(placement) },
            dragBegan: { [weak self] in self?.handlePetDragBegan() },
            dragEnded: { [weak self] origin in self?.handlePetDragEnded(origin: origin) }
        ))
    }

    private func showTransientPetMessage(_ message: String, seconds: TimeInterval) {
        let expiresAt = Date().addingTimeInterval(seconds)
        transientPetMessage = message
        transientPetMessageExpiresAt = expiresAt
        updatePet()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if self.transientPetMessageExpiresAt == expiresAt {
                self.transientPetMessage = nil
                self.transientPetMessageExpiresAt = nil
                self.updatePet()
            }
        }
    }

    private func currentTransientAction() -> PetAction? {
        guard let transientPetAction else { return nil }
        if let transientPetActionExpiresAt, transientPetActionExpiresAt <= Date() {
            self.transientPetAction = nil
            self.transientPetActionExpiresAt = nil
            return nil
        }
        return transientPetAction
    }

    private func hoverAction(for action: PetAction) -> PetAction {
        switch action {
        case .sleep, .breakRelax, .breakEnd:
            return .breath
        default:
            return .welcomeBack
        }
    }

    private func reasonTitle(_ reason: StateReason) -> String {
        switch reason {
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

    private func clearTransientPetAction(after seconds: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self.transientPetAction = nil
            self.transientPetActionExpiresAt = nil
            self.updatePet()
        }
    }
}

extension Notification.Name {
    static let focusPetOpenDashboardRequested = Notification.Name("FocusPetOpenDashboardRequested")
}

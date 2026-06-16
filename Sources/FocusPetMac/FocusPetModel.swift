import AppKit
import Combine
import FocusPetCore
import FocusPetRenderer
import FocusPetResources
import FocusPetStorage
import Foundation

struct RecognitionDiagnosticSnapshot: Equatable {
    var sampledAt: Date
    var appName: String
    var bundleID: String?
    var windowTitle: String?
    var category: ActivityCategory
    var catalogEntryCount: Int
    var defaultRuleCount: Int
    var userRuleCount: Int
    var screenRecordingStatus: String
    var inputMonitoringStatus: String
    var accessibilityStatus: String
    var recordingPaused: Bool

    var catalogStatus: String {
        catalogEntryCount >= 20 ? "目录已加载" : "仅使用兜底规则"
    }

    var windowTitleStatus: String {
        if let windowTitle, !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "已读取"
        }
        return "未读取到"
    }

    static let pending = RecognitionDiagnosticSnapshot(
        sampledAt: Date(timeIntervalSince1970: 0),
        appName: "等待刷新",
        bundleID: nil,
        windowTitle: nil,
        category: .ignore,
        catalogEntryCount: 0,
        defaultRuleCount: 0,
        userRuleCount: 0,
        screenRecordingStatus: "检查中",
        inputMonitoringStatus: "检查中",
        accessibilityStatus: "检查中",
        recordingPaused: false
    )
}

@MainActor
final class FocusPetModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var currentSnapshot: ActivitySnapshot
    @Published var currentDecision: StateDecision
    @Published var stateSegments: [StateSegment]
    @Published var appUsage: [AppUsageSegment]
    @Published var inputActivity: [InputActivityBucket]
    @Published var focusSessions: [FocusSession]
    @Published var breakSessions: [BreakSession]
    @Published var nudges: [NudgeEvent]
    @Published var summary: DailySummary
    @Published var selectedTab: DashboardTab = .today
    @Published var rules: [ClassificationRule]
    @Published var statusMessage = "Focus Pet 已准备好。"
    @Published var notificationPermissionTitle = "检查中"
    @Published var notificationPermissionIsAllowed = false
    @Published var recognitionDiagnostic = RecognitionDiagnosticSnapshot.pending
    @Published var exportURL: URL?
    @Published var availablePetPacks: [PetPackRecord] = []
    @Published var petImportMessage: String?
    @Published var petImportErrorMessage: String?

    private let store = LocalStore()
    private let persistenceService = SnapshotPersistenceService()
    private let tracker = TimeTracker()
    private let behaviorPolicy = PetBehaviorPolicy()
    private let summaryBuilder = DailySummaryBuilder()
    private let summaryService = SummaryRefreshService()
    private var activityClassifier = ActivityClassifier()
    private let activitySampler = ActivitySampler()
    private let switchTracker = AppSwitchTracker()
    private let inputEventMonitor = InputActivityMonitor()
    private let appSwitchEventMonitor = ApplicationSwitchEventMonitor()
    private let inputActivityRecorder = InputActivityRecorder()
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
    private var transientPetIntent: PetIntentKind?
    private var transientPetIntentSource: PetIntentSource = .interaction
    private var transientPetIntentExpiresAt: Date?
    private var currentPetIntentKind: PetIntentKind = .quietCompanion
    private var petAnimationIdentity: String?
    private var petAnimationStartedAt = Date()
    private var sourceActionSound: NSSound?
    private var sourceActionSoundIdentity: String?
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
    private var dashboardAnchorFrames: [DashboardPetAnchor: DashboardAnchorSnapshot] = [:]
    private var dashboardPetAttachment: DashboardPetAttachment?
    private var dashboardPetPinIsActive = false
    private var dashboardVisibilityTask: Task<Void, Never>?
    private var dashboardActivationTask: Task<Void, Never>?
    private var lastDashboardActivationRefreshAt = Date.distantPast
    private weak var observedDashboardWindow: NSWindow?
    private var dashboardWindowObserverTokens: [NSObjectProtocol] = []
    private var saveTask: Task<Void, Never>?
    private var pendingSaveSnapshot: LocalStoreSnapshot?
    private var lastEnqueuedSaveSnapshot: LocalStoreSnapshot?
    private var lastSaveStartedAt = Date.distantPast
    private let saveDebounceSeconds: TimeInterval = 2
    private let saveThrottleSeconds: TimeInterval = 20
    private var summaryTask: Task<Void, Never>?
    private var summaryGeneration = 0
    private var lastSummaryRefreshedAt = Date.distantPast
    private let summaryThrottleSeconds: TimeInterval = 20
    private var tickTask: Task<Void, Never>?
    private var tickGeneration = 0

    init() {
        let now = Date()
        let snapshot = store.loadSnapshot()
        settings = snapshot.settings
        stateSegments = snapshot.stateSegments
        appUsage = snapshot.appUsage
        inputActivity = snapshot.inputActivity
        focusSessions = snapshot.focusSessions
        breakSessions = snapshot.breakSessions
        nudges = snapshot.nudges
        let userRules = ActivityClassifier.userRules(fromStored: snapshot.classificationRules)
        rules = userRules
        activityClassifier = ActivityClassifier(rules: userRules)
        lastEnqueuedSaveSnapshot = snapshot
        Task { [persistenceService] in
            await persistenceService.replaceBaseline(snapshot)
        }

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
        lastSummaryRefreshedAt = now
        refreshPetPacks(saveIfChanged: false)
        configurePetPanelInteractions()
        applySettingsMigrationsIfNeeded()
        refreshRecognitionDiagnostics()
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
        if dashboardPetIsAttached {
            return nil
        }

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

    private var dashboardPetIsAttached: Bool {
        guard dashboardPetAttachment != nil,
              visibleDashboardWindow() != nil else { return false }
        return true
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

    var reminderPauseActionTitle: String {
        "暂停 \(settings.reminder.pauseMinutes) 分钟"
    }

    var recordingStatusTitle: String {
        settings.privacy.pauseActivityRecording ? "所有记录已暂停" : "正在记录本地统计"
    }

    var dataSizeTitle: String {
        ByteCountFormatter.string(fromByteCount: Int64(store.currentDataSize()), countStyle: .file)
    }

    var todayWorkload: InputWorkloadSummary {
        InputWorkloadSummary(dayContaining: Date(), inputActivity: inputActivity)
    }

    func start() {
        guard timer == nil else { return }
        configureSystemSleepObservers()
        configureSessionActivityObservers()
        inputEventMonitor.start()
        appSwitchEventMonitor.start()
        advanceStateTick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStateTick()
            }
        }
        timer?.tolerance = 0.5
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
            requestNotificationAuthorization()
        } else {
            refreshNotificationPermissionStatus()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        inputEventMonitor.stop()
        appSwitchEventMonitor.stop()
        mouseTimer?.invalidate()
        mouseTimer = nil
        tickTask?.cancel()
        summaryTask?.cancel()
        saveImmediately()
    }

    func advanceStateTick() {
        let now = Date()
        let elapsedSinceLastTick = lastTickAt.map { now.timeIntervalSince($0) }
        lastTickAt = now
        closeExpiredBreakIfNeeded(now: now)

        tickGeneration += 1
        let generation = tickGeneration
        let classifier = activityClassifier
        let privacy = settings.privacy
        tickTask?.cancel()
        tickTask = Task(priority: .utility) { [weak self, activitySampler] in
            let sample = await activitySampler.snapshot(now: now)
            guard !Task.isCancelled else { return }
            let front = sample.frontmostApplication
            let sanitizedTitle = privacy.sanitize(front.windowTitle)
            let category = classifier.classify(
                appName: front.appName,
                bundleID: front.bundleID,
                windowTitle: front.windowTitle
            )
            await MainActor.run {
                self?.applyActivitySample(
                    sample,
                    category: category,
                    sanitizedTitle: sanitizedTitle,
                    now: now,
                    elapsedSinceLastTick: elapsedSinceLastTick,
                    generation: generation
                )
            }
        }
    }

    private func applyActivitySample(
        _ sample: ActivitySamplerSnapshot,
        category: ActivityCategory,
        sanitizedTitle: SanitizedWindowTitle,
        now: Date,
        elapsedSinceLastTick: TimeInterval?,
        generation: Int
    ) {
        guard generation == tickGeneration else { return }
        if sample.session.isScreenLocked {
            applyScreenLockedSnapshot(now: now, idleSeconds: sample.idleSeconds)
            return
        }

        let front = sample.frontmostApplication
        let identity = "\(front.bundleID ?? "")|\(front.appName)"
        let didSampledSwitch = switchTracker.update(identity: identity, category: category, now: now)

        let snapshot = ActivitySnapshot(
            timestamp: now,
            appName: front.appName,
            bundleID: front.bundleID,
            windowTitle: settings.privacy.storeRawTitle && !settings.privacy.storeOnlyCategoryResult ? front.windowTitle : nil,
            titleHash: sanitizedTitle.titleHash,
            titleStored: sanitizedTitle.titleStored,
            titleDisplay: sanitizedTitle.titleDisplay,
            category: category,
            idleSeconds: sample.idleSeconds,
            switchCountLast5Min: switchTracker.switchCount(seconds: 5 * 60, now: now),
            switchCountLast15Min: switchTracker.switchCount(seconds: 15 * 60, now: now),
            activeCategoryDuration: switchTracker.activeCategoryDuration(now: now),
            activeAppDuration: switchTracker.activeAppDuration(now: now),
            isFocusSessionActive: activeFocusSession != nil,
            isBreakActive: activeBreakSession != nil,
            isScreenLocked: sample.session.isScreenLocked
        )

        let stateBeforeTick = currentDecision.state
        let stateDurationBeforeTick = currentDecision.stableDuration
        let rawDecision = stateEngine.evaluate(snapshot, previousStableState: currentDecision.state)
        let decision = stabilized(rawDecision, now: now)
        currentSnapshot = snapshot
        currentDecision = decision

        if settings.privacy.pauseActivityRecording {
            inputEventMonitor.discardCounts()
            _ = appSwitchEventMonitor.drainSwitchCount(fallbackSwitchCount: 0)
            statusMessage = "所有本地记录已暂停。"
            updatePet()
            return
        }

        let tickSeconds = min(max(tracker.tickSeconds, elapsedSinceLastTick ?? tracker.tickSeconds), 60)
        let tickTracker = TimeTracker(tickSeconds: tickSeconds)
        recordInputActivity(now: now, tickSeconds: tickSeconds, sampledSwitchCount: didSampledSwitch ? 1 : 0)
        stateSegments = tickTracker.record(decision: decision, snapshot: snapshot, segments: stateSegments)
        appUsage = decision.state == .away ? appUsage : tickTracker.recordAppUsage(snapshot: snapshot, appUsage: appUsage)
        applySessionAccounting(decision: decision, previousTickState: stateBeforeTick, tickSeconds: tickSeconds)
        reclassifyLongInputIdleAwayIfNeeded(decision: decision, snapshot: snapshot)
        let completedFocusSession = closeExpiredFocusSessionIfNeeded(now: now)
        if !completedFocusSession {
            triggerNudgeIfNeeded(
                decision: decision,
                snapshot: snapshot,
                now: now,
                previousState: stateBeforeTick == decision.state ? nil : stateBeforeTick,
                previousStateDuration: stateDurationBeforeTick
            )
        }
        refreshSummary()
        save()
        updatePet()
    }

    private func recordInputActivity(now: Date, tickSeconds: TimeInterval, sampledSwitchCount: Int) {
        let inputCounts = inputEventMonitor.drainCounts(fallbackWindowSeconds: tickSeconds)
        let switchCount = appSwitchEventMonitor.drainSwitchCount(fallbackSwitchCount: sampledSwitchCount)
        inputActivity = inputActivityRecorder.record(
            now: now,
            keyboardCount: inputCounts.keyboardCount,
            pointerCount: inputCounts.pointerCount,
            switchCount: switchCount,
            buckets: inputActivity
        )
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

    func pauseReminders(minutes: Int? = nil) {
        let minutes = minutes ?? settings.reminder.pauseMinutes
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
        detachDashboardPet(reposition: true)
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

    func openSystemSettings(_ destination: SystemSettingsDestination) {
        destination.open()
        statusMessage = "已打开 macOS \(destination.title) 设置。"
    }

    func requestSystemPermission(_ destination: SystemSettingsDestination) {
        switch destination {
        case .notifications:
            requestNotificationAuthorization(force: true)
            statusMessage = "已请求通知权限。"
        case .inputMonitoring, .screenRecording:
            _ = destination.requestAccessIfAvailable()
            destination.open()
            statusMessage = "已打开 macOS \(destination.title) 设置。"
        case .accessibility, .privacySecurity:
            destination.open()
            statusMessage = "已打开 macOS \(destination.title) 设置。"
        }
    }

    func showPetStatusBubble() {
        let idleText = FocusPetFormatters.duration(Int(currentSnapshot.idleSeconds))
        showTransientPetMessage("\(currentDecision.state.title) · \(currentSnapshot.appName) · 空闲 \(idleText)", seconds: 6)
    }

    func openDashboard(tab: DashboardTab = .today) {
        selectedTab = tab

        if bringDashboardWindowToFront() {
            schedulePetDashboardPresentation(tab: tab, delayNanoseconds: 20_000_000)
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
            self.schedulePetDashboardPresentation(tab: tab, delayNanoseconds: 80_000_000)
        }
    }

    @discardableResult
    func bringDashboardWindowToFront() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if let dashboardWindow = dashboardWindow() {
            dashboardWindow.collectionBehavior.insert(.moveToActiveSpace)
            dashboardWindow.makeKeyAndOrderFront(nil)
            dashboardWindow.orderFrontRegardless()
            configureDashboardWindowObservers()
            return true
        }
        return false
    }

    func registerOpenDashboardRequest(_ request: @escaping @MainActor (DashboardTab) -> Void) {
        openDashboardRequest = request
    }

    func updateDashboardPetAnchor(_ anchor: DashboardPetAnchor, frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        if let existing = dashboardAnchorFrames[anchor]?.frame,
           abs(existing.origin.x - frame.origin.x) < 0.5,
           abs(existing.origin.y - frame.origin.y) < 0.5,
           abs(existing.width - frame.width) < 0.5,
           abs(existing.height - frame.height) < 0.5 {
            dashboardAnchorFrames[anchor]?.updatedAt = Date()
            return
        }
        dashboardAnchorFrames[anchor] = DashboardAnchorSnapshot(frame: frame, updatedAt: Date())
        refreshDashboardPetAttachmentIfNeeded(changedAnchor: anchor)
    }

    func presentPetForDashboard(tab: DashboardTab) {
        guard !settings.pet.hidden else { return }
        let plan = dashboardPetPresentationPlan(for: tab)
        let now = Date()
        let expiresAt = now.addingTimeInterval(plan.duration)
        dashboardPetAttachment = DashboardPetAttachment(plan: plan, tab: tab)
        configureDashboardWindowObservers()
        transientPetIntent = plan.intent
        transientPetIntentSource = .interaction
        transientPetIntentExpiresAt = expiresAt
        petAnimationIdentity = nil
        transientPetMessage = plan.message
        transientPetMessageExpiresAt = plan.message == nil ? nil : expiresAt
        updatePet()

        positionDashboardAttachedPet(requiringFreshAnchor: false)
        clearTransientPetIntent(after: plan.duration)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard self.transientPetIntentExpiresAt == expiresAt else { return }
            self.positionDashboardAttachedPet(requiringFreshAnchor: true)
        }
    }

    func dashboardWindowDidActivate() {
        guard !settings.pet.hidden,
              dashboardWindow() != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDashboardActivationRefreshAt) >= 0.45 else { return }
        lastDashboardActivationRefreshAt = now
        configureDashboardWindowObservers()

        let tab = selectedTab
        dashboardActivationTask?.cancel()
        dashboardActivationTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled,
                  self.dashboardWindow() != nil else { return }

            if self.visibleDashboardWindow() == nil {
                try? await Task.sleep(nanoseconds: 180_000_000)
            }

            guard !Task.isCancelled,
                  self.visibleDashboardWindow() != nil else { return }
            self.presentPetForDashboard(tab: tab)

            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self.positionDashboardAttachedPet(requiringFreshAnchor: false)
        }
    }

    private struct DashboardAnchorSnapshot {
        var frame: CGRect
        var updatedAt: Date
    }

    private struct DashboardPetPresentationPlan {
        var anchor: DashboardPetAnchor
        var fallbackAnchors: [DashboardPetAnchor] = []
        var edge: PetPanelAnchorEdge
        var intent: PetIntentKind
        var message: String?
        var duration: TimeInterval
    }

    private struct DashboardPetAttachment {
        var plan: DashboardPetPresentationPlan
        var tab: DashboardTab
    }

    private static let minimumDashboardWindowSize = CGSize(width: 600, height: 500)

    private func schedulePetDashboardPresentation(tab: DashboardTab, delayNanoseconds: UInt64) {
        Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            } else {
                await Task.yield()
            }
            self.bringDashboardWindowToFront()
            self.presentPetForDashboard(tab: tab)
        }
    }

    private func dashboardPetPresentationPlan(for tab: DashboardTab) -> DashboardPetPresentationPlan {
        DashboardPetPresentationPlan(
            anchor: .sidebarPetDock,
            fallbackAnchors: [.dashboardPanel],
            edge: .insetBottomLeft,
            intent: tab == .sessions ? .focusRestHint : .dashboardGuide,
            message: nil,
            duration: 8
        )
    }

    private func refreshDashboardPetAttachmentIfNeeded(changedAnchor: DashboardPetAnchor) {
        guard let attachment = dashboardPetAttachment else { return }
        guard visibleDashboardWindow() != nil else {
            detachDashboardPet(reposition: true)
            return
        }

        let anchors = [attachment.plan.anchor] + attachment.plan.fallbackAnchors
        guard anchors.contains(changedAnchor) else { return }
        positionDashboardAttachedPet(requiringFreshAnchor: false)
    }

    private func positionDashboardAttachedPet(requiringFreshAnchor: Bool, refreshVisibilityWatch: Bool = true) {
        guard let attachment = dashboardPetAttachment else { return }
        guard visibleDashboardWindow() != nil else {
            detachDashboardPet(reposition: true)
            return
        }
        guard let frame = dashboardPresentationFrame(
            for: attachment.plan,
            tab: attachment.tab,
            requiringFreshAnchor: requiringFreshAnchor
        ) else { return }
        petPanel.pin(
            near: frame,
            preferredEdge: attachment.plan.edge,
            duration: 0.75
        )
        dashboardPetPinIsActive = true
        if refreshVisibilityWatch {
            startDashboardVisibilityWatch()
        }
    }

    private func dashboardPresentationFrame(
        for plan: DashboardPetPresentationPlan,
        tab: DashboardTab,
        requiringFreshAnchor: Bool
    ) -> CGRect? {
        if plan.anchor == .sidebarPetDock,
           let frame = dashboardWindowFallbackFrame(for: tab) {
            return frame
        }

        let anchors = [plan.anchor] + plan.fallbackAnchors
        for anchor in anchors {
            if let frame = dashboardAnchorFrame(anchor, requiringFresh: requiringFreshAnchor) {
                return frame
            }
        }
        return requiringFreshAnchor ? nil : dashboardWindowFallbackFrame(for: tab)
    }

    private func dashboardAnchorFrame(_ anchor: DashboardPetAnchor, requiringFresh: Bool) -> CGRect? {
        guard let snapshot = dashboardAnchorFrames[anchor] else { return nil }
        if requiringFresh && Date().timeIntervalSince(snapshot.updatedAt) > 1.5 {
            return nil
        }
        if let windowFrame = visibleDashboardWindow()?.frame,
           !windowFrame.insetBy(dx: -120, dy: -120).intersects(snapshot.frame) {
            return nil
        }
        return snapshot.frame
    }

    private func dashboardWindowFallbackFrame(for tab: DashboardTab) -> CGRect? {
        guard let windowFrame = visibleDashboardWindow()?.frame else { return nil }
        return DashboardPetDockingGeometry.sidebarDockFrame(windowFrame: windowFrame)
    }

    private func dashboardWindow() -> NSWindow? {
        let windows = NSApp.windows
        return windows.first { $0.identifier?.rawValue == "dashboard" }
            ?? windows.first {
                $0.title == "Focus Pet"
                    && $0.frame.width >= Self.minimumDashboardWindowSize.width
                    && $0.frame.height >= Self.minimumDashboardWindowSize.height
            }
    }

    private func visibleDashboardWindow() -> NSWindow? {
        guard let window = dashboardWindow(),
              window.isVisible,
              !window.isMiniaturized,
              window.occlusionState.contains(.visible),
              Self.dashboardWindowIsOnScreen(window) else { return nil }
        return window
    }

    private static func dashboardWindowIsOnScreen(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { info in
            guard let number = info[kCGWindowNumber as String] as? Int,
                  number == window.windowNumber,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                return false
            }
            return (bounds["Width"] ?? 0) >= minimumDashboardWindowSize.width
                && (bounds["Height"] ?? 0) >= minimumDashboardWindowSize.height
        }
    }

    private func configureDashboardWindowObservers() {
        guard let window = dashboardWindow() else {
            clearDashboardWindowObservers()
            return
        }
        guard observedDashboardWindow !== window else { return }
        clearDashboardWindowObservers()
        observedDashboardWindow = window
        let names: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.willMiniaturizeNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didExposeNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        dashboardWindowObserverTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    switch name {
                    case NSWindow.willCloseNotification,
                        NSWindow.willMiniaturizeNotification,
                        NSWindow.didMiniaturizeNotification:
                        self.dashboardWindowDidDismiss()
                    case NSWindow.didChangeOcclusionStateNotification:
                        if self.visibleDashboardWindow() == nil {
                            self.dashboardWindowDidDismiss()
                        } else {
                            self.dashboardWindowDidActivate()
                        }
                    default:
                        self.dashboardWindowDidActivate()
                    }
                }
            }
        }
        dashboardWindowObserverTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.dashboardWindowDidActivate()
                }
            }
        )
    }

    private func clearDashboardWindowObservers() {
        for token in dashboardWindowObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        dashboardWindowObserverTokens = []
        observedDashboardWindow = nil
    }

    private func startDashboardVisibilityWatch() {
        dashboardVisibilityTask?.cancel()
        dashboardVisibilityTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard self.dashboardPetAttachment != nil || self.dashboardPetPinIsActive else { return }
                if self.visibleDashboardWindow() == nil {
                    self.detachDashboardPet(reposition: true)
                    self.updatePet()
                    return
                }
                if self.dashboardPetAttachment != nil {
                    self.positionDashboardAttachedPet(requiringFreshAnchor: false, refreshVisibilityWatch: false)
                }
            }
        }
    }

    private func stopDashboardVisibilityWatch() {
        dashboardVisibilityTask?.cancel()
        dashboardVisibilityTask = nil
    }

    private func detachDashboardPet(reposition: Bool) {
        dashboardActivationTask?.cancel()
        dashboardActivationTask = nil
        dashboardPetAttachment = nil
        dashboardPetPinIsActive = false
        stopDashboardVisibilityWatch()
        clearDashboardWindowObservers()
        petPanel.clearTemporaryPlacement(reposition: reposition)
    }

    func dashboardWindowDidDismiss() {
        detachDashboardPet(reposition: true)
        updatePet()
    }

    func handlePetDragBegan() {
        detachDashboardPet(reposition: false)
        transientPetIntent = .dragged
        transientPetIntentSource = .physicalInteraction
        transientPetIntentExpiresAt = nil
        petAnimationIdentity = nil
        updatePet()
    }

    func handlePetDragEnded(origin: CGPoint) {
        settings.pet.placement = .custom
        settings.pet.customOriginX = origin.x
        settings.pet.customOriginY = origin.y
        transientPetIntent = .landing
        transientPetIntentSource = .physicalInteraction
        transientPetIntentExpiresAt = Date().addingTimeInterval(1.5)
        petAnimationIdentity = nil
        statusMessage = "桌宠位置已保存为自定义。"
        save()
        showTransientPetMessage("放在这里。", seconds: 3)
        clearTransientPetIntent(after: 1.6)
    }

    func deleteAllData() {
        summaryTask?.cancel()
        summaryGeneration += 1
        store.deleteAll()
        stateSegments = []
        appUsage = []
        inputActivity = []
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
        settings.reminder.hasAppliedSystemNotificationDefault = true
        if settings.privacy.storeOnlyCategoryResult {
            settings.privacy.storeRawTitle = false
        }
        settings.reminder.normalize()
        settings.judgment.normalize()
        save()
        if settings.reminder.enableSystemNotifications {
            requestNotificationAuthorization()
        } else {
            refreshNotificationPermissionStatus()
        }
        updatePet()
    }

    private func applySettingsMigrationsIfNeeded() {
        guard !settings.reminder.hasAppliedSystemNotificationDefault else { return }
        settings.reminder.hasAppliedSystemNotificationDefault = true
        save()
        refreshNotificationPermissionStatus()
    }

    func refreshNotificationPermissionStatus() {
        notificationSender.authorizationStatus { [weak self] state in
            Task { @MainActor in
                self?.applyNotificationPermissionState(state)
            }
        }
    }

    func refreshRecognitionDiagnostics() {
        let classifier = activityClassifier
        let userRuleCount = rules.count
        let recordingPaused = settings.privacy.pauseActivityRecording
        Task { [weak self, activitySampler] in
            let now = Date()
            let sample = await activitySampler.snapshot(now: now, windowTitleRefreshInterval: 0)
            let front = sample.frontmostApplication
            let category = classifier.classify(
                appName: front.appName,
                bundleID: front.bundleID,
                windowTitle: front.windowTitle
            )
            let diagnostic = RecognitionDiagnosticSnapshot(
                sampledAt: now,
                appName: front.appName,
                bundleID: front.bundleID,
                windowTitle: front.windowTitle,
                category: category,
                catalogEntryCount: ActivityClassifier.catalogEntries.count,
                defaultRuleCount: ActivityClassifier.defaultRules.count,
                userRuleCount: userRuleCount,
                screenRecordingStatus: SystemSettingsDestination.screenRecording.statusTitle ?? "未知",
                inputMonitoringStatus: SystemSettingsDestination.inputMonitoring.statusTitle ?? "未知",
                accessibilityStatus: SystemSettingsDestination.accessibility.statusTitle ?? "未知",
                recordingPaused: recordingPaused
            )
            await MainActor.run {
                self?.recognitionDiagnostic = diagnostic
            }
        }
    }

    func resetRecognitionRules() {
        rules.removeAll()
        activityClassifier = ActivityClassifier()
        statusMessage = "识别例外已清空，已恢复内置规则。"
        save()
        refreshRecognitionDiagnostics()
    }

    private func requestNotificationAuthorization(force: Bool = false) {
        notificationSender.requestAuthorization(force: force) { [weak self] state in
            Task { @MainActor in
                self?.applyNotificationPermissionState(state)
            }
        }
    }

    private func applyNotificationPermissionState(_ state: SystemNotificationPermissionState) {
        notificationPermissionTitle = state.title
        notificationPermissionIsAllowed = state.isAllowed
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

    private func selectedPetPackRecord() -> PetPackRecord? {
        availablePetPacks.first { $0.id == settings.pet.selectedPackID } ?? availablePetPacks.first
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

    func setIdleSourceAction(_ sourceActionID: String) {
        setSourceAction(sourceActionID, for: .quietCompanion)
    }

    func setSourceAction(_ sourceActionID: String, for intent: PetIntentKind) {
        guard let record = selectedPetPackRecord(),
              let sourceAction = record.sourceAction(id: sourceActionID),
              !record.frameURLs(forSourceActionID: sourceActionID).isEmpty else {
            return
        }

        settings.pet.setSourceActionID(sourceActionID, for: intent, packID: record.id)
        transientPetIntent = intent
        transientPetIntentSource = .interaction
        transientPetIntentExpiresAt = Date().addingTimeInterval(2.4)
        petAnimationIdentity = nil
        statusMessage = "\(intent.title)已映射到 \(sourceAction.title)。"
        save()
        updatePet()
        showTransientPetMessage("\(intent.title)：\(sourceAction.title)", seconds: 3)
        clearTransientPetIntent(after: 2.4)
    }

    func mappedSourceActionID(for intent: PetIntentKind, in record: PetPackRecord) -> String? {
        settings.pet.sourceActionID(for: intent, packID: record.id)
    }

    func resolvedSourceAction(for intent: PetIntentKind, in record: PetPackRecord) -> PetSourceActionSpec? {
        record.sourceAction(
            for: intent,
            mappedSourceActionID: settings.pet.sourceActionID(for: intent, packID: record.id)
        )
    }

    func isCustomSourceAction(_ sourceActionID: String, for intent: PetIntentKind, in record: PetPackRecord) -> Bool {
        settings.pet.sourceActionID(for: intent, packID: record.id) == sourceActionID
    }

    func addRule(pattern: String, matchKind: RuleMatchKind, category: ActivityCategory) {
        let cleaned = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        rules.append(ClassificationRule(
            matchKind: matchKind,
            pattern: cleaned,
            category: category,
            priority: rulePriority(for: matchKind)
        ))
        activityClassifier = ActivityClassifier(rules: rules)
        statusMessage = "识别例外已添加。"
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
            priority: rulePriority(for: matchKind)
        ))
        activityClassifier = ActivityClassifier(rules: rules)
        statusMessage = "\(cleaned) 已设为\(category.correctionTitle)。"
        save()
    }

    private func rulePriority(for matchKind: RuleMatchKind) -> Int {
        switch matchKind {
        case .windowTitle: 260
        case .appName: 240
        case .bundleID: 230
        }
    }

    func deleteRule(_ rule: ClassificationRule) {
        rules.removeAll { $0.id == rule.id }
        activityClassifier = ActivityClassifier(rules: rules)
        statusMessage = "识别例外已删除。"
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

        if now.timeIntervalSince(candidateSince) >= settings.judgment.stateEngineThresholds.uiStabilitySeconds {
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
        (currentDecision.state == .distracted && decision.state == .focus)
            || decision.reason.contains(.recentInputRecovery)
            || decision.reason.contains(.inputIdleDistracted)
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

    private func triggerNudgeIfNeeded(
        decision: StateDecision,
        snapshot: ActivitySnapshot,
        now: Date,
        previousState: FocusState?,
        previousStateDuration: TimeInterval?
    ) {
        if let pauseUntil = settings.reminder.pauseUntil {
            if pauseUntil > now {
                return
            }
            settings.reminder.pauseUntil = nil
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
            previousStateDuration: previousStateDuration,
            now: now,
            lastTriggeredAt: lastNudgeAt
        ) else { return }
        guard recordNudgeIfAllowed(event, now: now) else { return }
        lastNudgeAt[event.reason] = event.time
    }

    private func remindersCanRecord(_ reason: NudgeReason, now: Date) -> Bool {
        if let pauseUntil = settings.reminder.pauseUntil {
            if pauseUntil > now {
                return false
            }
            settings.reminder.pauseUntil = nil
        }

        guard settings.reminder.enablePetBubbles || settings.reminder.enableSystemNotifications else {
            return false
        }

        return settings.reminder.allows(reason)
    }

    @discardableResult
    private func recordNudgeIfAllowed(_ event: NudgeEvent, now: Date) -> Bool {
        guard remindersCanRecord(event.reason, now: now) else { return false }
        recordNudge(event)
        return true
    }

    private func reclassifyLongInputIdleAwayIfNeeded(decision: StateDecision, snapshot: ActivitySnapshot) {
        guard decision.reason.contains(.longInputIdleAway), snapshot.idleSeconds > 0 else { return }

        let idleEnd = snapshot.timestamp
        let idleStart = idleEnd.addingTimeInterval(-snapshot.idleSeconds)
        let sessionDeltas = reclassifiableActiveSessionSeconds(from: idleStart, to: idleEnd)
        let result = TimeTracker(tickSeconds: tracker.tickSeconds).reclassify(
            segments: stateSegments,
            from: idleStart,
            to: idleEnd,
            matching: [.focus, .distracted],
            as: .away,
            addingSource: .idleTime
        )

        guard !result.reclassifiedSeconds.isEmpty else { return }
        stateSegments = result.segments
        applyActiveSessionIdleAwayReclassification(sessionDeltas)

        let convertedSeconds = result.reclassifiedSeconds.values.reduce(0, +)
        if convertedSeconds > 0 {
            statusMessage = "长时间无输入，已将无输入时段记为暂离。"
        }
    }

    private func reclassifiableActiveSessionSeconds(from intervalStart: Date, to intervalEnd: Date) -> [FocusState: Int] {
        guard intervalEnd > intervalStart,
              let activeIndex = focusSessions.lastIndex(where: { $0.status == .active }) else {
            return [:]
        }

        let sessionStart = max(intervalStart, focusSessions[activeIndex].start)
        let sessionEnd = min(intervalEnd, focusSessions[activeIndex].end ?? intervalEnd)
        guard sessionEnd > sessionStart else { return [:] }

        var secondsByState: [FocusState: Int] = [:]
        for segment in stateSegments where segment.state == .focus || segment.state == .distracted {
            let overlapStart = max(segment.start, sessionStart)
            let overlapEnd = min(segment.end, sessionEnd)
            guard overlapEnd > overlapStart else { continue }
            secondsByState[segment.state, default: 0] += max(0, Int(overlapEnd.timeIntervalSince(overlapStart).rounded()))
        }
        return secondsByState
    }

    private func applyActiveSessionIdleAwayReclassification(_ secondsByState: [FocusState: Int]) {
        guard let activeIndex = focusSessions.lastIndex(where: { $0.status == .active }) else { return }

        let focusSeconds = min(focusSessions[activeIndex].effectiveFocusSeconds, secondsByState[.focus, default: 0])
        let distractedSeconds = min(focusSessions[activeIndex].distractedSeconds, secondsByState[.distracted, default: 0])
        let convertedSeconds = focusSeconds + distractedSeconds
        guard convertedSeconds > 0 else { return }

        focusSessions[activeIndex].effectiveFocusSeconds -= focusSeconds
        focusSessions[activeIndex].distractedSeconds -= distractedSeconds
        focusSessions[activeIndex].awaySeconds += convertedSeconds
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

    private func finishFocusSession(_ session: FocusSession, status: FocusSessionStatus, end: Date = Date()) {
        guard let index = focusSessions.firstIndex(where: { $0.id == session.id }) else { return }
        focusSessions[index].end = end
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
        let lockStartedAt = screenLockedStartedAt
        if let start = lockStartedAt {
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
        let lockedDuration = lockStartedAt.map { now.timeIntervalSince($0) } ?? 0
        if lockedDuration >= settings.reminder.nudgePolicyThresholds.welcomeBackAwaySeconds,
           settings.reminder.enableWelcomeBackNudges,
           settings.reminder.enablePetBubbles {
            showTransientPetMessage("欢迎回来。", seconds: 4)
        }
        advanceStateTick()
    }

    private func applyScreenLockedSnapshot(now: Date, idleSeconds: TimeInterval? = nil) {
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
            idleSeconds: idleSeconds ?? currentSnapshot.idleSeconds,
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
        currentDecision = stateEngine.evaluate(snapshot, previousStableState: previous)
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
        refreshSummary(force: true)
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
        currentDecision = stateEngine.evaluate(snapshot, previousStableState: currentDecision.state)
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
        let awayDecision = stateEngine.evaluate(awaySnapshot, previousStableState: currentDecision.state)
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
        refreshSummary(force: true)
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
        transientPetIntent = movementIntent(from: previousHint, to: hint)
        transientPetIntentSource = .interaction
        transientPetIntentExpiresAt = Date().addingTimeInterval(1.6)
        petAnimationIdentity = nil
        showTransientPetMessage("我切到这块屏幕。", seconds: 2)
        clearTransientPetIntent(after: 1.7)
    }

    @discardableResult
    private func closeExpiredFocusSessionIfNeeded(now: Date) -> Bool {
        guard let index = focusSessions.lastIndex(where: { $0.status == .active }) else { return false }
        let session = focusSessions[index]
        guard session.remainingSeconds(now: now) == 0 else { return false }

        finishFocusSession(session, status: .completed, end: now)
        let event = NudgeEvent(
            time: now,
            reason: .focusSessionCompleted,
            state: .focus,
            appName: session.taskName,
            category: .work,
            petIntent: .focusRestHint,
            cooldownSeconds: 0,
            message: "\(session.taskName) 完成啦，要休息一下吗？"
        )
        let didRecordNudge = recordNudgeIfAllowed(event, now: now)
        if didRecordNudge && settings.reminder.enablePetBubbles {
            showTransientPetMessage(event.message, seconds: 6)
        }

        if session.autoStartBreak {
            startBreak(minutes: max(1, session.breakDurationSeconds / 60), source: .afterFocusSession)
        } else {
            refreshSummary(force: true)
            save()
            updatePet()
        }

        return true
    }

    private func closeExpiredBreakIfNeeded(now: Date) {
        guard let index = breakSessions.lastIndex(where: { $0.end == nil && !$0.completed }) else { return }
        if breakSessions[index].remainingSeconds(now: now) == 0 {
            breakSessions[index].end = now
            breakSessions[index].completed = true
            let event = NudgeEvent(
                time: now,
                reason: .breakEnding,
                state: .breakTime,
                appName: "Break",
                category: .ignore,
                petIntent: .breakEnding,
                cooldownSeconds: 0,
                message: "休息时间结束啦。"
            )
            if recordNudgeIfAllowed(event, now: now) {
                transientPetIntent = .mouseSummon
                transientPetIntentSource = .interaction
                transientPetIntentExpiresAt = now.addingTimeInterval(6)
                petAnimationIdentity = nil
                petPanel.summonNearMouse(duration: 12)
                if settings.reminder.enablePetBubbles {
                    showTransientPetMessage("休息结束，回来工作啦。", seconds: 6)
                }
            }
            statusMessage = "休息结束。"
            refreshSummary(force: true)
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
        if (dashboardPetAttachment != nil || dashboardPetPinIsActive), visibleDashboardWindow() == nil {
            detachDashboardPet(reposition: true)
            updatePet()
            return
        }
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
            idleSeconds: currentSnapshot.idleSeconds,
            switchCountLast5Min: currentSnapshot.switchCountLast5Min,
            switchCountLast15Min: currentSnapshot.switchCountLast15Min,
            activeCategoryDuration: 0,
            activeAppDuration: 0,
            isFocusSessionActive: activeFocusSession != nil,
            isBreakActive: true,
            source: [.breakSession]
        )
        currentSnapshot = snapshot
        currentDecision = stateEngine.evaluate(snapshot, previousStableState: previous)
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

    private func movementIntent(from previousHint: ScreenPlacementHint?, to nextHint: ScreenPlacementHint) -> PetIntentKind {
        guard let previousHint else { return .moveRight }
        let dx = nextHint.visibleFrame.midX - previousHint.visibleFrame.midX
        let dy = nextHint.visibleFrame.midY - previousHint.visibleFrame.midY

        if abs(dx) >= abs(dy) {
            return dx >= 0 ? .moveRight : .moveLeft
        }

        return dy >= 0 ? .moveUp : .moveDown
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

    private func refreshSummary(force: Bool = false) {
        let now = Date()
        summaryGeneration += 1
        let generation = summaryGeneration
        summaryTask?.cancel()

        let delaySeconds = force ? 0 : max(0, summaryThrottleSeconds - now.timeIntervalSince(lastSummaryRefreshedAt))
        let delayNanoseconds = UInt64(max(0, delaySeconds) * 1_000_000_000)
        let stateSegmentsSnapshot = stateSegments
        let appUsageSnapshot = appUsage
        let focusSessionsSnapshot = focusSessions
        let breakSessionsSnapshot = breakSessions
        let nudgesSnapshot = nudges

        summaryTask = Task(priority: .utility) { [weak self, summaryService] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            let result = await summaryService.refresh(
                now: now,
                stateSegments: stateSegmentsSnapshot,
                appUsage: appUsageSnapshot,
                focusSessions: focusSessionsSnapshot,
                breakSessions: breakSessionsSnapshot,
                nudges: nudgesSnapshot
            )
            await MainActor.run {
                self?.applySummaryRefresh(result, generation: generation)
            }
        }
    }

    private func applySummaryRefresh(_ result: SummaryRefreshResult, generation: Int) {
        guard generation == summaryGeneration else { return }
        summary = result.summary
        lastSummaryRefreshedAt = Date()

        if activeBreakSession != nil || isPetHovering {
            updatePet()
        }
    }

    private func updatePet() {
        guard !settings.pet.hidden else {
            petPanel.hide()
            return
        }
        if availablePetPacks.isEmpty {
            refreshPetPacks(saveIfChanged: false)
        }
        let selectedRecord = selectedPetPackRecord()
            ?? PetPackRecord(pack: PetPackCatalog.fallbackPack, rootURL: nil, isBundled: true)
        let now = Date()
        let intent = resolvedPetIntent(now: now)
        currentPetIntentKind = intent.kind
        let hoverIntent = hoverIntent(for: intent.kind)
        let sourceAction = resolvedSourceAction(for: intent.kind, in: selectedRecord)
        let hoverSourceAction = resolvedSourceAction(for: hoverIntent, in: selectedRecord)
        let sourceFrameURLs = sourceAction.map { selectedRecord.frameURLs(forSourceActionID: $0.id) } ?? []
        let hoverFrameURLs = hoverSourceAction.map { selectedRecord.frameURLs(forSourceActionID: $0.id) } ?? []
        let displayFrameURLs = sourceFrameURLs
        let displayFramesPerSecond = sourceAction?.fps ?? 8
        let displayLoops = sourceAction?.loop ?? true
        let mappedActionTitle = selectedRecord.playableSourceActions.count > 1 ? sourceAction?.title : nil
        let nextAnimationIdentity = [
            selectedRecord.id,
            intent.kind.rawValue,
            intent.source.rawValue,
            hoverIntent.rawValue,
            sourceAction?.id ?? "-",
            hoverSourceAction?.id ?? "-"
        ].joined(separator: "|")
        if petAnimationIdentity != nextAnimationIdentity {
            petAnimationIdentity = nextAnimationIdentity
            petAnimationStartedAt = now
            if let sourceAction, !sourceFrameURLs.isEmpty {
                playPetSourceActionSoundIfNeeded(record: selectedRecord, sourceAction: sourceAction, identity: nextAnimationIdentity)
            }
        }
        petPanel.update(PetRenderState(
            focusState: currentDecision.state,
            intent: intent.kind,
            message: currentPetMessage,
            hoverMessage: petHoverMessage,
            hoverStatusEnabled: settings.pet.hoverStatusEnabled && !dashboardPetIsAttached,
            hoverDetails: petHoverDetails,
            hoverBreakButtonTitle: petHoverBreakButtonTitle,
            pauseRemindersTitle: reminderPauseActionTitle,
            activeIntentTitle: intent.kind.title,
            mappedActionTitle: mappedActionTitle,
            breakEndsAt: activeBreakSession.map { $0.start.addingTimeInterval(Double($0.targetDurationSeconds)) },
            size: settings.pet.size,
            opacity: settings.pet.opacity,
            animationEnabled: settings.pet.animationEnabled,
            packName: selectedRecord.pack.name,
            placement: settings.pet.placement,
            customOriginX: settings.pet.customOriginX,
            customOriginY: settings.pet.customOriginY,
            frameURLs: displayFrameURLs,
            framesPerSecond: displayFramesPerSecond,
            loops: displayLoops,
            hoverIntent: hoverIntent,
            hoverFrameURLs: hoverFrameURLs,
            hoverFramesPerSecond: hoverSourceAction?.fps ?? 8,
            hoverLoops: hoverSourceAction?.loop ?? false,
            animationStartedAt: petAnimationStartedAt,
            screenHint: petScreenHint.map {
                PetScreenHint(screenFrame: $0.screenFrame, visibleFrame: $0.visibleFrame)
            }
        ))
        petPanel.show()
    }

    private func save() {
        let snapshot = snapshot()
        guard snapshot != lastEnqueuedSaveSnapshot else { return }
        lastEnqueuedSaveSnapshot = snapshot
        pendingSaveSnapshot = snapshot
        schedulePendingSave(force: false)
    }

    private func saveImmediately() {
        saveTask?.cancel()
        let snapshot = pendingSaveSnapshot ?? snapshot()
        pendingSaveSnapshot = nil
        lastEnqueuedSaveSnapshot = snapshot
        lastSaveStartedAt = Date()
        store.saveSnapshot(snapshot)
        Task { [persistenceService] in
            await persistenceService.replaceBaseline(snapshot)
        }
    }

    private func schedulePendingSave(force: Bool) {
        saveTask?.cancel()
        let now = Date()
        let delaySeconds: TimeInterval
        if force {
            delaySeconds = 0
        } else {
            delaySeconds = max(saveDebounceSeconds, saveThrottleSeconds - now.timeIntervalSince(lastSaveStartedAt))
        }
        let delayNanoseconds = UInt64(max(0, delaySeconds) * 1_000_000_000)

        saveTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            self?.persistPendingSnapshot()
        }
    }

    private func persistPendingSnapshot() {
        guard let snapshot = pendingSaveSnapshot else { return }
        pendingSaveSnapshot = nil
        lastSaveStartedAt = Date()
        Task { [persistenceService] in
            await persistenceService.save(snapshot)
        }
    }

    private func recordNudge(_ event: NudgeEvent) {
        nudges.append(event)
        if nudges.count > 200 {
            nudges.removeFirst(nudges.count - 200)
        }
        if shouldDeliverSystemNotification(for: event.reason),
           settings.reminder.enableSystemNotifications,
           settings.reminder.pauseUntil.map({ $0 <= Date() }) ?? true {
            notificationSender.deliver(event) { [weak self] result in
                Task { @MainActor in
                    self?.handleNotificationDeliveryResult(result)
                }
            }
        }
    }

    private func shouldDeliverSystemNotification(for reason: NudgeReason) -> Bool {
        switch reason {
        case .distractedOverThreshold, .welcomeBack, .frequentSwitching:
            return false
        case .distractedStrong, .longFocusRest, .veryLongFocusRest, .focusSessionCompleted, .breakEnding:
            return true
        }
    }

    private func handleNotificationDeliveryResult(_ result: SystemNotificationDeliveryResult) {
        switch result {
        case .delivered:
            notificationPermissionTitle = SystemNotificationPermissionState.allowed.title
            notificationPermissionIsAllowed = true
        case .permissionDenied, .notGranted:
            notificationPermissionTitle = SystemNotificationPermissionState.denied.title
            notificationPermissionIsAllowed = false
            statusMessage = "系统通知未开启，请在设置中允许通知。"
        case .failed:
            statusMessage = "系统通知发送失败。"
            refreshNotificationPermissionStatus()
        }
    }

    private func snapshot() -> LocalStoreSnapshot {
        LocalStoreSnapshot(
            settings: settings,
            classificationRules: rules,
            stateSegments: stateSegments,
            appUsage: appUsage,
            inputActivity: inputActivity,
            focusSessions: focusSessions,
            breakSessions: breakSessions,
            nudges: nudges
        )
    }

    private func configurePetPanelInteractions() {
        petPanel.setInteractions(PetPanelInteractions(
            showStatusBubble: { [weak self] in self?.showPetStatusBubble() },
            openDashboard: { [weak self] in self?.openDashboard(tab: .today) },
            openSettings: { [weak self] in self?.openDashboard(tab: .pet) },
            startBreak: { [weak self] in self?.toggleBreakFromPet() },
            pauseReminders: { [weak self] in self?.pauseReminders() },
            cycleIntentAction: { [weak self] in self?.cycleCurrentIntentSourceAction() },
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

    private func cycleCurrentIntentSourceAction() {
        guard let record = selectedPetPackRecord() else {
            return
        }

        let intent = currentPetIntentKind
        let actions = record.playableSourceActions.filter {
            !record.frameURLs(forSourceActionID: $0.id).isEmpty
        }
        guard actions.count > 1 else {
            return
        }

        let currentID = settings.pet.sourceActionID(for: intent, packID: record.id)
            ?? resolvedSourceAction(for: intent, in: record)?.id
        let currentIndex = currentID.flatMap { id in
            actions.firstIndex { $0.id == id }
        } ?? -1
        let next = actions[(currentIndex + 1) % actions.count]
        settings.pet.setSourceActionID(next.id, for: intent, packID: record.id)
        transientPetIntent = intent
        transientPetIntentSource = .interaction
        transientPetIntentExpiresAt = Date().addingTimeInterval(2.4)
        petAnimationIdentity = nil
        showTransientPetMessage("\(intent.title)：\(next.title)", seconds: 2.4)
        save()
        clearTransientPetIntent(after: 2.4)
    }

    private func resolvedPetIntent(now: Date) -> PetIntent {
        let stateIntent = PetIntent(
            kind: behaviorPolicy.intentKind(
                for: currentDecision.state,
                previousState: previousState,
                now: now
            ),
            source: .state,
            startedAt: stableStateSince
        )

        if let transient = currentTransientIntent(now: now),
           transient.source == .physicalInteraction {
            return transient
        }

        if let nudgeIntent = currentNudgeIntent(now: now) {
            return nudgeIntent
        }

        if let transient = currentTransientIntent(now: now) {
            return transient
        }

        return stateIntent
    }

    private func currentNudgeIntent(now: Date) -> PetIntent? {
        guard let latest = nudges.last,
              now.timeIntervalSince(latest.time) <= behaviorPolicy.nudgeActionVisibleSeconds else {
            return nil
        }

        return PetIntent(
            kind: latest.petIntent,
            source: .nudge,
            startedAt: latest.time,
            expiresAt: latest.time.addingTimeInterval(behaviorPolicy.nudgeActionVisibleSeconds),
            message: latest.message
        )
    }

    private func currentTransientIntent(now: Date) -> PetIntent? {
        guard let transientPetIntent else { return nil }
        if let transientPetIntentExpiresAt, transientPetIntentExpiresAt <= now {
            self.transientPetIntent = nil
            self.transientPetIntentExpiresAt = nil
            self.transientPetIntentSource = .interaction
            return nil
        }

        return PetIntent(
            kind: transientPetIntent,
            source: transientPetIntentSource,
            expiresAt: transientPetIntentExpiresAt,
            interruptible: transientPetIntentSource != .physicalInteraction
        )
    }

    private func hoverIntent(for intent: PetIntentKind) -> PetIntentKind {
        switch intent {
        case .sleep, .breakCompanion, .breakEnding:
            return .quietCompanion
        default:
            return .welcomeBack
        }
    }

    private func playPetSourceActionSoundIfNeeded(
        record: PetPackRecord,
        sourceAction: PetSourceActionSpec,
        identity: String
    ) {
        guard settings.pet.audioEnabled,
              sourceActionSoundIdentity != identity else {
            return
        }
        sourceActionSoundIdentity = identity

        guard let url = record.audioURL(forSourceActionID: sourceAction.id),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            return
        }

        sourceActionSound?.stop()
        sound.volume = Float(sourceAction.audio?.volume ?? 0.55)
        sound.play()
        sourceActionSound = sound
    }

    private func reasonTitle(_ reason: StateReason) -> String {
        switch reason {
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

    private func clearTransientPetIntent(after seconds: TimeInterval) {
        let expectedIntentExpiresAt = transientPetIntentExpiresAt
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard self.transientPetIntentExpiresAt == expectedIntentExpiresAt else { return }
            self.transientPetIntent = nil
            self.transientPetIntentExpiresAt = nil
            self.transientPetIntentSource = .interaction
            self.updatePet()
        }
    }

    private var stateEngine: StateEngine {
        StateEngine(thresholds: settings.judgment.stateEngineThresholds)
    }

    private var nudgePolicy: NudgePolicy {
        NudgePolicy(thresholds: settings.reminder.nudgePolicyThresholds)
    }
}

private actor SnapshotPersistenceService {
    private let store: LocalStore
    private var lastPersistedSnapshot: LocalStoreSnapshot?

    init(store: LocalStore = LocalStore()) {
        self.store = store
    }

    func replaceBaseline(_ snapshot: LocalStoreSnapshot) {
        lastPersistedSnapshot = snapshot
    }

    func save(_ snapshot: LocalStoreSnapshot) {
        store.saveSnapshot(snapshot, changedFrom: lastPersistedSnapshot)
        lastPersistedSnapshot = snapshot
    }
}

private struct SummaryRefreshResult: Sendable {
    var summary: DailySummary
}

private actor SummaryRefreshService {
    private let summaryBuilder = DailySummaryBuilder()

    func refresh(
        now: Date,
        stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        focusSessions: [FocusSession],
        breakSessions: [BreakSession],
        nudges: [NudgeEvent]
    ) -> SummaryRefreshResult {
        return SummaryRefreshResult(
            summary: summaryBuilder.summary(
                for: now,
                segments: stateSegments,
                appUsage: appUsage,
                focusSessions: focusSessions,
                breakSessions: breakSessions,
                nudges: nudges
            )
        )
    }
}

extension Notification.Name {
    static let focusPetOpenDashboardRequested = Notification.Name("FocusPetOpenDashboardRequested")
}

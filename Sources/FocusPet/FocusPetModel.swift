import AppKit
import AVFoundation
import Combine
import FocusPetCore
import Foundation
import UserNotifications

@MainActor
final class FocusPetModel: ObservableObject {
    @MainActor static let shared = FocusPetModel()

    @Published var isPaused = false
    @Published var runtimeMode: RuntimeMode = .live
    @Published var currentObservation = FocusPetModel.initialObservation
    @Published var currentState = FusedUserState(
        timestamp: Date(),
        userState: .unknown,
        context: .neutral,
        confidence: 0.4,
        reason: ["initializing"],
        stableDurationSeconds: 0
    )
    @Published var rules = FocusRule.defaults
    @Published var reminderHistory: [ReminderDecision] = []
    @Published var stateEvents: [StateEvent] = []
    @Published var todaySummary = DailySummary(
        date: "today",
        totalActiveSeconds: 0,
        focusSeconds: 0,
        entertainmentSeconds: 0,
        offScreenCount: 0,
        lookingDownSeconds: 0,
        longestFocusSeconds: 0,
        reminderCount: 0,
        petEnergy: 0,
        summaryText: "今天还没有形成稳定专注记录。桌宠会先保持安静陪伴。"
    )
    @Published var cameraAuthorization: AVAuthorizationStatus = .notDetermined
    @Published var cameraIsRunning = false
    @Published var latestCameraFrameAt: Date?
    @Published var cameraFrameCount = 0
    @Published var latestFaceDetectionReason = "no_camera_frame"
    @Published var frontAppName = "Focus Pet"
    @Published var frontAppBundleID: String?
    @Published var petOpacity = 0.94
    @Published var petScale = 1.0
    @Published var petAnimationEnabled = true
    @Published var petHidden = false
    @Published var soundEnabled = false
    @Published var hasCompletedOnboarding = false
    @Published var lastReminderMessage = "桌宠会在需要时轻轻提醒你。"
    @Published var localDataBytes = 0
    @Published var localDataStatusMessage = "本地结构化数据会保存在 Application Support/FocusPetV0。"
    @Published var exportedDataURL: URL?
    @Published var faceDetectorStatus = "Apple Vision 本地检测已接入；不保存视频或图片。"

    private let fusionEngine = StateFusionEngine()
    private let ruleEngine = RuleEngine()
    private let reportGenerator = ReportGenerator()
    private let appClassifier = AppContextClassifier()
    private let foregroundAppService = ForegroundAppService()
    private let cameraService = CameraCaptureService()
    private let dataStore = LocalDataStore()
    private let liveStateSource = LiveStateSource()
    private var demoStateSource = DemoStateSource()
    private var stabilityTracker = ObservationStabilityTracker()
    private var latestCameraFrame: CameraFrameMetadata?
    private var latestFaceDetection: FaceDetectionResult?
    private var lastTriggeredAtByRuleID: [String: Date] = [:]
    private var stateTimer: Timer?
    private var hasBootstrapped = false

    var menuBarTitle: String {
        isPaused ? "已暂停" : currentState.userState.title
    }

    var menuBarSymbolName: String {
        isPaused ? "pause.circle.fill" : currentState.userState.statusSymbolName
    }

    var cameraStatusTitle: String {
        switch cameraAuthorization {
        case .authorized: cameraIsRunning ? "摄像头采集中" : "摄像头已授权"
        case .denied: "摄像头被拒绝"
        case .restricted: "摄像头受限制"
        case .notDetermined: "等待授权"
        @unknown default: "未知权限"
        }
    }

    var recentStateDescription: String {
        "\(currentState.userState.title) · \(currentState.reason.joined(separator: " · "))"
    }

    var privacyCommitments: [String] {
        [
            "摄像头画面只在本机处理",
            "默认不保存任何视频或图片",
            "不会上传摄像头画面",
            "不会做人脸身份识别",
            "用户可以随时暂停检测",
            "用户可以一键删除本地数据"
        ]
    }

    private init() {
        let settings = dataStore.loadSettings()
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        runtimeMode = settings.runtimeMode
        isPaused = settings.isPaused
        petOpacity = settings.petOpacity
        petScale = settings.petScale
        petAnimationEnabled = settings.petAnimationEnabled
        soundEnabled = settings.soundEnabled
        rules = dataStore.loadRules()
        reminderHistory = dataStore.loadReminders()
        stateEvents = dataStore.loadStateEvents()
        currentState = fusionEngine.fuse(currentObservation)
        refreshSummary()
        localDataBytes = dataStore.currentDataSize()
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        configureCameraFrameHandler()
        refreshFrontApp()
        refreshSummary()
        updatePetWindowAppearance()

        if !isPaused {
            startCameraIfAuthorized()
        }
    }

    func startStateLoop() {
        guard stateTimer == nil else { return }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStateTick()
            }
        }
        stateTimer?.tolerance = 0.6
    }

    func stopStateLoop() {
        stateTimer?.invalidate()
        stateTimer = nil
    }

    func setRuntimeMode(_ mode: RuntimeMode) {
        guard runtimeMode != mode else { return }
        runtimeMode = mode
        stabilityTracker = ObservationStabilityTracker()
        localDataStatusMessage = mode == .live
            ? "已切换到真实检测，Demo 事件不会计入今日指标。"
            : "已切换到 Demo，Demo 事件会单独标记，不会计入真实报告指标。"
        persistSettings()
    }

    func togglePause() {
        isPaused.toggle()

        if isPaused {
            cameraService.stop { [weak self] running in
                self?.cameraIsRunning = running
            }
            setPausedState(reason: "manual_pause")
            lastReminderMessage = "检测已暂停，摄像头已停止采集。"
        } else {
            startCameraIfAuthorized()
            lastReminderMessage = "检测已恢复，会继续使用低打扰提醒。"
            advanceStateTick()
        }

        persistSettings()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        persistSettings()
    }

    func requestCameraPermission() {
        CameraPermissionService.requestCameraAccess { [weak self] status in
            Task { @MainActor in
                self?.cameraAuthorization = status
                self?.startCameraIfAuthorized()
            }
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func togglePetVisibility() {
        petHidden.toggle()
        if petHidden {
            PetWindowController.shared.hide()
        } else {
            PetWindowController.shared.show(model: self)
        }
    }

    func updatePetWindowAppearance() {
        PetWindowController.shared.setOpacity(petOpacity)
        PetWindowController.shared.setScale(petScale)
        persistSettings()
    }

    func simulate(_ state: UserState) {
        if runtimeMode != .demo {
            setRuntimeMode(.demo)
        }

        let context = runtimeContext(now: Date())
        var observation = demoStateSource.observation(
            for: state,
            from: context,
            reasonOverride: demoStateSource.reasonOverride(for: state)
        )
        observation = stabilityTracker.observationWithUpdatedStability(observation)
        ingestObservation(observation, reasonOverride: demoStateSource.reasonOverride(for: state))
    }

    func markLatestReminderAsMistake() {
        guard !reminderHistory.isEmpty else { return }
        lastReminderMessage = "已记录为误判，后续同类提醒会更克制。"
    }

    func saveRules() {
        dataStore.saveRules(rules)
        localDataBytes = dataStore.currentDataSize()
        localDataStatusMessage = "规则已保存到本地 JSON。"
    }

    func saveLocalSnapshot() {
        dataStore.saveStateEvents(stateEvents)
        dataStore.saveReminders(reminderHistory)
        localDataBytes = dataStore.currentDataSize()
    }

    func deleteAllLocalData() {
        dataStore.deleteAll()
        stateEvents = []
        reminderHistory = []
        lastTriggeredAtByRuleID = [:]
        exportedDataURL = nil
        refreshSummary()
        localDataBytes = dataStore.currentDataSize()
        localDataStatusMessage = "本地结构化数据已删除；不会自动回填 Demo seed 数据。"
        lastReminderMessage = "本地结构化数据已删除。"
    }

    func exportLocalData() {
        exportedDataURL = dataStore.exportSnapshot(
            stateEvents: stateEvents,
            reminders: reminderHistory,
            rules: rules,
            settings: appSettings(),
            summary: todaySummary
        )
        localDataBytes = dataStore.currentDataSize()
        localDataStatusMessage = exportedDataURL.map { "已导出到 \($0.path)" } ?? "导出失败。"
    }

    private func configureCameraFrameHandler() {
        cameraService.setFrameHandler { [weak self] frame, detection in
            Task { @MainActor in
                self?.latestCameraFrame = frame
                self?.latestFaceDetection = detection
                self?.latestCameraFrameAt = frame.timestamp
                self?.cameraFrameCount = frame.sequenceNumber
                self?.latestFaceDetectionReason = detection?.reason ?? "no_face_detection_result"
            }
        }
    }

    private func startCameraIfAuthorized() {
        guard cameraAuthorization == .authorized, !isPaused else { return }
        cameraService.start { [weak self] running in
            self?.cameraIsRunning = running
        }
    }

    private func advanceStateTick() {
        guard !isPaused else { return }
        refreshFrontApp()

        let context = runtimeContext(now: Date())
        var observation: StateObservation

        switch runtimeMode {
        case .live:
            observation = liveStateSource.observation(from: context)
        case .demo:
            observation = demoStateSource.nextObservation(from: context)
        }

        observation = stabilityTracker.observationWithUpdatedStability(observation)
        ingestObservation(observation, reasonOverride: nil)
    }

    private func refreshFrontApp() {
        let frontApp = foregroundAppService.frontmostApplication()
        frontAppName = frontApp.name
        frontAppBundleID = frontApp.bundleID
    }

    private func runtimeContext(now: Date) -> RuntimeInputContext {
        let classifiedContext = appClassifier.classify(appName: frontAppName, bundleID: frontAppBundleID)

        return RuntimeInputContext(
            timestamp: now,
            frontAppName: frontAppName,
            frontAppBundleID: frontAppBundleID,
            context: classifiedContext,
            lastInputSeconds: InputActivityService.lastInputSeconds(),
            cameraAuthorization: CameraAuthorizationState(cameraAuthorization),
            cameraRunning: cameraIsRunning,
            latestFrame: latestCameraFrame,
            latestFaceDetection: latestFaceDetection
        )
    }

    private func ingestObservation(_ observation: StateObservation, reasonOverride: String?) {
        guard !isPaused else { return }

        currentObservation = observation

        var fused = fusionEngine.fuse(observation)
        if let reasonOverride {
            fused = FusedUserState(
                timestamp: fused.timestamp,
                userState: fused.userState,
                context: fused.context,
                confidence: max(fused.confidence, 0.8),
                reason: [reasonOverride],
                stableDurationSeconds: fused.stableDurationSeconds
            )
        }

        currentState = fused
        appendEvent(for: fused, sourceKind: observation.sourceKind)
        evaluateRules(for: fused, now: observation.timestamp)
        refreshSummary()
        saveLocalSnapshot()
    }

    private func setPausedState(reason: String) {
        let now = Date()
        currentObservation = StateObservation(
            timestamp: now,
            sourceKind: runtimeMode.sourceKind,
            facePresence: .unknown,
            gazeState: .unknown,
            headPitchDegrees: 0,
            frontAppName: frontAppName,
            context: .neutral,
            lastInputSeconds: InputActivityService.lastInputSeconds(),
            stableDurationSeconds: 0
        )
        currentState = FusedUserState(
            timestamp: now,
            userState: .unknown,
            context: .neutral,
            confidence: 0,
            reason: [reason],
            stableDurationSeconds: 0
        )
    }

    private func appendEvent(for state: FusedUserState, sourceKind: ObservationSourceKind) {
        let duration = max(3, Int(min(state.stableDurationSeconds, 600)))
        let event = StateEvent(
            id: UUID().uuidString,
            sourceKind: sourceKind,
            startTime: state.timestamp.addingTimeInterval(TimeInterval(-duration)),
            endTime: state.timestamp,
            userState: state.userState,
            context: state.context,
            confidence: state.confidence,
            reason: state.reason
        )
        stateEvents.append(event)

        if stateEvents.count > 240 {
            stateEvents.removeFirst(stateEvents.count - 240)
        }
    }

    private func evaluateRules(for state: FusedUserState, now: Date) {
        let decisions = ruleEngine.evaluate(
            rules: rules,
            state: state,
            now: now,
            lastTriggeredAtByRuleID: lastTriggeredAtByRuleID,
            isPaused: isPaused
        )

        for decision in decisions {
            reminderHistory.insert(decision, at: 0)
            lastTriggeredAtByRuleID[decision.ruleID] = decision.triggeredAt
            lastReminderMessage = decision.action.message
            if decision.action.type == .systemNotification {
                NotificationService.send(title: "Focus Pet", body: decision.action.message)
            }
        }

        if reminderHistory.count > 30 {
            reminderHistory.removeLast(reminderHistory.count - 30)
        }
    }

    private func refreshSummary() {
        todaySummary = reportGenerator.makeDailySummary(
            for: Date(),
            events: stateEvents,
            reminderCount: reminderHistory.count,
            petEnergy: min(99, stateEvents.filter { $0.sourceKind == .live && $0.userState == .focused }.count * 3)
        )
    }

    private func persistSettings() {
        dataStore.saveSettings(appSettings())
        localDataBytes = dataStore.currentDataSize()
    }

    private func appSettings() -> AppSettings {
        AppSettings(
            hasCompletedOnboarding: hasCompletedOnboarding,
            runtimeMode: runtimeMode,
            isPaused: isPaused,
            petOpacity: petOpacity,
            petScale: petScale,
            petAnimationEnabled: petAnimationEnabled,
            soundEnabled: soundEnabled
        )
    }

    private static let initialObservation = StateObservation(
        timestamp: Date(),
        sourceKind: .live,
        facePresence: .unknown,
        gazeState: .unknown,
        headPitchDegrees: 0,
        frontAppName: "Focus Pet",
        context: .neutral,
        lastInputSeconds: 0,
        stableDurationSeconds: 0
    )
}

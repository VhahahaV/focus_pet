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
    @Published var currentObservation: StateObservation
    @Published var currentState: FusedUserState
    @Published var rules = FocusRule.defaults
    @Published var reminderHistory: [ReminderDecision] = []
    @Published var stateEvents: [StateEvent] = []
    @Published var todaySummary: DailySummary
    @Published var cameraAuthorization: AVAuthorizationStatus = .notDetermined
    @Published var cameraIsRunning = false
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
    @Published var exportedDataURL: URL?

    private let fusionEngine = StateFusionEngine()
    private let ruleEngine = RuleEngine()
    private let reportGenerator = ReportGenerator()
    private let appClassifier = AppContextClassifier()
    private let foregroundAppService = ForegroundAppService()
    private let cameraService = CameraCaptureService()
    private let dataStore = LocalDataStore()
    private var lastTriggeredAtByRuleID: [String: Date] = [:]
    private var demoTimer: Timer?
    private var tickIndex = 0

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
        let initialObservation = StateObservation(
            timestamp: Date(),
            facePresent: true,
            gazeState: .screen,
            headPitchDegrees: 3,
            frontAppName: "Focus Pet",
            context: .work,
            lastInputSeconds: 0,
            stableDurationSeconds: 10
        )
        currentObservation = initialObservation
        currentState = fusionEngine.fuse(initialObservation)
        todaySummary = reportGenerator.makeDailySummary(
            for: Date(),
            events: [],
            reminderCount: 0,
            petEnergy: 0
        )
    }

    func bootstrap() async {
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        hasCompletedOnboarding = dataStore.hasCompletedOnboarding
        stateEvents = dataStore.loadStateEvents()
        if stateEvents.isEmpty {
            stateEvents = DemoFixtures.seedEvents(now: Date())
        }
        refreshFrontApp()
        refreshSummary()
        localDataBytes = dataStore.currentDataSize()
    }

    func startDemoLoop() {
        guard demoTimer == nil else { return }
        demoTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceDemoTick()
            }
        }
        demoTimer?.tolerance = 0.8
    }

    func stopDemoLoop() {
        demoTimer?.invalidate()
        demoTimer = nil
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            cameraService.stop()
            cameraIsRunning = false
            applyDemoState(.away, stableDuration: 0, reasonOverride: "manual_pause")
            lastReminderMessage = "检测已暂停，摄像头已停止采集。"
        } else {
            startCameraIfAuthorized()
            applyDemoState(.focused, stableDuration: 10, reasonOverride: "manual_resume")
            lastReminderMessage = "检测已恢复，会继续使用低打扰提醒。"
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        dataStore.saveHasCompletedOnboarding(true)
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
    }

    func simulate(_ state: UserState) {
        switch state {
        case .focused:
            applyDemoState(.focused, stableDuration: 600, reasonOverride: "manual_demo_focus")
        case .possiblyDistracted:
            applyDemoState(.possiblyDistracted, stableDuration: 34, reasonOverride: "manual_demo_distracted")
        case .lookingDown:
            applyDemoState(.lookingDown, stableDuration: 140, reasonOverride: "manual_demo_posture")
        case .entertainment:
            applyDemoState(.entertainment, stableDuration: 1_260, reasonOverride: "manual_demo_entertainment")
        case .away:
            applyDemoState(.away, stableDuration: 30, reasonOverride: "manual_demo_away")
        default:
            applyDemoState(.unknown, stableDuration: 0, reasonOverride: "manual_demo_unknown")
        }
    }

    func markLatestReminderAsMistake() {
        guard !reminderHistory.isEmpty else { return }
        lastReminderMessage = "已记录为误判，后续同类提醒会更克制。"
    }

    func saveLocalSnapshot() {
        dataStore.saveStateEvents(stateEvents)
        localDataBytes = dataStore.currentDataSize()
    }

    func deleteAllLocalData() {
        dataStore.deleteAll()
        stateEvents = []
        reminderHistory = []
        lastTriggeredAtByRuleID = [:]
        refreshSummary()
        localDataBytes = dataStore.currentDataSize()
        lastReminderMessage = "本地结构化数据已删除。"
    }

    func exportLocalData() {
        exportedDataURL = dataStore.exportSnapshot(
            stateEvents: stateEvents,
            reminders: reminderHistory,
            summary: todaySummary
        )
        localDataBytes = dataStore.currentDataSize()
    }

    private func startCameraIfAuthorized() {
        guard cameraAuthorization == .authorized, !isPaused else { return }
        cameraService.start()
        cameraIsRunning = cameraService.isRunning
    }

    private func advanceDemoTick() {
        guard !isPaused else { return }

        refreshFrontApp()
        tickIndex += 1

        let scriptedState: UserState
        switch tickIndex % 10 {
        case 0, 1, 2, 3:
            scriptedState = .focused
        case 4:
            scriptedState = .possiblyDistracted
        case 5:
            scriptedState = .offScreen
        case 6:
            scriptedState = .lookingDown
        case 7:
            scriptedState = .entertainment
        case 8:
            scriptedState = .away
        default:
            scriptedState = .focused
        }

        applyDemoState(scriptedState, stableDuration: scriptedDuration(for: scriptedState), reasonOverride: nil)
    }

    private func refreshFrontApp() {
        let frontApp = foregroundAppService.frontmostApplication()
        frontAppName = frontApp.name
        frontAppBundleID = frontApp.bundleID
    }

    private func applyDemoState(_ userState: UserState, stableDuration: TimeInterval, reasonOverride: String?) {
        let now = Date()
        let context = contextForDemoState(userState)
        let observation = StateObservation(
            timestamp: now,
            facePresent: userState != .away,
            gazeState: gazeForDemoState(userState),
            headPitchDegrees: userState == .lookingDown ? 32 : 4,
            frontAppName: frontAppName,
            context: context,
            lastInputSeconds: InputActivityService.lastInputSeconds(),
            stableDurationSeconds: stableDuration
        )
        currentObservation = observation

        var fused = fusionEngine.fuse(observation)
        if let reasonOverride {
            fused = FusedUserState(
                timestamp: fused.timestamp,
                userState: userState,
                context: context,
                confidence: max(fused.confidence, 0.8),
                reason: [reasonOverride],
                stableDurationSeconds: stableDuration
            )
        }
        currentState = fused

        appendEvent(for: fused)
        evaluateRules(for: fused, now: now)
        refreshSummary()
        saveLocalSnapshot()
    }

    private func appendEvent(for state: FusedUserState) {
        let duration = max(4, Int(min(state.stableDurationSeconds, 600)))
        let event = StateEvent(
            id: UUID().uuidString,
            startTime: state.timestamp.addingTimeInterval(TimeInterval(-duration)),
            endTime: state.timestamp,
            userState: state.userState,
            context: state.context,
            confidence: state.confidence,
            reason: state.reason
        )
        stateEvents.append(event)

        if stateEvents.count > 160 {
            stateEvents.removeFirst(stateEvents.count - 160)
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
            petEnergy: min(99, stateEvents.filter { $0.userState == .focused }.count * 3)
        )
    }

    private func contextForDemoState(_ state: UserState) -> ContextType {
        switch state {
        case .entertainment:
            .entertainment
        case .meeting:
            .meeting
        case .away:
            .neutral
        default:
            appClassifier.classify(appName: frontAppName, bundleID: frontAppBundleID) == .neutral
                ? .work
                : appClassifier.classify(appName: frontAppName, bundleID: frontAppBundleID)
        }
    }

    private func gazeForDemoState(_ state: UserState) -> GazeState {
        switch state {
        case .focused, .meeting, .resting:
            .screen
        case .possiblyDistracted, .offScreen:
            .offScreen
        case .lookingDown:
            .down
        case .away, .unknown:
            .unknown
        case .entertainment:
            .screen
        }
    }

    private func scriptedDuration(for state: UserState) -> TimeInterval {
        switch state {
        case .focused:
            900
        case .possiblyDistracted:
            24
        case .offScreen:
            34
        case .lookingDown:
            130
        case .entertainment:
            1_260
        case .away:
            28
        default:
            6
        }
    }
}

enum DemoFixtures {
    static func seedEvents(now: Date) -> [StateEvent] {
        [
            StateEvent(
                id: "seed-focus-morning",
                startTime: now.addingTimeInterval(-9_600),
                endTime: now.addingTimeInterval(-7_080),
                userState: .focused,
                context: .work,
                confidence: 0.91,
                reason: ["seed_focus_block"]
            ),
            StateEvent(
                id: "seed-offscreen",
                startTime: now.addingTimeInterval(-6_300),
                endTime: now.addingTimeInterval(-6_240),
                userState: .offScreen,
                context: .work,
                confidence: 0.82,
                reason: ["seed_off_screen"]
            ),
            StateEvent(
                id: "seed-looking-down",
                startTime: now.addingTimeInterval(-5_100),
                endTime: now.addingTimeInterval(-4_860),
                userState: .lookingDown,
                context: .work,
                confidence: 0.86,
                reason: ["seed_posture"]
            ),
            StateEvent(
                id: "seed-entertainment",
                startTime: now.addingTimeInterval(-3_300),
                endTime: now.addingTimeInterval(-2_460),
                userState: .entertainment,
                context: .entertainment,
                confidence: 0.9,
                reason: ["seed_entertainment"]
            )
        ]
    }
}

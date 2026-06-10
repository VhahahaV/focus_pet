import AppKit
import AVFoundation
import Combine
import FocusPetCore
import Foundation
import OSLog
import UserNotifications

@MainActor
final class FocusPetModel: ObservableObject {
    @MainActor static let shared = FocusPetModel()
    private static let faceLog = Logger(subsystem: "local.focuspet.v0", category: "FaceDiagnostics")

    @Published var isPaused = false
    @Published var currentObservation = FocusPetModel.initialObservation
    @Published var currentState = FusedUserState(
        timestamp: Date(),
        userState: .focused,
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
        distractedSeconds: 0,
        awayCount: 0,
        longestFocusSeconds: 0,
        reminderCount: 0,
        petEnergy: 0,
        summaryText: "今天还没有形成稳定专注记录。桌宠会先保持安静陪伴。"
    )
    @Published var cameraAuthorization: AVAuthorizationStatus = .notDetermined
    @Published var cameraSamplingEnabled = false
    @Published var cameraIsRunning = false
    @Published var latestCameraFrameAt: Date?
    @Published var cameraFrameCount = 0
    @Published var latestFaceDetectionReason = "no_camera_frame"
    @Published var frontAppName = "Focus Pet"
    @Published var frontAppBundleID: String?
    @Published var frontWindowTitle: String?
    @Published var currentLocalActivity = LocalActivitySnapshot.legacy(lastInputSeconds: 0)
    @Published var currentContextClassification = AppContextClassification.neutral
    @Published var petOpacity = 0.94
    @Published var petScale = 1.0
    @Published var petAnimationEnabled = true
    @Published var petHidden = false
    @Published var petHiddenUntil: Date?
    @Published var petSize = 128.0
    @Published var petPlacementMode: PetPlacementMode = .dockAttached
    @Published var petManualOrigin: CGPoint?
    @Published var petHoverMenuEnabled = true
    @Published var petIsHovered = false
    @Published var currentPetBehavior: PetBehaviorState = .sleeping
    @Published var currentPetAction: PetAction = .sleep
    @Published var currentPetBubble: PetBubble?
    @Published var selectedPetPackID = PetPackDefaults.luoXiaoHeiLocalID
    @Published var availablePetPacks: [PetPackRecord] = []
    @Published var petImportResult: PetPackValidationResult?
    @Published var petImportErrorMessage: String?
    @Published var currentPetCatalog = PetResourceLoader.loadBundledPack(id: PetPackDefaults.focusDinoID)
    @Published var selectedDashboardTab: DashboardTab = .today
    @Published var soundEnabled = false
    @Published var hasCompletedOnboarding = false
    @Published var lastReminderMessage = "桌宠会在需要时轻轻提醒你。"
    @Published var localDataBytes = 0
    @Published var localDataStatusMessage = "本地结构化数据会保存在 Application Support/FocusPetV0。"
    @Published var exportedDataURL: URL?
    @Published var faceDiagnostics: [FaceDiagnosticEntry] = []
    @Published var dataRetentionStatusMessage = "本地数据会自动回收：状态事件最多 720 条、提醒最多 80 条、判断日志最多 180 条。"
    @Published var pauseUntil: Date?

    private let fusionEngine = StateFusionEngine()
    private let ruleEngine = RuleEngine()
    private let reportGenerator = ReportGenerator()
    private let eventAccumulator = StateEventAccumulator()
    private let appClassifier = AppContextClassifier()
    private let foregroundAppService = ForegroundAppService()
    private let cameraService = CameraCaptureService()
    private let dataStore = LocalDataStore()
    private let liveStateSource = LiveStateSource()
    private let petEngine = PetEngine()
    private let stateLoopIntervalSeconds: TimeInterval = 10
    private let snapshotPersistIntervalSeconds: TimeInterval = 180
    private let diagnosticMemoryLimit = 180
    private let duplicateDiagnosticWindowSeconds: TimeInterval = 18
    private let diagnosticOSLogIntervalSeconds: TimeInterval = 30
    private var stabilityTracker = ObservationStabilityTracker()
    private var latestCameraFrame: CameraFrameMetadata?
    private var latestFaceDetection: FaceDetectionResult?
    private var frontAppIdentity: String?
    private var windowTitleIdentity: String?
    private var frontAppStableSince: Date?
    private var windowTitleStableSince: Date?
    private var lastFrontAppSwitchAt: Date?
    private var lastTriggeredAtByRuleID: [String: Date] = [:]
    private var lastSnapshotPersistAt: Date?
    private var lastDiagnosticOSLogAt = Date.distantPast
    private var stateTimer: Timer?
    private var pauseResumeTimer: Timer?
    private var petVisibilityTimer: Timer?
    private var hasBootstrapped = false

    var menuBarTitle: String {
        isPaused ? "已暂停" : currentState.userState.title
    }

    var menuBarSymbolName: String {
        isPaused ? "pause.circle.fill" : currentState.userState.statusSymbolName
    }

    var cameraStatusTitle: String {
        guard cameraSamplingEnabled else { return "视觉辅助已关闭" }
        return switch cameraAuthorization {
        case .authorized: cameraIsRunning ? "摄像头采集中" : "摄像头已授权"
        case .denied: "摄像头被拒绝"
        case .restricted: "摄像头受限制"
        case .notDetermined: "等待授权"
        @unknown default: "未知权限"
        }
    }

    var faceDetectorStatus: String {
        guard cameraSamplingEnabled else {
            return "摄像头采集已关闭；当前只使用前台应用、窗口标题即时分类和输入空闲时间。"
        }

        switch cameraAuthorization {
        case .authorized:
            return cameraIsRunning
                ? "已叠加 Apple Vision 本地视觉判断；同时使用前台应用、窗口标题即时分类和输入空闲时间。"
                : "摄像头已授权但未采集；当前仍使用本地活动判断。"
        case .denied, .restricted:
            return "摄像头未参与判断；当前只使用本地前台应用、窗口标题即时分类和输入空闲时间。"
        case .notDetermined:
            return "尚未授权摄像头；授权前只使用本地活动判断。"
        @unknown default:
            return "摄像头权限未知；优先使用本地活动判断。"
        }
    }

    var observationSourceTitle: String {
        cameraSamplingEnabled && cameraIsRunning ? "视觉 + 本地活动" : "本地活动"
    }

    var localActivitySummary: String {
        if currentLocalActivity.lastKeyboardSeconds <= 30 {
            return "键盘 \(Self.compactSeconds(currentLocalActivity.lastKeyboardSeconds))"
        }
        if currentLocalActivity.lastMouseSeconds <= 30 {
            return "鼠标 \(Self.compactSeconds(currentLocalActivity.lastMouseSeconds))"
        }
        if currentLocalActivity.lastScrollSeconds <= 30 {
            return "滚动 \(Self.compactSeconds(currentLocalActivity.lastScrollSeconds))"
        }
        return "空闲 \(Self.compactSeconds(currentLocalActivity.lastInputSeconds))"
    }

    var appStabilitySummary: String {
        "\(currentContextClassification.context.title) · \(Self.compactSeconds(currentLocalActivity.frontAppStableSeconds))"
    }

    var currentPetPackName: String {
        currentPetCatalog.pack?.name
            ?? availablePetPacks.first(where: { $0.id == selectedPetPackID })?.pack.name
            ?? "Focus Pet"
    }

    var recentStateDescription: String {
        "\(currentState.userState.title) · \(currentState.reason.joined(separator: " · "))"
    }

    var pauseStatusTitle: String {
        guard isPaused else { return "检测运行中" }

        if let pauseUntil {
            return "暂停至 \(pauseUntil.formatted(date: .omitted, time: .shortened))"
        }

        return "已手动暂停"
    }

    var privacyCommitments: [String] {
        [
            "画面只在本机处理",
            "不保存视频或图片",
            "不上传摄像头画面",
            "不做人脸身份识别",
            "可随时暂停检测",
            "可一键删除数据"
        ]
    }

    private init() {
        let settings = dataStore.loadSettings()
        let now = Date()
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        pauseUntil = settings.pauseUntil.flatMap { $0 > now ? $0 : nil }
        isPaused = settings.isPaused && (pauseUntil != nil || settings.pauseUntil == nil)
        petOpacity = settings.petOpacity
        petScale = settings.petScale
        petAnimationEnabled = settings.petAnimationEnabled
        petHiddenUntil = settings.petHiddenUntil.flatMap { $0 > now ? $0 : nil }
        petHidden = settings.petHidden && (petHiddenUntil != nil || settings.petHiddenUntil == nil)
        petSize = Self.clampedPetSize(settings.petSize)
        petPlacementMode = settings.petPlacementMode
        if let x = settings.petManualOriginX, let y = settings.petManualOriginY {
            petManualOrigin = CGPoint(x: x, y: y)
        }
        petHoverMenuEnabled = settings.petHoverMenuEnabled
        cameraSamplingEnabled = settings.cameraSamplingEnabled
        soundEnabled = settings.soundEnabled
        selectedPetPackID = settings.selectedPetPackID
        rules = dataStore.loadRules()
        reminderHistory = dataStore.loadReminders()
        lastTriggeredAtByRuleID = Self.lastTriggeredMap(from: reminderHistory)
        stateEvents = dataStore.loadStateEvents()
        faceDiagnostics = dataStore.loadFaceDiagnostics()
        currentState = fusionEngine.fuse(currentObservation)
        reclaimLocalData(reason: "启动回收", persist: true)
        refreshSummary()
        localDataBytes = dataStore.currentDataSize()
        installGeneratedLuoXiaoHeiPackIfAvailable()
        refreshPetPacks()

        updatePetState(previousState: nil, latestReminder: nil)

        if dataStore.settingsContainsLegacyRuntimeMode()
            || settings.pauseUntil != pauseUntil
            || settings.isPaused != isPaused
            || settings.petHiddenUntil != petHiddenUntil
            || settings.petHidden != petHidden
            || settings.selectedPetPackID != selectedPetPackID {
            persistSettings()
        }
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        configureCameraFrameHandler()
        refreshFrontApp(now: Date())
        refreshSummary()
        restorePetIfHiddenExpired()
        updatePetWindowAppearance()
        schedulePetVisibilityTimerIfNeeded()

        if !isPaused, cameraSamplingEnabled {
            startCameraIfAuthorized()
        } else {
            clearCameraSignal(reason: cameraSamplingEnabled ? "camera_paused" : "camera_sampling_disabled")
            schedulePauseResumeTimerIfNeeded()
        }
    }

    func startStateLoop() {
        guard stateTimer == nil else { return }
        stateTimer = Timer.scheduledTimer(withTimeInterval: stateLoopIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStateTick()
            }
        }
        stateTimer?.tolerance = 1.0
    }

    func stopStateLoop() {
        saveLocalSnapshot(force: true)
        stateTimer?.invalidate()
        stateTimer = nil
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        petVisibilityTimer?.invalidate()
        petVisibilityTimer = nil
    }

    func togglePause() {
        if isPaused {
            resumeDetection()
        } else {
            pauseDetection(until: nil)
        }
    }

    func pauseForTwentyFiveMinutes() {
        pauseDetection(until: Date().addingTimeInterval(25 * 60))
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        persistSettings()
    }

    func requestCameraPermission() {
        cameraSamplingEnabled = true
        persistSettings()
        CameraPermissionService.requestCameraAccess { [weak self] status in
            Task { @MainActor in
                self?.cameraAuthorization = status
                self?.startCameraIfAuthorized()
            }
        }
    }

    func setCameraSamplingEnabled(_ enabled: Bool) {
        guard cameraSamplingEnabled != enabled else { return }
        cameraSamplingEnabled = enabled
        stabilityTracker = ObservationStabilityTracker()

        if enabled {
            latestFaceDetectionReason = "camera_sampling_enabled"
            if cameraAuthorization != .authorized {
                persistSettings()
                advanceStateTick()
                return
            }
            startCameraIfAuthorized()
        } else {
            stopCameraSampling(reason: "camera_sampling_disabled")
        }

        persistSettings()
        advanceStateTick()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func togglePetVisibility() {
        if petHidden {
            showPet()
        } else {
            hidePet(for: nil)
        }
    }

    func hidePet(for duration: TimeInterval?) {
        petHidden = true
        petHiddenUntil = duration.map { Date().addingTimeInterval($0) }
        currentPetBehavior = .hidden
        currentPetAction = .hidden
        currentPetBubble = nil
        PetWindowController.shared.hide()
        schedulePetVisibilityTimerIfNeeded()
        persistSettings()
    }

    func showPet() {
        petHidden = false
        petHiddenUntil = nil
        updatePetState(previousState: nil, latestReminder: nil)
        PetWindowController.shared.show(model: self)
        schedulePetVisibilityTimerIfNeeded()
        persistSettings()
    }

    func setPetPlacement(_ placement: PetPlacementMode) {
        petPlacementMode = placement
        if placement != .manual {
            petManualOrigin = nil
        }
        PetWindowController.shared.refreshLayout(model: self)
        persistSettings()
    }

    func returnPetToDock() {
        setPetPlacement(.dockAttached)
    }

    func setPetSize(_ size: Double) {
        petSize = Self.clampedPetSize(size)
        petScale = petSize / 128
        PetWindowController.shared.setSize(petSize, model: self)
        persistSettings()
    }

    func updatePetWindowAppearance() {
        restorePetIfHiddenExpired()
        if petHidden {
            PetWindowController.shared.hide()
        } else {
            PetWindowController.shared.show(model: self)
            PetWindowController.shared.setOpacity(petOpacity)
            PetWindowController.shared.setSize(petSize, model: self)
        }
        if !petHoverMenuEnabled {
            PetWindowController.shared.hideHoverMenu()
        }
        persistSettings()
    }

    func refreshPetPacks() {
        let store = petPackStore()
        availablePetPacks = store.records()
        if selectedPetPackID == PetPackDefaults.focusDinoID,
           availablePetPacks.contains(where: { $0.id == PetPackDefaults.luoXiaoHeiLocalID }) {
            selectedPetPackID = PetPackDefaults.luoXiaoHeiLocalID
        }
        if !availablePetPacks.contains(where: { $0.id == selectedPetPackID }) {
            selectedPetPackID = availablePetPacks.contains(where: { $0.id == PetPackDefaults.luoXiaoHeiLocalID })
                ? PetPackDefaults.luoXiaoHeiLocalID
                : PetPackDefaults.focusDinoID
        }
        reloadSelectedPetCatalog()
    }

    func selectPetPack(_ id: String) {
        selectedPetPackID = id
        reloadSelectedPetCatalog()
        persistSettings()
    }

    func chooseAndImportPetPack() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"
        panel.message = "选择包含 pet.json 的本地桌宠资源包文件夹。"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPetPack(from: url)
    }

    func importPetPack(from folderURL: URL) {
        do {
            let importer = PetPackImporter(installRootURL: dataStore.ensurePetPacksRoot())
            let imported = try importer.importPack(from: folderURL)
            petImportResult = imported.validation
            petImportErrorMessage = nil
            refreshPetPacks()
            selectPetPack(imported.pack.id)
        } catch {
            petImportErrorMessage = error.localizedDescription
        }
    }

    func openMainWindow(tab: DashboardTab) {
        selectedDashboardTab = tab
        DashboardWindowCoordinator.open(tab)
    }

    func handlePetSingleClick() {
        if currentPetBubble != nil {
            PetWindowController.shared.updateBubble(model: self)
            return
        }

        currentPetAction = currentPetAction == .blink ? .stretch : .blink
        let bubble = petEngine.lightInteractionBubble()
        currentPetBubble = bubble
        PetWindowController.shared.updateBubble(model: self)
        scheduleBubbleDismissal(id: bubble.id, delay: 5)
    }

    func handlePetDoubleClick() {
        openMainWindow(tab: .today)
    }

    func handlePetHoverChanged(_ inside: Bool) {
        guard petIsHovered != inside else { return }
        petIsHovered = inside

        if inside {
            applyHoverPetActionIfNeeded()
        } else if currentPetBehavior == .observing {
            restoreCurrentPetAction()
        }
    }

    func handlePetDragBegan() {
        petIsHovered = false
        currentPetBehavior = .dragged
        currentPetAction = .dragged
        currentPetBubble = nil
        PetWindowController.shared.updateBubble(model: self)
    }

    func handlePetDragEnded(resolution: PetPlacementResolution) {
        petPlacementMode = resolution.mode
        petManualOrigin = resolution.manualOrigin
        currentPetBehavior = .landing
        currentPetAction = .landing
        persistSettings()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.updatePetState(previousState: nil, latestReminder: nil)
        }
    }

    func handlePetBubblePrimaryAction() {
        switch currentPetBubble?.kind {
        case .distracted:
            dismissPetBubble()
        case .entertainment:
            dismissPetBubble()
        case .welcomeBack:
            dismissPetBubble()
        case .light, .none:
            dismissPetBubble()
        }
    }

    func handlePetBubbleSecondaryAction() {
        switch currentPetBubble?.kind {
        case .distracted:
            dismissPetBubble()
        case .entertainment:
            openMainWindow(tab: .today)
            dismissPetBubble()
        case .welcomeBack:
            openMainWindow(tab: .today)
            dismissPetBubble()
        case .light, .none:
            dismissPetBubble()
        }
    }

    func dismissPetBubble() {
        currentPetBubble = nil
        PetWindowController.shared.updateBubble(model: self)
    }

    func saveRules() {
        dataStore.saveRules(rules)
        localDataBytes = dataStore.currentDataSize()
        localDataStatusMessage = "规则已保存到本地 JSON。"
    }

    func saveLocalSnapshot(force: Bool = false) {
        let now = Date()
        if !force,
           let lastSnapshotPersistAt,
           now.timeIntervalSince(lastSnapshotPersistAt) < snapshotPersistIntervalSeconds {
            return
        }

        reclaimLocalData(reason: "定期回收", persist: false)
        dataStore.saveStateEvents(stateEvents)
        dataStore.saveReminders(reminderHistory)
        dataStore.saveFaceDiagnostics(faceDiagnostics)
        lastSnapshotPersistAt = now
        localDataBytes = dataStore.currentDataSize()
    }

    func deleteAllLocalData() {
        dataStore.deleteAll()
        stateEvents = []
        reminderHistory = []
        faceDiagnostics = []
        lastTriggeredAtByRuleID = [:]
        exportedDataURL = nil
        refreshSummary()
        localDataBytes = dataStore.currentDataSize()
        localDataStatusMessage = "本地结构化数据已删除。"
        dataRetentionStatusMessage = "本地数据已清空。"
        lastReminderMessage = "本地结构化数据已删除。"
    }

    func exportLocalData() {
        saveLocalSnapshot(force: true)
        exportedDataURL = dataStore.exportSnapshot(
            stateEvents: stateEvents,
            reminders: reminderHistory,
            faceDiagnostics: faceDiagnostics,
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
                guard let self, !self.isPaused, self.cameraSamplingEnabled else { return }
                self.latestCameraFrame = frame
                self.latestFaceDetection = detection
                self.latestCameraFrameAt = frame.timestamp
                self.cameraFrameCount = frame.sequenceNumber
                self.latestFaceDetectionReason = detection?.reason ?? "no_face_detection_result"
                self.appendFaceDiagnostic(
                    FaceDiagnosticEntry(
                        timestamp: frame.timestamp,
                        phase: .frame,
                        frameSequenceNumber: frame.sequenceNumber,
                        facePresence: detection?.facePresence ?? .unknown,
                        gazeState: detection?.gazeState ?? .unknown,
                        headPitchDegrees: detection?.headPitchDegrees ?? 0,
                        visionConfidence: detection?.confidence ?? 0,
                        fusedState: self.currentState.userState,
                        context: self.currentState.context,
                        stableDurationSeconds: self.currentState.stableDurationSeconds,
                        reason: [detection?.reason ?? "no_face_detection_result"],
                        frontAppName: self.frontAppName,
                        frontWindowTitle: self.frontWindowTitle,
                        localActivity: self.currentLocalActivity,
                        contextConfidence: self.currentContextClassification.confidence,
                        contextReason: self.currentContextClassification.reason
                    )
                )
            }
        }
    }

    private func startCameraIfAuthorized() {
        guard cameraSamplingEnabled, cameraAuthorization == .authorized, !isPaused else {
            if !cameraSamplingEnabled {
                clearCameraSignal(reason: "camera_sampling_disabled")
            }
            return
        }
        cameraService.start { [weak self] running in
            self?.cameraIsRunning = running
        }
    }

    private func advanceStateTick() {
        if let pauseUntil, Date() >= pauseUntil {
            resumeDetection()
            return
        }

        restorePetIfHiddenExpired()

        guard !isPaused else { return }
        let now = Date()
        refreshFrontApp(now: now)

        let context = runtimeContext(now: now)
        var observation = liveStateSource.observation(from: context)
        observation = stabilityTracker.observationWithUpdatedStability(observation)
        ingestObservation(observation, reasonOverride: nil)
    }

    private func refreshFrontApp(now: Date) {
        let frontApp = foregroundAppService.frontmostApplication()
        let newFrontAppIdentity = frontApp.bundleID ?? frontApp.name
        if newFrontAppIdentity != frontAppIdentity {
            frontAppIdentity = newFrontAppIdentity
            frontAppStableSince = now
            lastFrontAppSwitchAt = now
        }

        let newWindowTitleIdentity = frontApp.windowTitle ?? ""
        if newWindowTitleIdentity != windowTitleIdentity {
            windowTitleIdentity = newWindowTitleIdentity
            windowTitleStableSince = now
        }

        frontAppName = frontApp.name
        frontAppBundleID = frontApp.bundleID
        frontWindowTitle = frontApp.windowTitle
    }

    private func runtimeContext(now: Date) -> RuntimeInputContext {
        let classification = appClassifier.classifyDetailed(
            appName: frontAppName,
            bundleID: frontAppBundleID,
            windowTitle: frontWindowTitle
        )
        currentContextClassification = classification

        let frontAppStableSeconds = frontAppStableSince.map { now.timeIntervalSince($0) } ?? 0
        let windowTitleStableSeconds = windowTitleStableSince.map { now.timeIntervalSince($0) } ?? 0
        let lastAppSwitchSeconds = lastFrontAppSwitchAt.map { now.timeIntervalSince($0) } ?? frontAppStableSeconds
        let localActivity = InputActivityService.snapshot(
            lastAppSwitchSeconds: lastAppSwitchSeconds,
            frontAppStableSeconds: frontAppStableSeconds,
            windowTitleStableSeconds: windowTitleStableSeconds
        )
        currentLocalActivity = localActivity

        return RuntimeInputContext(
            timestamp: now,
            frontAppName: frontAppName,
            frontAppBundleID: frontAppBundleID,
            frontWindowTitle: frontWindowTitle,
            context: classification.context,
            lastInputSeconds: localActivity.lastInputSeconds,
            cameraAuthorization: CameraAuthorizationState(cameraAuthorization),
            cameraRunning: cameraSamplingEnabled && cameraIsRunning,
            latestFrame: cameraSamplingEnabled ? latestCameraFrame : nil,
            latestFaceDetection: cameraSamplingEnabled ? latestFaceDetection : nil,
            localActivity: localActivity
        )
    }

    private func ingestObservation(_ observation: StateObservation, reasonOverride: String?) {
        guard !isPaused else { return }

        currentObservation = observation
        let previousState = currentState

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
        appendFaceDiagnostic(
            FaceDiagnosticEntry(
                timestamp: observation.timestamp,
                phase: .fusion,
                frameSequenceNumber: latestCameraFrame?.sequenceNumber,
                facePresence: observation.facePresence,
                gazeState: observation.gazeState,
                headPitchDegrees: observation.headPitchDegrees,
                visionConfidence: fused.confidence,
                fusedState: fused.userState,
                context: fused.context,
                stableDurationSeconds: fused.stableDurationSeconds,
                reason: fused.reason,
                frontAppName: observation.frontAppName,
                frontWindowTitle: frontWindowTitle,
                localActivity: observation.localActivity,
                contextConfidence: currentContextClassification.confidence,
                contextReason: currentContextClassification.reason
            )
        )
        appendEvent(for: fused, sourceKind: observation.sourceKind)
        let decisions = evaluateRules(for: fused, sourceKind: observation.sourceKind, now: observation.timestamp)
        updatePetState(previousState: previousState, latestReminder: decisions.first)
        refreshSummary()
        saveLocalSnapshot()
    }

    private func setPausedState(reason: String) {
        let now = Date()
        currentObservation = StateObservation(
            timestamp: now,
            sourceKind: .live,
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
            userState: .away,
            context: .neutral,
            confidence: 0,
            reason: [reason],
            stableDurationSeconds: 0
        )
        updatePetState(previousState: nil, latestReminder: nil)
    }

    private func appendFaceDiagnostic(_ entry: FaceDiagnosticEntry) {
        if let last = faceDiagnostics.last,
           isRedundantDiagnostic(entry, after: last) {
            return
        }

        faceDiagnostics.append(entry)
        if faceDiagnostics.count > diagnosticMemoryLimit {
            faceDiagnostics.removeFirst(faceDiagnostics.count - diagnosticMemoryLimit)
        }

        guard entry.timestamp.timeIntervalSince(lastDiagnosticOSLogAt) >= diagnosticOSLogIntervalSeconds else { return }
        lastDiagnosticOSLogAt = entry.timestamp

        logFaceDiagnostic(entry)
    }

    private func isRedundantDiagnostic(_ entry: FaceDiagnosticEntry, after last: FaceDiagnosticEntry) -> Bool {
        guard entry.timestamp.timeIntervalSince(last.timestamp) < duplicateDiagnosticWindowSeconds else { return false }
        return entry.phase == last.phase
            && entry.frameSequenceNumber == last.frameSequenceNumber
            && entry.facePresence == last.facePresence
            && entry.gazeState == last.gazeState
            && entry.headPitchDegrees == last.headPitchDegrees
            && entry.fusedState == last.fusedState
            && entry.context == last.context
            && entry.reason == last.reason
            && entry.frontAppName == last.frontAppName
            && entry.frontWindowTitle == last.frontWindowTitle
            && hasSimilarLocalActivity(entry.localActivity, last.localActivity)
    }

    private func hasSimilarLocalActivity(_ lhs: LocalActivitySnapshot?, _ rhs: LocalActivitySnapshot?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return lhs.hasDetailedInputBreakdown == rhs.hasDetailedInputBreakdown
                && activityBucket(lhs.lastInputSeconds) == activityBucket(rhs.lastInputSeconds)
                && activityBucket(lhs.lastKeyboardSeconds) == activityBucket(rhs.lastKeyboardSeconds)
                && activityBucket(lhs.lastMouseSeconds) == activityBucket(rhs.lastMouseSeconds)
                && activityBucket(lhs.lastScrollSeconds) == activityBucket(rhs.lastScrollSeconds)
        default:
            return false
        }
    }

    private func activityBucket(_ seconds: TimeInterval) -> Int {
        Int(max(0, seconds) / 15)
    }

    private func logFaceDiagnostic(_ entry: FaceDiagnosticEntry) {
        let fusedTitle = entry.fusedState?.title ?? "未融合"
        let inputSeconds = entry.localActivity?.lastInputSeconds ?? -1
        Self.faceLog.debug(
            "phase=\(entry.phase.rawValue, privacy: .public) frame=\(entry.frameSequenceNumber ?? -1, privacy: .public) face=\(entry.facePresence.rawValue, privacy: .public) gaze=\(entry.gazeState.rawValue, privacy: .public) pitch=\(entry.headPitchDegrees, privacy: .public) input=\(inputSeconds, privacy: .public) confidence=\(entry.visionConfidence, privacy: .public) state=\(fusedTitle, privacy: .public) reason=\(entry.reason.joined(separator: ","), privacy: .public)"
        )
    }

    private func reclaimLocalData(reason: String, persist: Bool) {
        let reclaimed = dataStore.reclaimLocalData(
            stateEvents: stateEvents,
            reminders: reminderHistory,
            faceDiagnostics: faceDiagnostics
        )
        stateEvents = reclaimed.stateEvents
        reminderHistory = reclaimed.reminders
        faceDiagnostics = reclaimed.faceDiagnostics
        lastTriggeredAtByRuleID = Self.lastTriggeredMap(from: reminderHistory)

        if reclaimed.report.totalRemoved > 0 {
            dataRetentionStatusMessage = "\(reason)：已回收 \(reclaimed.report.totalRemoved) 条记录（状态 \(reclaimed.report.removedStateEvents)、提醒 \(reclaimed.report.removedReminders)、判断日志 \(reclaimed.report.removedFaceDiagnostics)）。"
            if persist {
                dataStore.saveStateEvents(stateEvents)
                dataStore.saveReminders(reminderHistory)
                dataStore.saveFaceDiagnostics(faceDiagnostics)
            }
        } else if reason == "启动回收" {
            dataRetentionStatusMessage = "本地数据已在保留上限内：状态 \(stateEvents.count) 条、提醒 \(reminderHistory.count) 条、判断日志 \(faceDiagnostics.count) 条。"
        }
    }

    private func appendEvent(for state: FusedUserState, sourceKind: ObservationSourceKind) {
        stateEvents = eventAccumulator.recording(state: state, sourceKind: sourceKind, in: stateEvents)
    }

    @discardableResult
    private func evaluateRules(for state: FusedUserState, sourceKind: ObservationSourceKind, now: Date) -> [ReminderDecision] {
        let decisions = ruleEngine.evaluate(
            rules: rules,
            state: state,
            sourceKind: sourceKind,
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

        return decisions
    }

    private func refreshSummary() {
        todaySummary = reportGenerator.makeDailySummary(
            for: Date(),
            events: stateEvents,
            reminderCount: reminderHistory.filter { $0.sourceKind == .live }.count,
            petEnergy: nil
        )
    }

    private func updatePetState(previousState: FusedUserState?, latestReminder: ReminderDecision?) {
        guard !petHidden else {
            currentPetBehavior = .hidden
            currentPetAction = .hidden
            currentPetBubble = nil
            PetWindowController.shared.updateBubble(model: self)
            return
        }

        let behavior = petEngine.behavior(
            for: currentState,
            previousState: previousState,
            latestReminder: latestReminder
        )
        currentPetBehavior = behavior
        currentPetAction = petEngine.action(for: behavior)

        if let bubble = petEngine.bubble(
            for: currentState,
            previousState: previousState,
            latestReminder: latestReminder
        ) {
            currentPetBubble = bubble
            PetWindowController.shared.updateBubble(model: self)
            scheduleBubbleDismissal(id: bubble.id, delay: 8)
        } else if latestReminder == nil, previousState?.userState != .away {
            currentPetBubble = nil
            PetWindowController.shared.updateBubble(model: self)
        }

        applyHoverPetActionIfNeeded()
    }

    private func applyHoverPetActionIfNeeded() {
        guard petIsHovered, !petHidden, currentPetBehavior != .dragged else { return }
        currentPetBehavior = .observing
        currentPetAction = .stretch
    }

    private func restoreCurrentPetAction() {
        guard !petHidden else {
            currentPetBehavior = .hidden
            currentPetAction = .hidden
            return
        }

        let behavior = petEngine.behavior(
            for: currentState,
            previousState: nil,
            latestReminder: nil
        )
        currentPetBehavior = behavior
        currentPetAction = petEngine.action(for: behavior)
    }

    private func scheduleBubbleDismissal(id: String, delay: TimeInterval) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard self?.currentPetBubble?.id == id else { return }
            self?.dismissPetBubble()
        }
    }

    private func restorePetIfHiddenExpired() {
        guard petHidden, let petHiddenUntil, Date() >= petHiddenUntil else { return }
        petHidden = false
        self.petHiddenUntil = nil
        updatePetState(previousState: nil, latestReminder: nil)
        PetWindowController.shared.show(model: self)
        persistSettings()
    }

    private func schedulePetVisibilityTimerIfNeeded() {
        petVisibilityTimer?.invalidate()
        guard petHidden, let petHiddenUntil, petHiddenUntil > Date() else {
            petVisibilityTimer = nil
            return
        }

        petVisibilityTimer = Timer.scheduledTimer(withTimeInterval: max(1, petHiddenUntil.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showPet()
            }
        }
    }

    private func persistSettings() {
        dataStore.saveSettings(appSettings())
        localDataBytes = dataStore.currentDataSize()
    }

    private func appSettings() -> AppSettings {
        AppSettings(
            hasCompletedOnboarding: hasCompletedOnboarding,
            isPaused: isPaused,
            pauseUntil: pauseUntil,
            petOpacity: petOpacity,
            petScale: petScale,
            petAnimationEnabled: petAnimationEnabled,
            petSize: petSize,
            petHidden: petHidden,
            petHiddenUntil: petHiddenUntil,
            petPlacementMode: petPlacementMode,
            petManualOriginX: petManualOrigin.map { Double($0.x) },
            petManualOriginY: petManualOrigin.map { Double($0.y) },
            petHoverMenuEnabled: petHoverMenuEnabled,
            cameraSamplingEnabled: cameraSamplingEnabled,
            soundEnabled: soundEnabled,
            selectedPetPackID: selectedPetPackID
        )
    }

    private func petPackStore() -> PetPackStore {
        PetPackStore(userRootURL: dataStore.ensurePetPacksRoot())
    }

    private func installGeneratedLuoXiaoHeiPackIfAvailable() {
        guard let imported = petPackStore().installGeneratedLuoXiaoHeiPackIfAvailable() else { return }
        petImportResult = imported.validation
        petImportErrorMessage = nil
        if selectedPetPackID == PetPackDefaults.focusDinoID
            || selectedPetPackID == PetPackDefaults.luoXiaoHeiLocalID {
            selectedPetPackID = imported.pack.id
        }
    }

    private func reloadSelectedPetCatalog() {
        if let record = petPackStore().record(id: selectedPetPackID) {
            currentPetCatalog = PetResourceLoader.load(record: record)
        } else {
            currentPetCatalog = PetResourceLoader.loadBundledPack(id: PetPackDefaults.focusDinoID)
        }
    }

    private func pauseDetection(until resumeDate: Date?) {
        isPaused = true
        pauseUntil = resumeDate
        pauseResumeTimer?.invalidate()
        cameraService.stop { [weak self] running in
            self?.cameraIsRunning = running
        }
        clearCameraSignal(reason: "camera_paused")
        setPausedState(reason: resumeDate == nil ? "manual_pause" : "timed_pause")
        lastReminderMessage = resumeDate.map {
            "检测已暂停至 \($0.formatted(date: .omitted, time: .shortened))，摄像头已停止采集。"
        } ?? "检测已暂停，摄像头已停止采集。"
        schedulePauseResumeTimerIfNeeded()
        saveLocalSnapshot(force: true)
        persistSettings()
    }

    private func resumeDetection() {
        isPaused = false
        pauseUntil = nil
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        startCameraIfAuthorized()
        lastReminderMessage = "检测已恢复，会继续使用低打扰提醒。"
        persistSettings()
        advanceStateTick()
    }

    private func stopCameraSampling(reason: String) {
        cameraIsRunning = false
        cameraService.stop { [weak self] running in
            self?.cameraIsRunning = running
        }
        clearCameraSignal(reason: reason)
    }

    private func clearCameraSignal(reason: String) {
        latestCameraFrame = nil
        latestFaceDetection = nil
        latestCameraFrameAt = nil
        latestFaceDetectionReason = reason
    }

    private func schedulePauseResumeTimerIfNeeded() {
        pauseResumeTimer?.invalidate()
        guard let pauseUntil, pauseUntil > Date() else { return }
        pauseResumeTimer = Timer.scheduledTimer(withTimeInterval: pauseUntil.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeDetection()
            }
        }
    }

    private static func lastTriggeredMap(from reminders: [ReminderDecision]) -> [String: Date] {
        reminders
            .filter { $0.sourceKind == .live }
            .reduce(into: [:]) { result, reminder in
                if let existing = result[reminder.ruleID] {
                    result[reminder.ruleID] = max(existing, reminder.triggeredAt)
                } else {
                    result[reminder.ruleID] = reminder.triggeredAt
                }
            }
    }

    private static func clampedPetSize(_ size: Double) -> Double {
        min(max(size, 96), 160)
    }

    private static func compactSeconds(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds.rounded()))秒"
        }

        return "\(Int((seconds / 60).rounded()))分"
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

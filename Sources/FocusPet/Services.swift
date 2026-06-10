import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import FocusPetCore
import Foundation
import ImageIO
import UserNotifications
import Vision

struct FrontApplication: Sendable {
    var name: String
    var bundleID: String?
    var windowTitle: String?
}

struct ForegroundAppService: Sendable {
    func frontmostApplication() -> FrontApplication {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontApplication(
            name: app?.localizedName ?? "Unknown",
            bundleID: app?.bundleIdentifier,
            windowTitle: frontWindowTitle(for: app?.processIdentifier)
        )
    }

    private func frontWindowTitle(for processID: pid_t?) -> String? {
        guard let processID,
              let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        return windowList.first { info in
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            let layer = info[kCGWindowLayer as String] as? Int
            return ownerPID == processID && layer == 0
        }
        .flatMap { info in
            let title = info[kCGWindowName as String] as? String
            return title?.isEmpty == false ? title : nil
        }
    }
}

extension CameraAuthorizationState {
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .unknown
        }
    }
}

enum InputActivityService {
    static func lastInputSeconds() -> TimeInterval {
        snapshot().lastInputSeconds
    }

    static func snapshot(
        lastAppSwitchSeconds: TimeInterval = 0,
        frontAppStableSeconds: TimeInterval = 0,
        windowTitleStableSeconds: TimeInterval = 0
    ) -> LocalActivitySnapshot {
        let keyboard = secondsSinceMostRecent([.keyDown])
        let mouse = secondsSinceMostRecent([
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ])
        let scroll = secondsSinceMostRecent([.scrollWheel])
        let input = min(keyboard, mouse, scroll)

        return LocalActivitySnapshot(
            lastInputSeconds: input,
            lastKeyboardSeconds: keyboard,
            lastMouseSeconds: mouse,
            lastScrollSeconds: scroll,
            lastAppSwitchSeconds: lastAppSwitchSeconds,
            frontAppStableSeconds: frontAppStableSeconds,
            windowTitleStableSeconds: windowTitleStableSeconds,
            hasDetailedInputBreakdown: true
        )
    }

    private static func secondsSinceMostRecent(_ eventTypes: [CGEventType]) -> TimeInterval {
        eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}

enum CameraPermissionService {
    static func requestCameraAccess(_ completion: @escaping @MainActor (AVAuthorizationStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            Task { @MainActor in
                completion(status)
            }
        }
    }
}

final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "FocusPet.CameraCapture.session")
    private let frameQueue = DispatchQueue(label: "FocusPet.CameraCapture.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let visionDetector = VisionFrameFaceDetector()
    private let detectionIntervalSeconds: TimeInterval = 10
    private let targetFrameRate: Int32 = 2
    private let lock = NSLock()
    private var running = false
    private var frameHandler: ((CameraFrameMetadata, FaceDetectionResult?) -> Void)?
    private var lastFrameEmitAt: Date?
    private var frameSequence = 0

    var isRunning: Bool {
        lock.withLock { running }
    }

    func setFrameHandler(_ handler: ((CameraFrameMetadata, FaceDetectionResult?) -> Void)?) {
        lock.withLock {
            frameHandler = handler
        }
    }

    func start(completion: @escaping @MainActor (Bool) -> Void) {
        sessionQueue.async { [self] in
            guard !session.isRunning else {
                setRunning(true)
                Task { @MainActor in completion(true) }
                return
            }

            configureSessionIfNeeded()
            session.startRunning()
            let didStart = session.isRunning
            setRunning(didStart)

            Task { @MainActor in completion(didStart) }
        }
    }

    func stop(completion: (@MainActor (Bool) -> Void)? = nil) {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            setRunning(false)
            Task { @MainActor in completion?(false) }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        if let lastFrameEmitAt, now.timeIntervalSince(lastFrameEmitAt) < detectionIntervalSeconds {
            return
        }

        lastFrameEmitAt = now
        frameSequence += 1

        let frame = CameraFrameMetadata(timestamp: now, sequenceNumber: frameSequence)
        let detection = visionDetector.detect(
            sampleBuffer: sampleBuffer,
            orientation: imageOrientation(for: connection)
        )
        let handler = lock.withLock { frameHandler }
        handler?(frame, detection)
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .low

        if let camera = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            configureLowFrameRate(camera)
            session.addInput(input)
        }

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
            videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    private func setRunning(_ value: Bool) {
        lock.withLock {
            running = value
        }
    }

    private func configureLowFrameRate(_ camera: AVCaptureDevice) {
        let frameDuration = CMTime(value: 1, timescale: targetFrameRate)
        guard camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { range in
            CMTimeCompare(range.minFrameDuration, frameDuration) <= 0
                && CMTimeCompare(frameDuration, range.maxFrameDuration) <= 0
        }) else {
            return
        }

        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = frameDuration
            camera.activeVideoMaxFrameDuration = frameDuration
            camera.unlockForConfiguration()
        } catch {
            return
        }
    }

    private func imageOrientation(for connection: AVCaptureConnection) -> CGImagePropertyOrientation {
        let mirrored = connection.isVideoMirrored
        let angle = normalizedRotationAngle(connection.videoRotationAngle)

        switch angle {
        case 90:
            return mirrored ? .leftMirrored : .right
        case 180:
            return mirrored ? .downMirrored : .down
        case 270:
            return mirrored ? .rightMirrored : .left
        default:
            return mirrored ? .upMirrored : .up
        }
    }

    private func normalizedRotationAngle(_ angle: CGFloat) -> Int {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return Int(positive.rounded()) % 360
    }
}

private final class VisionFrameFaceDetector: @unchecked Sendable {
    private let heuristics = FaceStateHeuristics()

    func detect(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> FaceDetectionResult {
        let request = VNDetectFaceRectanglesRequest()
        if #available(macOS 13.0, *) {
            request.revision = VNDetectFaceRectanglesRequestRevision3
        }
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return FaceDetectionResult(
                facePresence: .unknown,
                gazeState: .unknown,
                headPitchDegrees: 0,
                confidence: 0.35,
                reason: "vision_request_failed"
            )
        }

        guard let observation = request.results?.first as? VNFaceObservation else {
            return heuristics.result(from: nil)
        }

        return heuristics.result(from: FaceGeometrySnapshot(
            yawDegrees: degrees(from: observation.yaw),
            pitchDegrees: degrees(from: observation.pitch),
            rollDegrees: degrees(from: observation.roll),
            boundingBoxCenterY: observation.boundingBox.midY,
            confidence: Double(observation.confidence)
        ))
    }

    private func degrees(from number: NSNumber?) -> Double? {
        guard let number else { return nil }
        return Double(truncating: number) * 180 / .pi
    }
}

enum NotificationService {
    static func send(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}

struct LocalDataStore: Sendable {
    private var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("FocusPetV0", isDirectory: true)
    }

    private var eventsURL: URL {
        rootURL.appendingPathComponent("state-events.json")
    }

    private var settingsURL: URL {
        rootURL.appendingPathComponent("settings.json")
    }

    private var rulesURL: URL {
        rootURL.appendingPathComponent("rules.json")
    }

    private var remindersURL: URL {
        rootURL.appendingPathComponent("reminders.json")
    }

    private var faceDiagnosticsURL: URL {
        rootURL.appendingPathComponent("face-diagnostics.json")
    }

    private var onboardingURL: URL {
        rootURL.appendingPathComponent("onboarding-complete.flag")
    }

    var petPacksRootURL: URL {
        rootURL.appendingPathComponent("PetPacks", isDirectory: true)
    }

    var hasCompletedOnboarding: Bool {
        loadSettings().hasCompletedOnboarding || FileManager.default.fileExists(atPath: onboardingURL.path)
    }

    func saveHasCompletedOnboarding(_ value: Bool) {
        var settings = loadSettings()
        settings.hasCompletedOnboarding = value
        saveSettings(settings)
    }

    func loadSettings() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONDecoder.focusPet.decode(AppSettings.self, from: data) else {
            var defaults = AppSettings()
            defaults.hasCompletedOnboarding = FileManager.default.fileExists(atPath: onboardingURL.path)
            return defaults
        }

        if FileManager.default.fileExists(atPath: onboardingURL.path) {
            settings.hasCompletedOnboarding = true
        }

        return settings
    }

    func settingsContainsLegacyRuntimeMode() -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["runtimeMode"] != nil
    }

    func saveSettings(_ settings: AppSettings) {
        ensureRoot()
        guard let data = try? JSONEncoder.focusPet.encode(settings) else { return }
        try? data.write(to: settingsURL, options: [.atomic])
    }

    func loadRules() -> [FocusRule] {
        guard let data = try? Data(contentsOf: rulesURL) else { return FocusRule.defaults }
        guard let decoded = try? JSONDecoder.focusPet.decode([FocusRule].self, from: data) else {
            return FocusRule.defaults
        }

        let currentRules = decoded.filter { rule in
            FocusRule.currentRuleIDs.contains(rule.id) && !rule.states.isEmpty
        }
        return currentRules.isEmpty ? FocusRule.defaults : currentRules
    }

    func saveRules(_ rules: [FocusRule]) {
        ensureRoot()
        guard let data = try? JSONEncoder.focusPet.encode(rules) else { return }
        try? data.write(to: rulesURL, options: [.atomic])
    }

    func loadReminders() -> [ReminderDecision] {
        guard let data = try? Data(contentsOf: remindersURL) else { return [] }
        return (try? JSONDecoder.focusPet.decode([ReminderDecision].self, from: data)) ?? []
    }

    func saveReminders(_ reminders: [ReminderDecision]) {
        ensureRoot()
        guard let data = try? JSONEncoder.focusPet.encode(reminders) else { return }
        try? data.write(to: remindersURL, options: [.atomic])
    }

    func loadStateEvents() -> [StateEvent] {
        guard let data = try? Data(contentsOf: eventsURL) else { return [] }
        return (try? JSONDecoder.focusPet.decode([StateEvent].self, from: data)) ?? []
    }

    func saveStateEvents(_ events: [StateEvent]) {
        ensureRoot()
        guard let data = try? JSONEncoder.focusPet.encode(events) else { return }
        try? data.write(to: eventsURL, options: [.atomic])
    }

    func loadFaceDiagnostics() -> [FaceDiagnosticEntry] {
        guard let data = try? Data(contentsOf: faceDiagnosticsURL) else { return [] }
        return (try? JSONDecoder.focusPet.decode([FaceDiagnosticEntry].self, from: data)) ?? []
    }

    func saveFaceDiagnostics(_ entries: [FaceDiagnosticEntry]) {
        ensureRoot()
        guard let data = try? JSONEncoder.focusPet.encode(entries) else { return }
        try? data.write(to: faceDiagnosticsURL, options: [.atomic])
    }

    func ensurePetPacksRoot() -> URL {
        ensureRoot()
        try? FileManager.default.createDirectory(at: petPacksRootURL, withIntermediateDirectories: true)
        return petPacksRootURL
    }

    func reclaimLocalData(
        stateEvents: [StateEvent],
        reminders: [ReminderDecision],
        faceDiagnostics: [FaceDiagnosticEntry]
    ) -> ReclaimedLocalData {
        LocalDataReclaimer().reclaim(
            stateEvents: stateEvents,
            reminders: reminders,
            faceDiagnostics: faceDiagnostics
        )
    }

    func currentDataSize() -> Int {
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        return enumerator.compactMap { item -> Int? in
            guard let url = item as? URL else { return nil }
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }
        .reduce(0, +)
    }

    func exportSnapshot(
        stateEvents: [StateEvent],
        reminders: [ReminderDecision],
        faceDiagnostics: [FaceDiagnosticEntry],
        rules: [FocusRule],
        settings: AppSettings,
        summary: DailySummary
    ) -> URL? {
        ensureRoot()
        let exportURL = rootURL.appendingPathComponent("focus-pet-export-\(Int(Date().timeIntervalSince1970)).json")
        let snapshot = ExportSnapshot(
            stateEvents: stateEvents,
            reminders: reminders,
            faceDiagnostics: faceDiagnostics,
            rules: rules,
            settings: settings,
            summary: summary
        )
        guard let data = try? JSONEncoder.focusPet.encode(snapshot) else { return nil }
        try? data.write(to: exportURL, options: [.atomic])
        pruneExportSnapshots(keeping: exportURL)
        return exportURL
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: rootURL)
        ensureRoot()
    }

    private func ensureRoot() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func pruneExportSnapshots(
        keeping currentExportURL: URL,
        maxCount: Int = 5,
        maxAgeSeconds: TimeInterval = 7 * 24 * 60 * 60
    ) {
        let now = Date()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let exports = urls.filter {
            $0.lastPathComponent.hasPrefix("focus-pet-export-")
                && $0.pathExtension == "json"
                && $0 != currentExportURL
        }
        let sorted = exports.sorted { lhs, rhs in
            modificationDate(for: lhs) < modificationDate(for: rhs)
        }
        let overCount = max(0, sorted.count - max(0, maxCount - 1))
        var removalCandidates: [URL] = []

        for (index, url) in sorted.enumerated() {
            let isOld = now.timeIntervalSince(modificationDate(for: url)) > maxAgeSeconds
            if index < overCount || isOld {
                removalCandidates.append(url)
            }
        }

        for url in removalCandidates {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

private struct ExportSnapshot: Codable {
    var stateEvents: [StateEvent]
    var reminders: [ReminderDecision]
    var faceDiagnostics: [FaceDiagnosticEntry]
    var rules: [FocusRule]
    var settings: AppSettings
    var summary: DailySummary
}

private extension JSONEncoder {
    static var focusPet: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var focusPet: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

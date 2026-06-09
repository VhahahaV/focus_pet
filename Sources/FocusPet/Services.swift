import AppKit
@preconcurrency import AVFoundation
import FocusPetCore
import Foundation
import UserNotifications

struct FrontApplication: Sendable {
    var name: String
    var bundleID: String?
}

struct ForegroundAppService: Sendable {
    func frontmostApplication() -> FrontApplication {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontApplication(
            name: app?.localizedName ?? "Unknown",
            bundleID: app?.bundleIdentifier
        )
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
        let key = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let mouse = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        return min(key, mouse)
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
    private let lock = NSLock()
    private var running = false
    private var frameHandler: ((CameraFrameMetadata) -> Void)?
    private var lastFrameEmitAt: Date?
    private var frameSequence = 0

    var isRunning: Bool {
        lock.withLock { running }
    }

    func setFrameHandler(_ handler: ((CameraFrameMetadata) -> Void)?) {
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
        if let lastFrameEmitAt, now.timeIntervalSince(lastFrameEmitAt) < 1.0 {
            return
        }

        lastFrameEmitAt = now
        frameSequence += 1

        let frame = CameraFrameMetadata(timestamp: now, sequenceNumber: frameSequence)
        let handler = lock.withLock { frameHandler }
        handler?(frame)
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .low

        if let camera = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
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

    private var onboardingURL: URL {
        rootURL.appendingPathComponent("onboarding-complete.flag")
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

    func saveSettings(_ settings: AppSettings) {
        ensureRoot()
        guard let data = try? JSONEncoder.focusPet.encode(settings) else { return }
        try? data.write(to: settingsURL, options: [.atomic])
    }

    func loadRules() -> [FocusRule] {
        guard let data = try? Data(contentsOf: rulesURL) else { return FocusRule.defaults }
        return (try? JSONDecoder.focusPet.decode([FocusRule].self, from: data)) ?? FocusRule.defaults
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
        rules: [FocusRule],
        settings: AppSettings,
        summary: DailySummary
    ) -> URL? {
        ensureRoot()
        let exportURL = rootURL.appendingPathComponent("focus-pet-export-\(Int(Date().timeIntervalSince1970)).json")
        let snapshot = ExportSnapshot(
            stateEvents: stateEvents,
            reminders: reminders,
            rules: rules,
            settings: settings,
            summary: summary
        )
        guard let data = try? JSONEncoder.focusPet.encode(snapshot) else { return nil }
        try? data.write(to: exportURL, options: [.atomic])
        return exportURL
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: rootURL)
        ensureRoot()
    }

    private func ensureRoot() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
}

private struct ExportSnapshot: Codable {
    var stateEvents: [StateEvent]
    var reminders: [ReminderDecision]
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

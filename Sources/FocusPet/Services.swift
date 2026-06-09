import AppKit
import AVFoundation
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

@MainActor
final class CameraCaptureService {
    private let session = AVCaptureSession()

    var isRunning: Bool {
        session.isRunning
    }

    func start() {
        guard !session.isRunning else { return }
        session.beginConfiguration()
        session.sessionPreset = .low

        if session.inputs.isEmpty,
           let camera = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
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

    private var onboardingURL: URL {
        rootURL.appendingPathComponent("onboarding-complete.flag")
    }

    var hasCompletedOnboarding: Bool {
        FileManager.default.fileExists(atPath: onboardingURL.path)
    }

    func saveHasCompletedOnboarding(_ value: Bool) {
        ensureRoot()
        if value {
            FileManager.default.createFile(atPath: onboardingURL.path, contents: Data(), attributes: nil)
        } else {
            try? FileManager.default.removeItem(at: onboardingURL)
        }
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
        summary: DailySummary
    ) -> URL? {
        ensureRoot()
        let exportURL = rootURL.appendingPathComponent("focus-pet-export-\(Int(Date().timeIntervalSince1970)).json")
        let snapshot = ExportSnapshot(stateEvents: stateEvents, reminders: reminders, summary: summary)
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

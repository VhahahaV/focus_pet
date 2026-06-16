import FocusPetCore
import Foundation

public struct LocalStoreSnapshot: Codable, Hashable, Sendable {
    public var settings: AppSettings
    public var classificationRules: [ClassificationRule]
    public var stateSegments: [StateSegment]
    public var appUsage: [AppUsageSegment]
    public var inputActivity: [InputActivityBucket]
    public var focusSessions: [FocusSession]
    public var breakSessions: [BreakSession]
    public var nudges: [NudgeEvent]

    public init(
        settings: AppSettings = AppSettings(),
        classificationRules: [ClassificationRule] = [],
        stateSegments: [StateSegment] = [],
        appUsage: [AppUsageSegment] = [],
        inputActivity: [InputActivityBucket] = [],
        focusSessions: [FocusSession] = [],
        breakSessions: [BreakSession] = [],
        nudges: [NudgeEvent] = []
    ) {
        self.settings = settings
        self.classificationRules = classificationRules
        self.stateSegments = stateSegments
        self.appUsage = appUsage
        self.inputActivity = inputActivity
        self.focusSessions = focusSessions
        self.breakSessions = breakSessions
        self.nudges = nudges
    }

    private enum CodingKeys: String, CodingKey {
        case settings
        case classificationRules
        case stateSegments
        case appUsage
        case inputActivity
        case focusSessions
        case breakSessions
        case nudges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            settings: try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings(),
            classificationRules: try container.decodeIfPresent([ClassificationRule].self, forKey: .classificationRules) ?? [],
            stateSegments: try container.decodeIfPresent([StateSegment].self, forKey: .stateSegments) ?? [],
            appUsage: try container.decodeIfPresent([AppUsageSegment].self, forKey: .appUsage) ?? [],
            inputActivity: try container.decodeIfPresent([InputActivityBucket].self, forKey: .inputActivity) ?? [],
            focusSessions: try container.decodeIfPresent([FocusSession].self, forKey: .focusSessions) ?? [],
            breakSessions: try container.decodeIfPresent([BreakSession].self, forKey: .breakSessions) ?? [],
            nudges: try container.decodeIfPresent([NudgeEvent].self, forKey: .nudges) ?? []
        )
    }
}

public struct LocalStore: Sendable {
    private let schemaVersion = "focuspet-mvp-1"
    private let migratableSchemaVersions: Set<String> = []
    public let rootURL: URL

    public init(rootURL: URL = FocusPetDataPaths.rootURL()) {
        self.rootURL = rootURL
    }

    public func bootstrapCleanSchemaIfNeeded() {
        _ = prepareStoreForAccess(writeIntent: false)
    }

    public func loadSnapshot() -> LocalStoreSnapshot {
        bootstrapCleanSchemaIfNeeded()
        return LocalStoreSnapshot(
            settings: load("settings.json", defaultValue: AppSettings()),
            classificationRules: ActivityClassifier.userRules(
                fromStored: load("classification-rules.json", defaultValue: [])
            ),
            stateSegments: load("state-segments.json", defaultValue: []),
            appUsage: load("app-usage.json", defaultValue: []),
            inputActivity: load("input-activity.json", defaultValue: []),
            focusSessions: load("focus-sessions.json", defaultValue: []),
            breakSessions: load("break-sessions.json", defaultValue: []),
            nudges: load("nudges.json", defaultValue: [])
        )
    }

    public func saveSnapshot(_ snapshot: LocalStoreSnapshot, changedFrom previous: LocalStoreSnapshot? = nil) {
        guard prepareStoreForAccess(writeIntent: true) else { return }
        if previous?.settings != snapshot.settings {
            save(snapshot.settings, to: "settings.json")
        }
        if previous?.classificationRules != snapshot.classificationRules {
            save(snapshot.classificationRules, to: "classification-rules.json")
        }
        if previous?.stateSegments != snapshot.stateSegments {
            save(snapshot.stateSegments, to: "state-segments.json")
        }
        if previous?.appUsage != snapshot.appUsage {
            save(snapshot.appUsage, to: "app-usage.json")
        }
        if previous?.inputActivity != snapshot.inputActivity {
            save(snapshot.inputActivity, to: "input-activity.json")
        }
        if previous?.focusSessions != snapshot.focusSessions {
            save(snapshot.focusSessions, to: "focus-sessions.json")
        }
        if previous?.breakSessions != snapshot.breakSessions {
            save(snapshot.breakSessions, to: "break-sessions.json")
        }
        if previous?.nudges != snapshot.nudges {
            save(snapshot.nudges, to: "nudges.json")
        }
    }

    public func exportSnapshot(_ snapshot: LocalStoreSnapshot, redacted: Bool = false) -> URL? {
        guard prepareStoreForAccess(writeIntent: true) else { return nil }
        let prefix = redacted ? "focus-pet-redacted-export" : "focus-pet-export"
        let url = rootURL.appendingPathComponent("\(prefix)-\(Int(Date().timeIntervalSince1970)).json")
        let exportSnapshot = redacted ? snapshot.redactedForExport() : snapshot
        guard let data = try? JSONEncoder.focusPet.encode(exportSnapshot) else { return nil }
        try? data.write(to: url, options: [.atomic])
        return url
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: rootURL)
        ensureRoot()
        saveMetadata()
    }

    public func currentDataSize() -> Int {
        guard let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        return enumerator.compactMap { item -> Int? in
            guard let url = item as? URL else { return nil }
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }.reduce(0, +)
    }

    @discardableResult
    private func prepareStoreForAccess(writeIntent: Bool) -> Bool {
        migrateLegacyRootIfNeeded()
        ensureRoot()
        let metadataURL = rootURL.appendingPathComponent("schema.json")

        switch metadataState(at: metadataURL) {
        case .current:
            removeLegacyRoots()
            return true
        case .missing:
            if rootContainsData() {
                backupRootIfNeeded(reason: "missing-schema")
            }
            saveMetadata()
            removeLegacyRoots()
            return true
        case .invalid:
            if rootContainsData() {
                backupRootIfNeeded(reason: "invalid-schema")
            }
            return !writeIntent
        case .unsupported(let existingSchemaVersion):
            if migratableSchemaVersions.contains(existingSchemaVersion) {
                backupRootIfNeeded(reason: "migrate-\(existingSchemaVersion)")
                saveMetadata()
                removeLegacyRoots()
                return true
            }

            if rootContainsData() {
                backupRootIfNeeded(reason: "unsupported-schema-\(existingSchemaVersion)")
            }
            return !writeIntent
        }
    }

    private func load<T: Decodable>(_ fileName: String, defaultValue: T) -> T {
        let url = rootURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.focusPet.decode(T.self, from: data) else {
            return defaultValue
        }
        return decoded
    }

    private func save<T: Encodable>(_ value: T, to fileName: String) {
        ensureRoot()
        let url = rootURL.appendingPathComponent(fileName)
        guard let data = try? JSONEncoder.focusPet.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func ensureRoot() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func saveMetadata() {
        save(StoreMetadata(schemaVersion: schemaVersion), to: "schema.json")
    }

    private func metadataState(at metadataURL: URL) -> MetadataState {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return .missing
        }

        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder.focusPet.decode(StoreMetadata.self, from: data) else {
            return .invalid
        }

        if metadata.schemaVersion == schemaVersion {
            return .current
        }

        return .unsupported(metadata.schemaVersion)
    }

    private func rootContainsData() -> Bool {
        guard FileManager.default.fileExists(atPath: rootURL.path),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }

        return !contents.isEmpty
    }

    private func backupRootIfNeeded(reason: String) {
        guard rootContainsData() else { return }

        let fileManager = FileManager.default
        let parentURL = rootURL.deletingLastPathComponent()
        let safeReason = sanitizedBackupReason(reason)
        let backupPrefix = "\(rootURL.lastPathComponent) Backup "

        if let existingBackups = try? fileManager.contentsOfDirectory(atPath: parentURL.path),
           existingBackups.contains(where: { name in
               name.hasPrefix(backupPrefix) && name.hasSuffix(" \(safeReason)")
           }) {
            return
        }

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let baseName = "\(backupPrefix)\(timestamp) \(safeReason)"
        var backupURL = parentURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: backupURL.path) {
            backupURL = parentURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        try? fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try? fileManager.copyItem(at: rootURL, to: backupURL)
    }

    private func sanitizedBackupReason(_ reason: String) -> String {
        let cleaned = reason.map { character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        let compacted = String(cleaned)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compacted.isEmpty ? "schema" : compacted
    }

    private func migrateLegacyRootIfNeeded() {
        let metadataURL = rootURL.appendingPathComponent("schema.json")
        guard !FileManager.default.fileExists(atPath: metadataURL.path) else { return }

        if FileManager.default.fileExists(atPath: rootURL.path),
           let contents = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path),
           !contents.isEmpty {
            return
        }

        for legacyURL in FocusPetDataPaths.legacyRootURLs() where legacyURL != rootURL {
            let legacyMetadataURL = legacyURL.appendingPathComponent("schema.json")
            guard FileManager.default.fileExists(atPath: legacyMetadataURL.path) else { continue }

            do {
                if FileManager.default.fileExists(atPath: rootURL.path) {
                    try FileManager.default.removeItem(at: rootURL)
                }
                try FileManager.default.createDirectory(
                    at: rootURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: legacyURL, to: rootURL)
                return
            } catch {
                try? FileManager.default.copyItem(at: legacyURL, to: rootURL)
                return
            }
        }
    }

    private func removeLegacyRoots() {
        let metadataURL = rootURL.appendingPathComponent("schema.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }

        for url in FocusPetDataPaths.legacyRootURLs() where url != rootURL {
            let legacyMetadataURL = url.appendingPathComponent("schema.json")
            if FileManager.default.fileExists(atPath: legacyMetadataURL.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

public extension LocalStoreSnapshot {
    func redactedForExport() -> LocalStoreSnapshot {
        var copy = self
        copy.settings.privacy.storeRawTitle = false
        copy.settings.privacy.storeOnlyCategoryResult = true
        copy.stateSegments = stateSegments.map { segment in
            var redacted = segment
            redacted.titleStored = false
            redacted.titleDisplay = nil
            return redacted
        }
        return copy
    }
}

private struct StoreMetadata: Codable {
    var schemaVersion: String
}

private enum MetadataState {
    case current
    case missing
    case invalid
    case unsupported(String)
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

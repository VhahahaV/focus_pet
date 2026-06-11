import FocusPetCore
import Foundation

public struct LocalStoreSnapshot: Codable, Hashable, Sendable {
    public var settings: AppSettings
    public var classificationRules: [ClassificationRule]
    public var stateSegments: [StateSegment]
    public var appUsage: [AppUsageSegment]
    public var focusSessions: [FocusSession]
    public var breakSessions: [BreakSession]
    public var nudges: [NudgeEvent]

    public init(
        settings: AppSettings = AppSettings(),
        classificationRules: [ClassificationRule] = ActivityClassifier.defaultRules,
        stateSegments: [StateSegment] = [],
        appUsage: [AppUsageSegment] = [],
        focusSessions: [FocusSession] = [],
        breakSessions: [BreakSession] = [],
        nudges: [NudgeEvent] = []
    ) {
        self.settings = settings
        self.classificationRules = classificationRules
        self.stateSegments = stateSegments
        self.appUsage = appUsage
        self.focusSessions = focusSessions
        self.breakSessions = breakSessions
        self.nudges = nudges
    }
}

public struct LocalStore: Sendable {
    private let schemaVersion = "focuspet-mvp-1"
    public let rootURL: URL

    public init(rootURL: URL = FocusPetDataPaths.rootURL()) {
        self.rootURL = rootURL
    }

    public func bootstrapCleanSchemaIfNeeded() {
        removeLegacyRoots()
        let metadataURL = rootURL.appendingPathComponent("schema.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder.focusPet.decode(StoreMetadata.self, from: data),
              metadata.schemaVersion == schemaVersion else {
            try? FileManager.default.removeItem(at: rootURL)
            ensureRoot()
            saveMetadata()
            return
        }

        ensureRoot()
    }

    public func loadSnapshot() -> LocalStoreSnapshot {
        bootstrapCleanSchemaIfNeeded()
        return LocalStoreSnapshot(
            settings: load("settings.json", defaultValue: AppSettings()),
            classificationRules: load("classification-rules.json", defaultValue: ActivityClassifier.defaultRules),
            stateSegments: load("state-segments.json", defaultValue: []),
            appUsage: load("app-usage.json", defaultValue: []),
            focusSessions: load("focus-sessions.json", defaultValue: []),
            breakSessions: load("break-sessions.json", defaultValue: []),
            nudges: load("nudges.json", defaultValue: [])
        )
    }

    public func saveSnapshot(_ snapshot: LocalStoreSnapshot) {
        bootstrapCleanSchemaIfNeeded()
        save(snapshot.settings, to: "settings.json")
        save(snapshot.classificationRules, to: "classification-rules.json")
        save(snapshot.stateSegments, to: "state-segments.json")
        save(snapshot.appUsage, to: "app-usage.json")
        save(snapshot.focusSessions, to: "focus-sessions.json")
        save(snapshot.breakSessions, to: "break-sessions.json")
        save(snapshot.nudges, to: "nudges.json")
    }

    public func exportSnapshot(_ snapshot: LocalStoreSnapshot, redacted: Bool = false) -> URL? {
        bootstrapCleanSchemaIfNeeded()
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

    private func removeLegacyRoots() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let legacyNames = ["FocusPetV0", "FocusPetLegacy"]
        for name in legacyNames {
            if let url = appSupport?.appendingPathComponent(name, isDirectory: true),
               url != rootURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

public extension LocalStoreSnapshot {
    func repairedOvernightFocusArtifacts(now: Date = Date()) -> LocalStoreSnapshot {
        let windows = Self.sleepWindows(covering: repairRelevantDates(now: now))
        let noisyReasons: Set<NudgeReason> = [.longFocusRest, .veryLongFocusRest]
        let nudgeTimes = nudges
            .filter { noisyReasons.contains($0.reason) }
            .map(\.time)

        guard !windows.isEmpty, !nudgeTimes.isEmpty else { return self }
        let noisyWindows = windows.filter { window in
            nudgeTimes.contains { window.containsInclusive($0) }
        }
        guard !noisyWindows.isEmpty else { return self }

        var copy = self
        var repairedRanges: [DateInterval] = []
        copy.stateSegments = stateSegments.flatMap { segment -> [StateSegment] in
            guard segment.state == .focus,
                  segment.category != .work else {
                return [segment]
            }

            let segmentInterval = DateInterval(start: segment.start, end: segment.end)
            let ranges = noisyWindows.compactMap { window in
                Self.intersection(segmentInterval, window)
            }

            guard !ranges.isEmpty else { return [segment] }
            repairedRanges.append(contentsOf: ranges)
            return Self.splitFocusSegment(segment, repairing: ranges)
        }

        guard !repairedRanges.isEmpty else { return self }

        copy.appUsage = Self.removeIntervals(repairedRanges, from: appUsage)
        copy.focusSessions = Self.repairFocusSessions(focusSessions, removing: repairedRanges, now: now)
        copy.nudges = nudges.filter { nudge in
            guard noisyReasons.contains(nudge.reason) else { return true }
            return !noisyWindows.contains { $0.containsInclusive(nudge.time) }
        }
        return copy
    }

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

private extension LocalStoreSnapshot {
    func repairRelevantDates(now: Date) -> [Date] {
        stateSegments.flatMap { [$0.start, $0.end] }
            + appUsage.flatMap { [$0.start, $0.end] }
            + nudges.map(\.time)
            + focusSessions.flatMap { [$0.start, $0.end ?? now] }
            + [now]
    }

    static func sleepWindows(covering dates: [Date]) -> [DateInterval] {
        guard let minDate = dates.min(), let maxDate = dates.max() else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        var day = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: minDate))
            ?? calendar.startOfDay(for: minDate)
        let lastDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: maxDate))
            ?? calendar.startOfDay(for: maxDate)

        var windows: [DateInterval] = []
        while day <= lastDay {
            let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: day) ?? day
            let end = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day)
                ?? start.addingTimeInterval(8.5 * 60 * 60)
            windows.append(DateInterval(start: start, end: end))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(24 * 60 * 60)
        }
        return windows
    }

    static func splitFocusSegment(_ segment: StateSegment, repairing ranges: [DateInterval]) -> [StateSegment] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var result: [StateSegment] = []
        var cursor = segment.start

        for range in sorted {
            let start = max(range.start, segment.start)
            let end = min(range.end, segment.end)
            guard end > start else { continue }

            if start > cursor {
                result.append(copy(segment, start: cursor, end: start))
            }

            var source = segment.source
            source.insert(.idleTime)
            result.append(StateSegment(
                start: start,
                end: end,
                state: .away,
                appName: "Sleep",
                bundleID: nil,
                category: .ignore,
                titleStored: false,
                titleDisplay: nil,
                source: source
            ))
            cursor = max(cursor, end)
        }

        if cursor < segment.end {
            result.append(copy(segment, start: cursor, end: segment.end))
        }

        return result
    }

    static func copy(_ segment: StateSegment, start: Date, end: Date) -> StateSegment {
        var copy = segment
        copy.start = start
        copy.end = end
        return copy
    }

    static func removeIntervals(_ ranges: [DateInterval], from usage: [AppUsageSegment]) -> [AppUsageSegment] {
        usage.flatMap { item -> [AppUsageSegment] in
            let fragments = subtract(ranges, from: DateInterval(start: item.start, end: item.end))
            return fragments.map { fragment in
                var copy = item
                copy.start = fragment.start
                copy.end = fragment.end
                return copy
            }
        }
    }

    static func repairFocusSessions(_ sessions: [FocusSession], removing ranges: [DateInterval], now: Date) -> [FocusSession] {
        sessions.map { session in
            var copy = session
            let sessionInterval = DateInterval(start: session.start, end: session.end ?? now)
            let repairedSeconds = ranges.compactMap { intersection($0, sessionInterval) }
                .reduce(0) { $0 + max(0, Int($1.duration.rounded())) }
            guard repairedSeconds > 0 else { return session }

            copy.effectiveFocusSeconds = max(0, copy.effectiveFocusSeconds - repairedSeconds)
            copy.awaySeconds += repairedSeconds
            return copy
        }
    }

    static func subtract(_ ranges: [DateInterval], from interval: DateInterval) -> [DateInterval] {
        ranges.sorted { $0.start < $1.start }.reduce([interval]) { fragments, range in
            fragments.flatMap { fragment -> [DateInterval] in
                guard let overlap = intersection(fragment, range) else { return [fragment] }
                var result: [DateInterval] = []
                if fragment.start < overlap.start {
                    result.append(DateInterval(start: fragment.start, end: overlap.start))
                }
                if overlap.end < fragment.end {
                    result.append(DateInterval(start: overlap.end, end: fragment.end))
                }
                return result
            }
        }
    }

    static func intersection(_ lhs: DateInterval, _ rhs: DateInterval) -> DateInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

private extension DateInterval {
    func containsInclusive(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

public enum FocusPetDataPaths {
    public static func rootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("FocusPetMVP", isDirectory: true)
    }
}

private struct StoreMetadata: Codable {
    var schemaVersion: String
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

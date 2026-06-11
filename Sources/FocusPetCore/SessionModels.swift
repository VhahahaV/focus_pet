import Foundation

public enum FocusSessionStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case active
    case completed
    case cancelled
}

public struct FocusSession: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var taskName: String
    public var start: Date
    public var targetDurationSeconds: Int
    public var end: Date?
    public var effectiveFocusSeconds: Int
    public var distractedSeconds: Int
    public var awaySeconds: Int
    public var switchCount: Int
    public var interruptionCount: Int
    public var mainAppName: String?
    public var completed: Bool
    public var status: FocusSessionStatus
    public var autoStartBreak: Bool
    public var breakDurationSeconds: Int

    public init(
        id: String = UUID().uuidString,
        taskName: String,
        start: Date,
        targetDurationSeconds: Int,
        end: Date? = nil,
        effectiveFocusSeconds: Int = 0,
        distractedSeconds: Int = 0,
        awaySeconds: Int = 0,
        switchCount: Int = 0,
        interruptionCount: Int = 0,
        mainAppName: String? = nil,
        completed: Bool = false,
        status: FocusSessionStatus = .active,
        autoStartBreak: Bool = true,
        breakDurationSeconds: Int = 5 * 60
    ) {
        self.id = id
        self.taskName = taskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "专注任务" : taskName
        self.start = start
        self.targetDurationSeconds = max(60, targetDurationSeconds)
        self.end = end
        self.effectiveFocusSeconds = max(0, effectiveFocusSeconds)
        self.distractedSeconds = max(0, distractedSeconds)
        self.awaySeconds = max(0, awaySeconds)
        self.switchCount = max(0, switchCount)
        self.interruptionCount = max(0, interruptionCount)
        self.mainAppName = mainAppName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.completed = completed
        self.status = status
        self.autoStartBreak = autoStartBreak
        self.breakDurationSeconds = max(60, breakDurationSeconds)
    }

    public func elapsedSeconds(now: Date = Date()) -> Int {
        max(0, Int((end ?? now).timeIntervalSince(start)))
    }

    public func remainingSeconds(now: Date = Date()) -> Int {
        max(0, targetDurationSeconds - elapsedSeconds(now: now))
    }

    public var completionRatio: Double {
        guard targetDurationSeconds > 0 else { return 0 }
        return min(1, max(0, Double(effectiveFocusSeconds) / Double(targetDurationSeconds)))
    }

    public var effectiveSeconds: Int {
        effectiveFocusSeconds + distractedSeconds + awaySeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case taskName
        case start
        case targetDurationSeconds
        case end
        case effectiveFocusSeconds
        case distractedSeconds
        case awaySeconds
        case switchCount
        case interruptionCount
        case mainAppName
        case completed
        case status
        case autoStartBreak
        case breakDurationSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            taskName: try container.decodeIfPresent(String.self, forKey: .taskName) ?? "专注任务",
            start: try container.decode(Date.self, forKey: .start),
            targetDurationSeconds: try container.decodeIfPresent(Int.self, forKey: .targetDurationSeconds) ?? 25 * 60,
            end: try container.decodeIfPresent(Date.self, forKey: .end),
            effectiveFocusSeconds: try container.decodeIfPresent(Int.self, forKey: .effectiveFocusSeconds) ?? 0,
            distractedSeconds: try container.decodeIfPresent(Int.self, forKey: .distractedSeconds) ?? 0,
            awaySeconds: try container.decodeIfPresent(Int.self, forKey: .awaySeconds) ?? 0,
            switchCount: try container.decodeIfPresent(Int.self, forKey: .switchCount) ?? 0,
            interruptionCount: try container.decodeIfPresent(Int.self, forKey: .interruptionCount) ?? 0,
            mainAppName: try container.decodeIfPresent(String.self, forKey: .mainAppName),
            completed: try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false,
            status: try container.decodeIfPresent(FocusSessionStatus.self, forKey: .status) ?? .active,
            autoStartBreak: try container.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? true,
            breakDurationSeconds: try container.decodeIfPresent(Int.self, forKey: .breakDurationSeconds) ?? 5 * 60
        )
    }
}

public enum BreakSource: String, Codable, Hashable, Sendable, CaseIterable {
    case manual
    case afterFocusSession
    case longFocusSuggestion
}


public struct BreakSession: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var start: Date
    public var targetDurationSeconds: Int
    public var end: Date?
    public var source: BreakSource
    public var completed: Bool

    public init(
        id: String = UUID().uuidString,
        start: Date,
        targetDurationSeconds: Int,
        end: Date? = nil,
        source: BreakSource,
        completed: Bool = false
    ) {
        self.id = id
        self.start = start
        self.targetDurationSeconds = max(60, targetDurationSeconds)
        self.end = end
        self.source = source
        self.completed = completed
    }

    public func remainingSeconds(now: Date = Date()) -> Int {
        max(0, targetDurationSeconds - max(0, Int(now.timeIntervalSince(start))))
    }
}

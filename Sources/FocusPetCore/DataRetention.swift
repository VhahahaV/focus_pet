import Foundation

public struct DataRetentionPolicy: Codable, Hashable, Sendable {
    public var maxStateEvents: Int
    public var maxReminders: Int
    public var maxFaceDiagnostics: Int
    public var maxEventAgeSeconds: TimeInterval
    public var maxReminderAgeSeconds: TimeInterval
    public var maxFaceDiagnosticAgeSeconds: TimeInterval

    public init(
        maxStateEvents: Int = 720,
        maxReminders: Int = 80,
        maxFaceDiagnostics: Int = 180,
        maxEventAgeSeconds: TimeInterval = 14 * 24 * 60 * 60,
        maxReminderAgeSeconds: TimeInterval = 30 * 24 * 60 * 60,
        maxFaceDiagnosticAgeSeconds: TimeInterval = 6 * 60 * 60
    ) {
        self.maxStateEvents = maxStateEvents
        self.maxReminders = maxReminders
        self.maxFaceDiagnostics = maxFaceDiagnostics
        self.maxEventAgeSeconds = maxEventAgeSeconds
        self.maxReminderAgeSeconds = maxReminderAgeSeconds
        self.maxFaceDiagnosticAgeSeconds = maxFaceDiagnosticAgeSeconds
    }
}

public struct DataRetentionReport: Codable, Hashable, Sendable {
    public var removedStateEvents: Int
    public var removedReminders: Int
    public var removedFaceDiagnostics: Int

    public init(removedStateEvents: Int, removedReminders: Int, removedFaceDiagnostics: Int) {
        self.removedStateEvents = removedStateEvents
        self.removedReminders = removedReminders
        self.removedFaceDiagnostics = removedFaceDiagnostics
    }

    public var totalRemoved: Int {
        removedStateEvents + removedReminders + removedFaceDiagnostics
    }
}

public struct ReclaimedLocalData: Sendable {
    public var stateEvents: [StateEvent]
    public var reminders: [ReminderDecision]
    public var faceDiagnostics: [FaceDiagnosticEntry]
    public var report: DataRetentionReport
}

public struct LocalDataReclaimer: Sendable {
    public var policy: DataRetentionPolicy

    public init(policy: DataRetentionPolicy = DataRetentionPolicy()) {
        self.policy = policy
    }

    public func reclaim(
        stateEvents: [StateEvent],
        reminders: [ReminderDecision],
        faceDiagnostics: [FaceDiagnosticEntry],
        now: Date = Date()
    ) -> ReclaimedLocalData {
        let retainedEvents = retain(
            stateEvents,
            maxCount: policy.maxStateEvents,
            now: now,
            maxAge: policy.maxEventAgeSeconds,
            date: \.endTime
        )
        let retainedReminders = retain(
            reminders,
            maxCount: policy.maxReminders,
            now: now,
            maxAge: policy.maxReminderAgeSeconds,
            date: \.triggeredAt
        )
        let retainedDiagnostics = retain(
            faceDiagnostics,
            maxCount: policy.maxFaceDiagnostics,
            now: now,
            maxAge: policy.maxFaceDiagnosticAgeSeconds,
            date: \.timestamp
        )

        return ReclaimedLocalData(
            stateEvents: retainedEvents,
            reminders: retainedReminders,
            faceDiagnostics: retainedDiagnostics,
            report: DataRetentionReport(
                removedStateEvents: stateEvents.count - retainedEvents.count,
                removedReminders: reminders.count - retainedReminders.count,
                removedFaceDiagnostics: faceDiagnostics.count - retainedDiagnostics.count
            )
        )
    }

    private func retain<T>(
        _ records: [T],
        maxCount: Int,
        now: Date,
        maxAge: TimeInterval,
        date: KeyPath<T, Date>
    ) -> [T] {
        let recent = records.filter { now.timeIntervalSince($0[keyPath: date]) <= maxAge }
        guard recent.count > maxCount else { return recent }
        return Array(recent.suffix(maxCount))
    }
}

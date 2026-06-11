import Foundation

public struct AppUsageSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(bundleID ?? appName)-\(category.rawValue)" }
    public var appName: String
    public var bundleID: String?
    public var category: ActivityCategory
    public var seconds: Int
    public var stateBreakdown: [FocusState: Int]
}

public struct CategoryUsageSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String { category.rawValue }
    public var category: ActivityCategory
    public var seconds: Int
    public var appCount: Int

    public init(category: ActivityCategory, seconds: Int, appCount: Int) {
        self.category = category
        self.seconds = max(0, seconds)
        self.appCount = max(0, appCount)
    }
}

public struct DailySummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String { date }
    public var date: String
    public var focusSeconds: Int
    public var distractedSeconds: Int
    public var breakSeconds: Int
    public var awaySeconds: Int
    public var longestFocusSeconds: Int
    public var focusSessionCount: Int
    public var distractedCount: Int
    public var awayCount: Int
    public var nudgeCount: Int
    public var switchCount: Int
    public var appUsage: [AppUsageSummary]
    public var categoryUsage: [CategoryUsageSummary]

    public var totalSeconds: Int {
        focusSeconds + distractedSeconds + breakSeconds + awaySeconds
    }

    public func categorySeconds(_ category: ActivityCategory) -> Int {
        categoryUsage.first { $0.category == category }?.seconds ?? 0
    }
}

public struct DailySummaryBuilder: Sendable {
    public init() {}

    public func summary(
        for date: Date,
        segments: [StateSegment],
        appUsage: [AppUsageSegment],
        focusSessions: [FocusSession],
        breakSessions: [BreakSession],
        nudges: [NudgeEvent]
    ) -> DailySummary {
        let bounds = Self.dayBounds(for: date)
        let clipped = segments.compactMap { segment -> StateSegment? in
            let start = max(segment.start, bounds.start)
            let end = min(segment.end, bounds.end)
            guard end > start else { return nil }
            var copy = segment
            copy.start = start
            copy.end = end
            return copy
        }

        let durations = clipped.reduce(into: Dictionary(uniqueKeysWithValues: FocusState.allCases.map { ($0, 0) })) {
            result, segment in
            result[segment.state, default: 0] += segment.durationSeconds
        }

        let appSummary = makeAppSummary(from: clipped, appUsage: appUsage, bounds: bounds)
        let categorySummary = makeCategorySummary(from: clipped, appUsage: appUsage, bounds: bounds)

        return DailySummary(
            date: Self.dateString(from: date),
            focusSeconds: durations[.focus, default: 0],
            distractedSeconds: durations[.distracted, default: 0],
            breakSeconds: durations[.breakTime, default: 0],
            awaySeconds: durations[.away, default: 0],
            longestFocusSeconds: clipped.filter { $0.state == .focus }.map(\.durationSeconds).max() ?? 0,
            focusSessionCount: focusSessions.filter { overlaps($0.start, $0.end ?? bounds.end, bounds: bounds) }.count,
            distractedCount: clipped.filter { $0.state == .distracted }.count,
            awayCount: clipped.filter { $0.state == .away }.count,
            nudgeCount: nudges.filter { $0.time >= bounds.start && $0.time < bounds.end }.count,
            switchCount: appUsage.filter { overlaps($0.start, $0.end, bounds: bounds) }.count,
            appUsage: appSummary,
            categoryUsage: categorySummary
        )
    }

    private func makeAppSummary(
        from segments: [StateSegment],
        appUsage: [AppUsageSegment],
        bounds: (start: Date, end: Date)
    ) -> [AppUsageSummary] {
        var result: [String: AppUsageSummary] = [:]

        for usage in appUsage where overlaps(usage.start, usage.end, bounds: bounds) {
            let key = "\(usage.bundleID ?? usage.appName)-\(usage.category.rawValue)"
            var summary = result[key] ?? AppUsageSummary(
                appName: usage.appName,
                bundleID: usage.bundleID,
                category: usage.category,
                seconds: 0,
                stateBreakdown: [:]
            )
            summary.seconds += usage.durationSeconds
            result[key] = summary
        }

        for segment in segments {
            let key = "\(segment.bundleID ?? segment.appName)-\(segment.category.rawValue)"
            var summary = result[key] ?? AppUsageSummary(
                appName: segment.appName,
                bundleID: segment.bundleID,
                category: segment.category,
                seconds: 0,
                stateBreakdown: [:]
            )
            summary.stateBreakdown[segment.state, default: 0] += segment.durationSeconds
            if summary.seconds == 0 {
                summary.seconds += segment.durationSeconds
            }
            result[key] = summary
        }

        return result.values.sorted { lhs, rhs in
            if lhs.seconds == rhs.seconds {
                return lhs.appName < rhs.appName
            }
            return lhs.seconds > rhs.seconds
        }
    }

    private func makeCategorySummary(
        from segments: [StateSegment],
        appUsage: [AppUsageSegment],
        bounds: (start: Date, end: Date)
    ) -> [CategoryUsageSummary] {
        var secondsByCategory: [ActivityCategory: Int] = [:]
        var appsByCategory: [ActivityCategory: Set<String>] = [:]

        let usageInDay = appUsage.filter { overlaps($0.start, $0.end, bounds: bounds) }
        if usageInDay.isEmpty {
            for segment in segments {
                secondsByCategory[segment.category, default: 0] += segment.durationSeconds
                appsByCategory[segment.category, default: []].insert(segment.bundleID ?? segment.appName)
            }
        } else {
            for usage in usageInDay {
                secondsByCategory[usage.category, default: 0] += clippedDuration(start: usage.start, end: usage.end, bounds: bounds)
                appsByCategory[usage.category, default: []].insert(usage.bundleID ?? usage.appName)
            }
        }

        return ActivityCategory.allCases
            .filter { $0 != .neutral || secondsByCategory[$0, default: 0] > 0 }
            .map {
                CategoryUsageSummary(
                    category: $0,
                    seconds: secondsByCategory[$0, default: 0],
                    appCount: appsByCategory[$0, default: []].count
                )
            }
            .sorted { lhs, rhs in
                if lhs.seconds == rhs.seconds {
                    return lhs.category.rawValue < rhs.category.rawValue
                }
                return lhs.seconds > rhs.seconds
            }
    }

    private func overlaps(_ start: Date, _ end: Date, bounds: (start: Date, end: Date)) -> Bool {
        end > bounds.start && start < bounds.end
    }

    private func clippedDuration(start: Date, end: Date, bounds: (start: Date, end: Date)) -> Int {
        max(0, Int(min(end, bounds.end).timeIntervalSince(max(start, bounds.start))))
    }

    private static func dayBounds(for date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        let start = calendar.startOfDay(for: date)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

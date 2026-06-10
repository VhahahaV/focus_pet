import Foundation

public struct ReportGenerator: Sendable {
    private static let sampledEventMergeGapSeconds: TimeInterval = 12
    private let timelineAnalyzer: StateTimelineAnalyzer

    public init() {
        timelineAnalyzer = StateTimelineAnalyzer(mergeGapSeconds: Self.sampledEventMergeGapSeconds)
    }

    public func makeDailySummary(
        for date: Date,
        events: [StateEvent],
        reminderCount: Int,
        petEnergy: Int? = nil
    ) -> DailySummary {
        let liveEvents = events.filter { $0.sourceKind == .live && Self.overlapsDay($0, date: date) }
        let demoEventCount = events.filter { $0.sourceKind == .demo && Self.overlapsDay($0, date: date) }.count
        let bounds = Self.dayBounds(for: date)
        let timeline = timelineAnalyzer.summarize(
            events: liveEvents,
            from: bounds.start,
            to: bounds.end,
            sourceKind: .live
        )
        let totalActiveSeconds = timeline.totalSeconds
        let focusSeconds = timeline.seconds(for: .focused)
        let distractedSeconds = timeline.seconds(for: .distracted)
        let awayCount = timeline.awayCount
        let longestFocusSeconds = timeline.longestFocusSeconds
        let resolvedPetEnergy = petEnergy ?? min(99, max(0, focusSeconds / 60))

        let summaryText = Self.makeSummaryText(
            focusSeconds: focusSeconds,
            longestFocusSeconds: longestFocusSeconds,
            distractedSeconds: distractedSeconds,
            awayCount: awayCount,
            petEnergy: resolvedPetEnergy
        )

        return DailySummary(
            date: Self.dateString(from: date),
            totalActiveSeconds: totalActiveSeconds,
            focusSeconds: focusSeconds,
            distractedSeconds: distractedSeconds,
            awayCount: awayCount,
            longestFocusSeconds: longestFocusSeconds,
            reminderCount: reminderCount,
            petEnergy: resolvedPetEnergy,
            liveEventCount: timeline.segments.count,
            demoEventCount: demoEventCount,
            summaryText: summaryText
        )
    }

    private static func makeSummaryText(
        focusSeconds: Int,
        longestFocusSeconds: Int,
        distractedSeconds: Int,
        awayCount: Int,
        petEnergy: Int
    ) -> String {
        let focusMinutes = focusSeconds / 60
        let longestMinutes = longestFocusSeconds / 60
        let distractedMinutes = distractedSeconds / 60

        if focusSeconds == 0 {
            return "今天还没有形成稳定专注记录。桌宠会继续观察专注、走神和暂离状态。"
        }

        return "今天有效专注 \(focusMinutes) 分钟，最长连续专注 \(longestMinutes) 分钟。走神 \(distractedMinutes) 分钟，暂离 \(awayCount) 次，桌宠获得 \(petEnergy) 点能量。"
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func overlapsDay(_ event: StateEvent, date: Date) -> Bool {
        let bounds = dayBounds(for: date)
        return event.endTime > bounds.start && event.startTime < bounds.end
    }

    private static func dayBounds(for date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}

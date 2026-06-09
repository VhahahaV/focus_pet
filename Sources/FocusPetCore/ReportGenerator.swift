import Foundation

public struct ReportGenerator: Sendable {
    public init() {}

    public func makeDailySummary(
        for date: Date,
        events: [StateEvent],
        reminderCount: Int,
        petEnergy: Int
    ) -> DailySummary {
        let totalActiveSeconds = events.reduce(0) { $0 + $1.durationSeconds }
        let focusSeconds = events
            .filter { $0.userState == .focused }
            .reduce(0) { $0 + $1.durationSeconds }
        let entertainmentSeconds = events
            .filter { $0.context == .entertainment || $0.userState == .entertainment }
            .reduce(0) { $0 + $1.durationSeconds }
        let offScreenCount = events
            .filter { $0.userState == .offScreen || $0.userState == .away }
            .count
        let lookingDownSeconds = events
            .filter { $0.userState == .lookingDown }
            .reduce(0) { $0 + $1.durationSeconds }
        let longestFocusSeconds = events
            .filter { $0.userState == .focused }
            .map(\.durationSeconds)
            .max() ?? 0

        let summaryText = Self.makeSummaryText(
            focusSeconds: focusSeconds,
            longestFocusSeconds: longestFocusSeconds,
            lookingDownSeconds: lookingDownSeconds,
            offScreenCount: offScreenCount,
            petEnergy: petEnergy
        )

        return DailySummary(
            date: Self.dateString(from: date),
            totalActiveSeconds: totalActiveSeconds,
            focusSeconds: focusSeconds,
            entertainmentSeconds: entertainmentSeconds,
            offScreenCount: offScreenCount,
            lookingDownSeconds: lookingDownSeconds,
            longestFocusSeconds: longestFocusSeconds,
            reminderCount: reminderCount,
            petEnergy: petEnergy,
            summaryText: summaryText
        )
    }

    private static func makeSummaryText(
        focusSeconds: Int,
        longestFocusSeconds: Int,
        lookingDownSeconds: Int,
        offScreenCount: Int,
        petEnergy: Int
    ) -> String {
        let focusMinutes = focusSeconds / 60
        let longestMinutes = longestFocusSeconds / 60
        let downMinutes = lookingDownSeconds / 60

        if focusSeconds == 0 {
            return "今天还没有形成稳定专注记录。桌宠会先保持安静陪伴。"
        }

        return "今天有效专注 \(focusMinutes) 分钟，最长连续专注 \(longestMinutes) 分钟。离屏 \(offScreenCount) 次，低头累计 \(downMinutes) 分钟，桌宠获得 \(petEnergy) 点能量。"
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

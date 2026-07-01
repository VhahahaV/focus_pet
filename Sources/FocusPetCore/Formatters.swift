import Foundation

public enum FocusPetFormatters {
    private static let clockFormatterKey = "FocusPetFormatters.clockFormatter"

    public static func duration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)秒"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)分钟"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)小时"
        }
        return "\(hours)小时\(remainingMinutes)分钟"
    }

    public static func clock(_ date: Date) -> String {
        let formatter = cachedClockFormatter()
        return formatter.string(from: date)
    }

    public static func percentage(_ ratio: Double) -> String {
        "\(Int((min(1, max(0, ratio)) * 100).rounded()))%"
    }

    public static func compactCount(_ value: Int) -> String {
        let value = max(0, value)
        if value < 10_000 {
            return "\(value)"
        }

        let wan = Double(value) / 10_000
        if wan >= 10 {
            return "\(Int(wan.rounded()))万"
        }

        let formatted = String(format: "%.1f", wan)
            .replacingOccurrences(of: ".0", with: "")
        return "\(formatted)万"
    }

    public static func estimatedTypedCharacters(_ value: Int) -> String {
        "键入约 \(compactCount(value)) 次"
    }

    public static func pointerActions(_ value: Int) -> String {
        "操作 \(compactCount(value)) 次"
    }

    public static func contextSwitches(_ value: Int) -> String {
        "切换 \(compactCount(value)) 次"
    }

    private static func cachedClockFormatter() -> DateFormatter {
        if let formatter = Thread.current.threadDictionary[clockFormatterKey] as? DateFormatter {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        Thread.current.threadDictionary[clockFormatterKey] = formatter
        return formatter
    }
}

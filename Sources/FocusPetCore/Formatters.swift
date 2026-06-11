import Foundation

public enum FocusPetFormatters {
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func percentage(_ ratio: Double) -> String {
        "\(Int((min(1, max(0, ratio)) * 100).rounded()))%"
    }
}

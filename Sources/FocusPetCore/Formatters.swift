import Foundation

public enum FocusPetFormatters {
    public static func duration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60

        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分钟"
        }

        return "\(minutes) 分钟"
    }
}

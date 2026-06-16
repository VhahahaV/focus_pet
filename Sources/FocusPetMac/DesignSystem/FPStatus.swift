import SwiftUI

enum FPStatus {
    case focus
    case distracted
    case rest
    case away
    case neutral
    case pet
    case privacy
    case warning
    case error

    var title: String {
        switch self {
        case .focus: return "专注"
        case .distracted: return "走神"
        case .rest: return "休息"
        case .away: return "离开"
        case .neutral: return "普通"
        case .pet: return "桌宠"
        case .privacy: return "权限"
        case .warning: return "提醒"
        case .error: return "异常"
        }
    }

    var primary: Color {
        switch self {
        case .focus: return FPColor.focus500
        case .distracted: return FPColor.distracted500
        case .rest: return FPColor.rest500
        case .away: return FPColor.away500
        case .neutral: return FPColor.textTertiary
        case .pet: return FPColor.petWarm500
        case .privacy: return FPColor.systemCyan500
        case .warning: return FPColor.warning
        case .error: return FPColor.error
        }
    }

    var strongText: Color {
        switch self {
        case .focus: return FPColor.focus600
        case .distracted: return FPColor.distracted600
        case .rest: return FPColor.rest600
        case .away, .neutral: return FPColor.textSecondary
        case .pet: return FPColor.petWarm500
        case .privacy: return FPColor.systemCyan500
        case .warning: return FPColor.warning
        case .error: return FPColor.error
        }
    }

    var softBackground: Color {
        switch self {
        case .focus: return FPColor.focus100
        case .distracted: return FPColor.distracted100
        case .rest: return FPColor.rest100
        case .away: return FPColor.away100
        case .neutral: return FPColor.controlSurface
        case .pet: return FPColor.petWarm100
        case .privacy: return FPColor.systemCyan100
        case .warning: return FPColor.warningBackground
        case .error: return FPColor.errorBackground
        }
    }

    var border: Color {
        switch self {
        case .focus: return FPColor.focus200
        case .distracted: return FPColor.distracted200
        case .rest: return FPColor.rest200
        case .away: return FPColor.away300
        case .neutral: return FPColor.borderDefault
        case .pet: return FPColor.petWarm300
        case .privacy: return FPColor.systemCyan300
        case .warning: return FPColor.warning.opacity(0.32)
        case .error: return FPColor.error.opacity(0.32)
        }
    }
}

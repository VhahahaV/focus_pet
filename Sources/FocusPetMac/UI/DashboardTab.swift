import Foundation

enum DashboardTab: Hashable, CaseIterable, Identifiable {
    case today
    case sessions
    case pet
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日"
        case .sessions: "历史"
        case .pet: "桌宠"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "house.fill"
        case .sessions: "clock"
        case .pet: "pawprint.fill"
        case .settings: "gearshape.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .today: "专注当下，长期主义"
        case .sessions: "复盘专注节奏与注意力分布"
        case .pet: "资源包、动作与悬浮表现"
        case .settings: "管理判定、提醒与本地数据"
        }
    }
}

enum DashboardPetAnchor: String, Hashable {
    case todayFocusCard
    case todayBreakControl
    case todayTimeline
    case sidebarPetDock
    case historyWorkTimeline
    case dashboardPanel
    case settingsPetPanel
    case petPreviewStage
}

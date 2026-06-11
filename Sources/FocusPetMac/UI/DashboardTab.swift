import Foundation

enum DashboardTab: Hashable, CaseIterable, Identifiable {
    case today
    case distribution
    case sessions
    case rules
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日"
        case .distribution: "时间分布"
        case .sessions: "专注会话"
        case .rules: "规则"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "chart.bar.xaxis"
        case .distribution: "chart.pie.fill"
        case .sessions: "timer"
        case .rules: "slider.horizontal.3"
        case .settings: "gearshape.fill"
        }
    }
}

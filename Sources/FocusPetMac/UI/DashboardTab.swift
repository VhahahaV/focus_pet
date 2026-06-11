import Foundation

enum DashboardTab: Hashable, CaseIterable, Identifiable {
    case today
    case sessions
    case rules
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日"
        case .sessions: "历史"
        case .rules: "规则"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "chart.bar.xaxis"
        case .sessions: "clock.arrow.circlepath"
        case .rules: "slider.horizontal.3"
        case .settings: "gearshape.fill"
        }
    }
}

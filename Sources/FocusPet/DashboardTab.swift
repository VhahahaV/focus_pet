import AppKit
import Foundation

enum DashboardTab: Hashable, CaseIterable, Identifiable {
    case today
    case rules
    case pet
    case faceLog
    case privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "今日"
        case .rules: "规则"
        case .pet: "桌宠"
        case .faceLog: "判断日志"
        case .privacy: "隐私"
        }
    }

    var symbolName: String {
        switch self {
        case .today: "chart.bar.xaxis"
        case .rules: "slider.horizontal.3"
        case .pet: "pawprint.fill"
        case .faceLog: "waveform.path.ecg.rectangle"
        case .privacy: "lock.shield.fill"
        }
    }
}

@MainActor
enum DashboardWindowCoordinator {
    static var opener: ((DashboardTab) -> Void)?

    static func open(_ tab: DashboardTab) {
        if let opener {
            opener(tab)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "Focus Pet" }?.makeKeyAndOrderFront(nil)
        }
    }
}

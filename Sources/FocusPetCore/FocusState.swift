import Foundation

public enum FocusState: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case focus
    case distracted
    case breakTime = "break"
    case away

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focus: "专注"
        case .distracted: "走神"
        case .breakTime: "休息"
        case .away: "暂离"
        }
    }

    public var symbolName: String {
        switch self {
        case .focus: "checkmark.circle.fill"
        case .distracted: "eye.trianglebadge.exclamationmark"
        case .breakTime: "cup.and.saucer.fill"
        case .away: "moon.zzz.fill"
        }
    }
}

public enum ActivityCategory: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case work
    case entertainment
    case ignore
    case neutral

    public var id: String { rawValue }

    public static let userFacingClassificationCases: [ActivityCategory] = [.work, .entertainment, .ignore]

    public var title: String {
        switch self {
        case .work: "工作工具"
        case .entertainment: "容易分心"
        case .ignore: "不参与判断"
        case .neutral: "旧数据"
        }
    }

    public var correctionTitle: String {
        switch self {
        case .work: "通常用于工作"
        case .entertainment: "容易让我分心"
        case .ignore: "不参与判断"
        case .neutral: "旧数据"
        }
    }
}

public enum ActivitySignalSource: String, Codable, Hashable, Sendable, CaseIterable {
    case frontmostApplication
    case windowTitle
    case idleTime
    case appSwitching
    case focusSession
    case breakSession
    case systemSleep
    case screenLock
}

public struct FocusStateSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var timestamp: Date
    public var state: FocusState
    public var category: ActivityCategory
    public var stableDuration: TimeInterval
    public var appName: String
    public var bundleID: String?
    public var reason: [StateReason]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        state: FocusState,
        category: ActivityCategory,
        stableDuration: TimeInterval,
        appName: String,
        bundleID: String?,
        reason: [StateReason] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.category = category
        self.stableDuration = max(0, stableDuration)
        self.appName = appName
        self.bundleID = bundleID
        self.reason = reason
    }
}

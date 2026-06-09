import Foundation

public enum GazeState: String, Codable, Hashable, Sendable, CaseIterable {
    case screen
    case offScreen
    case down
    case side
    case unknown
}

public enum ObservationSourceKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case live
    case demo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .live: "真实检测"
        case .demo: "Demo"
        }
    }
}

public enum RuntimeMode: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case live
    case demo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .live: "真实检测"
        case .demo: "Demo"
        }
    }

    public var sourceKind: ObservationSourceKind {
        switch self {
        case .live: .live
        case .demo: .demo
        }
    }
}

public enum FacePresence: String, Codable, Hashable, Sendable, CaseIterable {
    case present
    case missing
    case unknown
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var runtimeMode: RuntimeMode
    public var isPaused: Bool
    public var petOpacity: Double
    public var petScale: Double
    public var petAnimationEnabled: Bool
    public var soundEnabled: Bool

    public init(
        hasCompletedOnboarding: Bool = false,
        runtimeMode: RuntimeMode = .live,
        isPaused: Bool = false,
        petOpacity: Double = 0.94,
        petScale: Double = 1.0,
        petAnimationEnabled: Bool = true,
        soundEnabled: Bool = false
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.runtimeMode = runtimeMode
        self.isPaused = isPaused
        self.petOpacity = petOpacity
        self.petScale = petScale
        self.petAnimationEnabled = petAnimationEnabled
        self.soundEnabled = soundEnabled
    }
}

public enum ContextType: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case work
    case entertainment
    case meeting
    case neutral

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .work: "办公"
        case .entertainment: "娱乐"
        case .meeting: "会议"
        case .neutral: "普通"
        }
    }
}

public enum UserState: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case focused
    case possiblyDistracted
    case offScreen
    case lookingDown
    case away
    case resting
    case entertainment
    case meeting
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focused: "专注中"
        case .possiblyDistracted: "可能走神"
        case .offScreen: "看向屏幕外"
        case .lookingDown: "低头中"
        case .away: "离开中"
        case .resting: "休息中"
        case .entertainment: "娱乐中"
        case .meeting: "会议中"
        case .unknown: "识别中"
        }
    }

    public var statusSymbolName: String {
        switch self {
        case .focused: "checkmark.circle.fill"
        case .possiblyDistracted: "eye.trianglebadge.exclamationmark"
        case .offScreen: "eye.slash.fill"
        case .lookingDown: "figure.mind.and.body"
        case .away: "moon.zzz.fill"
        case .resting: "cup.and.saucer.fill"
        case .entertainment: "play.rectangle.fill"
        case .meeting: "video.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

public enum ReminderStrength: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case silent
    case light
    case medium
    case strong

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .silent: "静默记录"
        case .light: "桌宠气泡"
        case .medium: "系统通知"
        case .strong: "强提醒"
        }
    }
}

public enum ReminderActionType: String, Codable, Hashable, Sendable, CaseIterable {
    case petBubble
    case systemNotification
    case petAnimation
    case silentLog
}

public struct StateObservation: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var sourceKind: ObservationSourceKind
    public var facePresence: FacePresence
    public var gazeState: GazeState
    public var headPitchDegrees: Double
    public var frontAppName: String?
    public var context: ContextType
    public var lastInputSeconds: TimeInterval
    public var stableDurationSeconds: TimeInterval

    public var facePresent: Bool {
        facePresence == .present
    }

    public init(
        timestamp: Date,
        sourceKind: ObservationSourceKind = .live,
        facePresence: FacePresence,
        gazeState: GazeState,
        headPitchDegrees: Double,
        frontAppName: String?,
        context: ContextType,
        lastInputSeconds: TimeInterval,
        stableDurationSeconds: TimeInterval
    ) {
        self.timestamp = timestamp
        self.sourceKind = sourceKind
        self.facePresence = facePresence
        self.gazeState = gazeState
        self.headPitchDegrees = headPitchDegrees
        self.frontAppName = frontAppName
        self.context = context
        self.lastInputSeconds = lastInputSeconds
        self.stableDurationSeconds = stableDurationSeconds
    }

    public init(
        timestamp: Date,
        sourceKind: ObservationSourceKind = .live,
        facePresent: Bool,
        gazeState: GazeState,
        headPitchDegrees: Double,
        frontAppName: String?,
        context: ContextType,
        lastInputSeconds: TimeInterval,
        stableDurationSeconds: TimeInterval
    ) {
        self.init(
            timestamp: timestamp,
            sourceKind: sourceKind,
            facePresence: facePresent ? .present : .missing,
            gazeState: gazeState,
            headPitchDegrees: headPitchDegrees,
            frontAppName: frontAppName,
            context: context,
            lastInputSeconds: lastInputSeconds,
            stableDurationSeconds: stableDurationSeconds
        )
    }
}

public struct FusedUserState: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var userState: UserState
    public var context: ContextType
    public var confidence: Double
    public var reason: [String]
    public var stableDurationSeconds: TimeInterval

    public init(
        timestamp: Date,
        userState: UserState,
        context: ContextType,
        confidence: Double,
        reason: [String],
        stableDurationSeconds: TimeInterval
    ) {
        self.timestamp = timestamp
        self.userState = userState
        self.context = context
        self.confidence = confidence
        self.reason = reason
        self.stableDurationSeconds = stableDurationSeconds
    }
}

public struct RuleAction: Codable, Hashable, Sendable {
    public var type: ReminderActionType
    public var message: String
    public var strength: ReminderStrength

    public init(type: ReminderActionType, message: String, strength: ReminderStrength) {
        self.type = type
        self.message = message
        self.strength = strength
    }
}

public struct FocusRule: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var contexts: Set<ContextType>
    public var states: Set<UserState>
    public var durationSeconds: TimeInterval
    public var cooldownSeconds: TimeInterval
    public var action: RuleAction

    public init(
        id: String,
        name: String,
        isEnabled: Bool,
        contexts: Set<ContextType>,
        states: Set<UserState>,
        durationSeconds: TimeInterval,
        cooldownSeconds: TimeInterval,
        action: RuleAction
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.contexts = contexts
        self.states = states
        self.durationSeconds = durationSeconds
        self.cooldownSeconds = cooldownSeconds
        self.action = action
    }
}

public extension FocusRule {
    static let workDistraction = FocusRule(
        id: "rule.work.distraction",
        name: "办公走神提醒",
        isEnabled: true,
        contexts: [.work],
        states: [.possiblyDistracted, .offScreen],
        durationSeconds: 30,
        cooldownSeconds: 300,
        action: RuleAction(
            type: .petBubble,
            message: "刚才可能走神了，要回到当前任务吗？",
            strength: .light
        )
    )

    static let postureReminder = FocusRule(
        id: "rule.posture.down",
        name: "低头提醒",
        isEnabled: true,
        contexts: [.work, .neutral],
        states: [.lookingDown],
        durationSeconds: 120,
        cooldownSeconds: 600,
        action: RuleAction(
            type: .petBubble,
            message: "你已经低头一会儿了，要不要抬头休息一下？",
            strength: .light
        )
    )

    static let entertainmentLimit = FocusRule(
        id: "rule.entertainment.limit",
        name: "娱乐超时提醒",
        isEnabled: true,
        contexts: [.entertainment],
        states: [.entertainment],
        durationSeconds: 1_200,
        cooldownSeconds: 3_600,
        action: RuleAction(
            type: .systemNotification,
            message: "已经娱乐 20 分钟，要继续还是回到任务？",
            strength: .medium
        )
    )

    static let restEncouragement = FocusRule(
        id: "rule.focus.break",
        name: "休息鼓励",
        isEnabled: true,
        contexts: [.work],
        states: [.focused],
        durationSeconds: 2_700,
        cooldownSeconds: 2_700,
        action: RuleAction(
            type: .petBubble,
            message: "已经连续专注 45 分钟，可以休息 5 分钟。",
            strength: .light
        )
    )

    static let defaults: [FocusRule] = [
        .workDistraction,
        .postureReminder,
        .entertainmentLimit,
        .restEncouragement
    ]
}

public struct ReminderDecision: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var ruleID: String
    public var triggeredAt: Date
    public var userState: UserState
    public var action: RuleAction

    public init(id: String, ruleID: String, triggeredAt: Date, userState: UserState, action: RuleAction) {
        self.id = id
        self.ruleID = ruleID
        self.triggeredAt = triggeredAt
        self.userState = userState
        self.action = action
    }
}

public struct StateEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sourceKind: ObservationSourceKind
    public var startTime: Date
    public var endTime: Date
    public var userState: UserState
    public var context: ContextType
    public var confidence: Double
    public var reason: [String]

    public init(
        id: String,
        sourceKind: ObservationSourceKind = .live,
        startTime: Date,
        endTime: Date,
        userState: UserState,
        context: ContextType,
        confidence: Double,
        reason: [String]
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.startTime = startTime
        self.endTime = endTime
        self.userState = userState
        self.context = context
        self.confidence = confidence
        self.reason = reason
    }

    public var durationSeconds: Int {
        max(0, Int(endTime.timeIntervalSince(startTime)))
    }
}

public struct DailySummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String { date }
    public var date: String
    public var totalActiveSeconds: Int
    public var focusSeconds: Int
    public var entertainmentSeconds: Int
    public var offScreenCount: Int
    public var lookingDownSeconds: Int
    public var longestFocusSeconds: Int
    public var reminderCount: Int
    public var petEnergy: Int
    public var liveEventCount: Int
    public var demoEventCount: Int
    public var summaryText: String

    public init(
        date: String,
        totalActiveSeconds: Int,
        focusSeconds: Int,
        entertainmentSeconds: Int,
        offScreenCount: Int,
        lookingDownSeconds: Int,
        longestFocusSeconds: Int,
        reminderCount: Int,
        petEnergy: Int,
        liveEventCount: Int = 0,
        demoEventCount: Int = 0,
        summaryText: String
    ) {
        self.date = date
        self.totalActiveSeconds = totalActiveSeconds
        self.focusSeconds = focusSeconds
        self.entertainmentSeconds = entertainmentSeconds
        self.offScreenCount = offScreenCount
        self.lookingDownSeconds = lookingDownSeconds
        self.longestFocusSeconds = longestFocusSeconds
        self.reminderCount = reminderCount
        self.petEnergy = petEnergy
        self.liveEventCount = liveEventCount
        self.demoEventCount = demoEventCount
        self.summaryText = summaryText
    }
}

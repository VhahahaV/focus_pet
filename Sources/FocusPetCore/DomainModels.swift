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

public enum FacePresence: String, Codable, Hashable, Sendable, CaseIterable {
    case present
    case missing
    case unknown
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var isPaused: Bool
    public var pauseUntil: Date?
    public var petOpacity: Double
    public var petScale: Double
    public var petAnimationEnabled: Bool
    public var petSize: Double
    public var petHidden: Bool
    public var petHiddenUntil: Date?
    public var petPlacementMode: PetPlacementMode
    public var petManualOriginX: Double?
    public var petManualOriginY: Double?
    public var petHoverMenuEnabled: Bool
    public var cameraSamplingEnabled: Bool
    public var soundEnabled: Bool
    public var selectedPetPackID: String

    public init(
        hasCompletedOnboarding: Bool = false,
        isPaused: Bool = false,
        pauseUntil: Date? = nil,
        petOpacity: Double = 0.94,
        petScale: Double = 1.0,
        petAnimationEnabled: Bool = true,
        petSize: Double = 128,
        petHidden: Bool = false,
        petHiddenUntil: Date? = nil,
        petPlacementMode: PetPlacementMode = .dockAttached,
        petManualOriginX: Double? = nil,
        petManualOriginY: Double? = nil,
        petHoverMenuEnabled: Bool = true,
        cameraSamplingEnabled: Bool = false,
        soundEnabled: Bool = false,
        selectedPetPackID: String = PetPackDefaults.luoXiaoHeiLocalID
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.isPaused = isPaused
        self.pauseUntil = pauseUntil
        self.petOpacity = petOpacity
        self.petScale = petScale
        self.petAnimationEnabled = petAnimationEnabled
        self.petSize = petSize
        self.petHidden = petHidden
        self.petHiddenUntil = petHiddenUntil
        self.petPlacementMode = petPlacementMode
        self.petManualOriginX = petManualOriginX
        self.petManualOriginY = petManualOriginY
        self.petHoverMenuEnabled = petHoverMenuEnabled
        self.cameraSamplingEnabled = cameraSamplingEnabled
        self.soundEnabled = soundEnabled
        self.selectedPetPackID = selectedPetPackID
    }

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case isPaused
        case pauseUntil
        case petOpacity
        case petScale
        case petAnimationEnabled
        case petSize
        case petHidden
        case petHiddenUntil
        case petPlacementMode
        case petManualOriginX
        case petManualOriginY
        case petHoverMenuEnabled
        case cameraSamplingEnabled
        case soundEnabled
        case selectedPetPackID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        pauseUntil = try container.decodeIfPresent(Date.self, forKey: .pauseUntil)
        petOpacity = try container.decodeIfPresent(Double.self, forKey: .petOpacity) ?? 0.94
        petScale = try container.decodeIfPresent(Double.self, forKey: .petScale) ?? 1.0
        petAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .petAnimationEnabled) ?? true
        petSize = try container.decodeIfPresent(Double.self, forKey: .petSize) ?? 128
        petHidden = try container.decodeIfPresent(Bool.self, forKey: .petHidden) ?? false
        petHiddenUntil = try container.decodeIfPresent(Date.self, forKey: .petHiddenUntil)
        petPlacementMode = try container.decodeIfPresent(PetPlacementMode.self, forKey: .petPlacementMode) ?? .dockAttached
        petManualOriginX = try container.decodeIfPresent(Double.self, forKey: .petManualOriginX)
        petManualOriginY = try container.decodeIfPresent(Double.self, forKey: .petManualOriginY)
        petHoverMenuEnabled = try container.decodeIfPresent(Bool.self, forKey: .petHoverMenuEnabled) ?? true
        cameraSamplingEnabled = try container.decodeIfPresent(Bool.self, forKey: .cameraSamplingEnabled) ?? false
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        selectedPetPackID = try container.decodeIfPresent(String.self, forKey: .selectedPetPackID)
            ?? PetPackDefaults.luoXiaoHeiLocalID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encodeIfPresent(pauseUntil, forKey: .pauseUntil)
        try container.encode(petOpacity, forKey: .petOpacity)
        try container.encode(petScale, forKey: .petScale)
        try container.encode(petAnimationEnabled, forKey: .petAnimationEnabled)
        try container.encode(petSize, forKey: .petSize)
        try container.encode(petHidden, forKey: .petHidden)
        try container.encodeIfPresent(petHiddenUntil, forKey: .petHiddenUntil)
        try container.encode(petPlacementMode, forKey: .petPlacementMode)
        try container.encodeIfPresent(petManualOriginX, forKey: .petManualOriginX)
        try container.encodeIfPresent(petManualOriginY, forKey: .petManualOriginY)
        try container.encode(petHoverMenuEnabled, forKey: .petHoverMenuEnabled)
        try container.encode(cameraSamplingEnabled, forKey: .cameraSamplingEnabled)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(selectedPetPackID, forKey: .selectedPetPackID)
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
    case distracted
    case away

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focused: "专注"
        case .distracted: "走神"
        case .away: "暂离"
        }
    }

    public var statusSymbolName: String {
        switch self {
        case .focused: "checkmark.circle.fill"
        case .distracted: "eye.trianglebadge.exclamationmark"
        case .away: "moon.zzz.fill"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.focused.rawValue, "resting", "meeting":
            self = .focused
        case Self.distracted.rawValue, "possiblyDistracted", "offScreen", "lookingDown", "entertainment", "unknown":
            self = .distracted
        case Self.away.rawValue:
            self = .away
        default:
            self = .distracted
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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

public struct LocalActivitySnapshot: Codable, Hashable, Sendable {
    public var lastInputSeconds: TimeInterval
    public var lastKeyboardSeconds: TimeInterval
    public var lastMouseSeconds: TimeInterval
    public var lastScrollSeconds: TimeInterval
    public var lastAppSwitchSeconds: TimeInterval
    public var frontAppStableSeconds: TimeInterval
    public var windowTitleStableSeconds: TimeInterval
    public var hasDetailedInputBreakdown: Bool

    public init(
        lastInputSeconds: TimeInterval,
        lastKeyboardSeconds: TimeInterval? = nil,
        lastMouseSeconds: TimeInterval? = nil,
        lastScrollSeconds: TimeInterval? = nil,
        lastAppSwitchSeconds: TimeInterval? = nil,
        frontAppStableSeconds: TimeInterval = 0,
        windowTitleStableSeconds: TimeInterval = 0,
        hasDetailedInputBreakdown: Bool = true
    ) {
        self.lastInputSeconds = max(0, lastInputSeconds)
        self.lastKeyboardSeconds = max(0, lastKeyboardSeconds ?? lastInputSeconds)
        self.lastMouseSeconds = max(0, lastMouseSeconds ?? lastInputSeconds)
        self.lastScrollSeconds = max(0, lastScrollSeconds ?? lastInputSeconds)
        self.lastAppSwitchSeconds = max(0, lastAppSwitchSeconds ?? frontAppStableSeconds)
        self.frontAppStableSeconds = max(0, frontAppStableSeconds)
        self.windowTitleStableSeconds = max(0, windowTitleStableSeconds)
        self.hasDetailedInputBreakdown = hasDetailedInputBreakdown
    }

    public static func legacy(lastInputSeconds: TimeInterval) -> LocalActivitySnapshot {
        LocalActivitySnapshot(
            lastInputSeconds: lastInputSeconds,
            lastKeyboardSeconds: lastInputSeconds,
            lastMouseSeconds: lastInputSeconds,
            lastScrollSeconds: lastInputSeconds,
            lastAppSwitchSeconds: 0,
            frontAppStableSeconds: 0,
            windowTitleStableSeconds: 0,
            hasDetailedInputBreakdown: false
        )
    }

    public var hasRecentInput: Bool {
        lastInputSeconds <= 30
    }

    public var hasRecentKeyboardInput: Bool {
        hasDetailedInputBreakdown && lastKeyboardSeconds <= 30
    }

    public var hasRecentMouseOrScrollInput: Bool {
        hasDetailedInputBreakdown && min(lastMouseSeconds, lastScrollSeconds) <= 30
    }

    public var hasStableFrontApp: Bool {
        frontAppStableSeconds >= 30
    }
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
    public var localActivity: LocalActivitySnapshot

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
        stableDurationSeconds: TimeInterval,
        localActivity: LocalActivitySnapshot? = nil
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
        self.localActivity = localActivity ?? .legacy(lastInputSeconds: lastInputSeconds)
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
        stableDurationSeconds: TimeInterval,
        localActivity: LocalActivitySnapshot? = nil
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
            stableDurationSeconds: stableDurationSeconds,
            localActivity: localActivity
        )
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case sourceKind
        case facePresence
        case facePresent
        case gazeState
        case headPitchDegrees
        case frontAppName
        case context
        case lastInputSeconds
        case stableDurationSeconds
        case localActivity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sourceKind = try container.decodeIfPresent(ObservationSourceKind.self, forKey: .sourceKind) ?? .live

        if let decodedPresence = try container.decodeIfPresent(FacePresence.self, forKey: .facePresence) {
            facePresence = decodedPresence
        } else if let legacyFacePresent = try container.decodeIfPresent(Bool.self, forKey: .facePresent) {
            facePresence = legacyFacePresent ? .present : .missing
        } else {
            facePresence = .unknown
        }

        gazeState = try container.decodeIfPresent(GazeState.self, forKey: .gazeState) ?? .unknown
        headPitchDegrees = try container.decodeIfPresent(Double.self, forKey: .headPitchDegrees) ?? 0
        frontAppName = try container.decodeIfPresent(String.self, forKey: .frontAppName)
        context = try container.decodeIfPresent(ContextType.self, forKey: .context) ?? .neutral
        lastInputSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .lastInputSeconds) ?? 0
        stableDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .stableDurationSeconds) ?? 0
        localActivity = try container.decodeIfPresent(LocalActivitySnapshot.self, forKey: .localActivity)
            ?? .legacy(lastInputSeconds: lastInputSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(facePresence, forKey: .facePresence)
        try container.encode(gazeState, forKey: .gazeState)
        try container.encode(headPitchDegrees, forKey: .headPitchDegrees)
        try container.encodeIfPresent(frontAppName, forKey: .frontAppName)
        try container.encode(context, forKey: .context)
        try container.encode(lastInputSeconds, forKey: .lastInputSeconds)
        try container.encode(stableDurationSeconds, forKey: .stableDurationSeconds)
        try container.encode(localActivity, forKey: .localActivity)
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
    static let distractionReminder = FocusRule(
        id: "rule.distraction",
        name: "走神提醒",
        isEnabled: true,
        contexts: [.work, .neutral, .meeting],
        states: [.distracted],
        durationSeconds: 20,
        cooldownSeconds: 300,
        action: RuleAction(
            type: .petBubble,
            message: "刚才可能走神了，要回到当前任务吗？",
            strength: .light
        )
    )

    static let entertainmentDistraction = FocusRule(
        id: "rule.entertainment.distraction",
        name: "娱乐走神提醒",
        isEnabled: true,
        contexts: [.entertainment],
        states: [.distracted],
        durationSeconds: 60,
        cooldownSeconds: 900,
        action: RuleAction(
            type: .petBubble,
            message: "已经进入娱乐走神状态，要回到任务吗？",
            strength: .light
        )
    )

    static let awayReminder = FocusRule(
        id: "rule.away",
        name: "暂离过久提醒",
        isEnabled: true,
        contexts: [.work, .neutral, .meeting, .entertainment],
        states: [.away],
        durationSeconds: 180,
        cooldownSeconds: 900,
        action: RuleAction(
            type: .petBubble,
            message: "检测到你暂离了一会儿，需要暂停记录吗？",
            strength: .light
        )
    )

    static let defaults: [FocusRule] = [
        .distractionReminder,
        .entertainmentDistraction,
        .awayReminder
    ]

    static var currentRuleIDs: Set<String> {
        Set(defaults.map(\.id))
    }
}

public struct ReminderDecision: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var ruleID: String
    public var sourceKind: ObservationSourceKind
    public var triggeredAt: Date
    public var userState: UserState
    public var action: RuleAction

    public init(
        id: String,
        ruleID: String,
        sourceKind: ObservationSourceKind = .live,
        triggeredAt: Date,
        userState: UserState,
        action: RuleAction
    ) {
        self.id = id
        self.ruleID = ruleID
        self.sourceKind = sourceKind
        self.triggeredAt = triggeredAt
        self.userState = userState
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case ruleID
        case sourceKind
        case triggeredAt
        case userState
        case action
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ruleID = try container.decode(String.self, forKey: .ruleID)
        sourceKind = try container.decodeIfPresent(ObservationSourceKind.self, forKey: .sourceKind) ?? .demo
        triggeredAt = try container.decode(Date.self, forKey: .triggeredAt)
        userState = try container.decode(UserState.self, forKey: .userState)
        action = try container.decode(RuleAction.self, forKey: .action)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ruleID, forKey: .ruleID)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encode(triggeredAt, forKey: .triggeredAt)
        try container.encode(userState, forKey: .userState)
        try container.encode(action, forKey: .action)
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
    public var distractedSeconds: Int
    public var awayCount: Int
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
        distractedSeconds: Int,
        awayCount: Int,
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
        self.distractedSeconds = distractedSeconds
        self.awayCount = awayCount
        self.longestFocusSeconds = longestFocusSeconds
        self.reminderCount = reminderCount
        self.petEnergy = petEnergy
        self.liveEventCount = liveEventCount
        self.demoEventCount = demoEventCount
        self.summaryText = summaryText
    }
}

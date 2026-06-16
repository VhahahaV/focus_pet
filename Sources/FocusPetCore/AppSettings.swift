import Foundation

public struct ReminderSettings: Codable, Hashable, Sendable {
    public var enablePetBubbles: Bool
    public var enableSystemNotifications: Bool
    public var hasAppliedSystemNotificationDefault: Bool
    public var pauseUntil: Date?
    public var pauseMinutes: Int
    public var enableDistractedNudges: Bool
    public var enableFocusRestNudges: Bool
    public var enableWelcomeBackNudges: Bool
    public var lightDistractedMinutes: Int
    public var strongDistractedMinutes: Int
    public var longFocusMinutes: Int
    public var veryLongFocusMinutes: Int
    public var cooldownMinutes: Int

    public init(
        enablePetBubbles: Bool = true,
        enableSystemNotifications: Bool = false,
        hasAppliedSystemNotificationDefault: Bool = true,
        pauseUntil: Date? = nil,
        pauseMinutes: Int = 30,
        enableDistractedNudges: Bool = true,
        enableFocusRestNudges: Bool = true,
        enableWelcomeBackNudges: Bool = true,
        lightDistractedMinutes: Int = 8,
        strongDistractedMinutes: Int = 15,
        longFocusMinutes: Int = 25,
        veryLongFocusMinutes: Int = 60,
        cooldownMinutes: Int = 10
    ) {
        self.enablePetBubbles = enablePetBubbles
        self.enableSystemNotifications = enableSystemNotifications
        self.hasAppliedSystemNotificationDefault = hasAppliedSystemNotificationDefault
        self.pauseUntil = pauseUntil
        self.pauseMinutes = min(240, max(5, pauseMinutes))
        self.enableDistractedNudges = enableDistractedNudges
        self.enableFocusRestNudges = enableFocusRestNudges
        self.enableWelcomeBackNudges = enableWelcomeBackNudges
        self.lightDistractedMinutes = min(60, max(1, lightDistractedMinutes))
        self.strongDistractedMinutes = min(120, max(self.lightDistractedMinutes, strongDistractedMinutes))
        self.longFocusMinutes = min(180, max(5, longFocusMinutes))
        self.veryLongFocusMinutes = min(240, max(self.longFocusMinutes, veryLongFocusMinutes))
        self.cooldownMinutes = min(60, max(1, cooldownMinutes))
    }

    public var nudgePolicyThresholds: NudgePolicyThresholds {
        NudgePolicyThresholds(
            lightDistractedSeconds: TimeInterval(lightDistractedMinutes * 60),
            strongDistractedSeconds: TimeInterval(strongDistractedMinutes * 60),
            longFocusSeconds: TimeInterval(longFocusMinutes * 60),
            veryLongFocusSeconds: TimeInterval(veryLongFocusMinutes * 60),
            cooldownSeconds: TimeInterval(cooldownMinutes * 60)
        )
    }

    public func allows(_ reason: NudgeReason) -> Bool {
        switch reason {
        case .distractedOverThreshold, .distractedStrong, .frequentSwitching:
            enableDistractedNudges
        case .longFocusRest, .veryLongFocusRest, .focusSessionCompleted, .breakEnding:
            enableFocusRestNudges
        case .welcomeBack:
            enableWelcomeBackNudges
        }
    }

    public mutating func normalize() {
        self = ReminderSettings(
            enablePetBubbles: enablePetBubbles,
            enableSystemNotifications: enableSystemNotifications,
            hasAppliedSystemNotificationDefault: hasAppliedSystemNotificationDefault,
            pauseUntil: pauseUntil,
            pauseMinutes: pauseMinutes,
            enableDistractedNudges: enableDistractedNudges,
            enableFocusRestNudges: enableFocusRestNudges,
            enableWelcomeBackNudges: enableWelcomeBackNudges,
            lightDistractedMinutes: lightDistractedMinutes,
            strongDistractedMinutes: strongDistractedMinutes,
            longFocusMinutes: longFocusMinutes,
            veryLongFocusMinutes: veryLongFocusMinutes,
            cooldownMinutes: cooldownMinutes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case enablePetBubbles
        case enableSystemNotifications
        case hasAppliedSystemNotificationDefault
        case pauseUntil
        case pauseMinutes
        case enableDistractedNudges
        case enableFocusRestNudges
        case enableWelcomeBackNudges
        case lightDistractedMinutes
        case strongDistractedMinutes
        case longFocusMinutes
        case veryLongFocusMinutes
        case cooldownMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enablePetBubbles: try container.decodeIfPresent(Bool.self, forKey: .enablePetBubbles) ?? true,
            enableSystemNotifications: try container.decodeIfPresent(Bool.self, forKey: .enableSystemNotifications) ?? false,
            hasAppliedSystemNotificationDefault: try container.decodeIfPresent(Bool.self, forKey: .hasAppliedSystemNotificationDefault) ?? false,
            pauseUntil: try container.decodeIfPresent(Date.self, forKey: .pauseUntil),
            pauseMinutes: try container.decodeIfPresent(Int.self, forKey: .pauseMinutes) ?? 30,
            enableDistractedNudges: try container.decodeIfPresent(Bool.self, forKey: .enableDistractedNudges) ?? true,
            enableFocusRestNudges: try container.decodeIfPresent(Bool.self, forKey: .enableFocusRestNudges) ?? true,
            enableWelcomeBackNudges: try container.decodeIfPresent(Bool.self, forKey: .enableWelcomeBackNudges) ?? true,
            lightDistractedMinutes: try container.decodeIfPresent(Int.self, forKey: .lightDistractedMinutes) ?? 8,
            strongDistractedMinutes: try container.decodeIfPresent(Int.self, forKey: .strongDistractedMinutes) ?? 15,
            longFocusMinutes: try container.decodeIfPresent(Int.self, forKey: .longFocusMinutes) ?? 25,
            veryLongFocusMinutes: try container.decodeIfPresent(Int.self, forKey: .veryLongFocusMinutes) ?? 60,
            cooldownMinutes: try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 10
        )
    }
}

public enum PetPlacementMode: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft
    case dock
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bottomRight: "右下角"
        case .bottomLeft: "左下角"
        case .topRight: "右上角"
        case .topLeft: "左上角"
        case .dock: "Dock 附近"
        case .custom: "自定义"
        }
    }

    public var symbolName: String {
        switch self {
        case .bottomRight: "arrow.down.right"
        case .bottomLeft: "arrow.down.left"
        case .topRight: "arrow.up.right"
        case .topLeft: "arrow.up.left"
        case .dock: "dock.rectangle"
        case .custom: "hand.draw"
        }
    }
}

public struct DataRetentionSettings: Codable, Hashable, Sendable {
    public var stateRetentionDays: Int
    public var appUsageRetentionDays: Int
    public var inputActivityRetentionDays: Int
    public var sessionRetentionDays: Int
    public var nudgeRetentionDays: Int

    public init(
        stateRetentionDays: Int = 30,
        appUsageRetentionDays: Int = 30,
        inputActivityRetentionDays: Int = 30,
        sessionRetentionDays: Int = 90,
        nudgeRetentionDays: Int = 30
    ) {
        self.stateRetentionDays = max(1, stateRetentionDays)
        self.appUsageRetentionDays = max(1, appUsageRetentionDays)
        self.inputActivityRetentionDays = max(1, inputActivityRetentionDays)
        self.sessionRetentionDays = max(1, sessionRetentionDays)
        self.nudgeRetentionDays = max(1, nudgeRetentionDays)
    }

    private enum CodingKeys: String, CodingKey {
        case stateRetentionDays
        case appUsageRetentionDays
        case inputActivityRetentionDays
        case sessionRetentionDays
        case nudgeRetentionDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            stateRetentionDays: try container.decodeIfPresent(Int.self, forKey: .stateRetentionDays) ?? 30,
            appUsageRetentionDays: try container.decodeIfPresent(Int.self, forKey: .appUsageRetentionDays) ?? 30,
            inputActivityRetentionDays: try container.decodeIfPresent(Int.self, forKey: .inputActivityRetentionDays) ?? 30,
            sessionRetentionDays: try container.decodeIfPresent(Int.self, forKey: .sessionRetentionDays) ?? 90,
            nudgeRetentionDays: try container.decodeIfPresent(Int.self, forKey: .nudgeRetentionDays) ?? 30
        )
    }
}

public struct JudgmentSettings: Codable, Hashable, Sendable {
    public var inputIdleDistractedSeconds: Int
    public var entertainmentDistractedSeconds: Int
    public var focusRecoverySeconds: Int
    public var idleAwaySeconds: Int

    public init(
        inputIdleDistractedSeconds: Int = 180,
        entertainmentDistractedSeconds: Int = 60,
        focusRecoverySeconds: Int = 10,
        idleAwaySeconds: Int = 10 * 60
    ) {
        self.inputIdleDistractedSeconds = min(900, max(30, inputIdleDistractedSeconds))
        self.entertainmentDistractedSeconds = min(900, max(15, entertainmentDistractedSeconds))
        self.focusRecoverySeconds = min(120, max(1, focusRecoverySeconds))
        self.idleAwaySeconds = min(3_600, max(self.inputIdleDistractedSeconds, max(180, idleAwaySeconds)))
    }

    public var stateEngineThresholds: StateEngineThresholds {
        StateEngineThresholds(
            uiStabilitySeconds: TimeInterval(focusRecoverySeconds),
            idleDistractedSeconds: TimeInterval(inputIdleDistractedSeconds),
            idleAwaySeconds: TimeInterval(idleAwaySeconds),
            distractedSeconds: TimeInterval(entertainmentDistractedSeconds)
        )
    }

    public mutating func normalize() {
        self = JudgmentSettings(
            inputIdleDistractedSeconds: inputIdleDistractedSeconds,
            entertainmentDistractedSeconds: entertainmentDistractedSeconds,
            focusRecoverySeconds: focusRecoverySeconds,
            idleAwaySeconds: idleAwaySeconds
        )
    }
}

public struct PetSettings: Codable, Hashable, Sendable {
    public static let defaultSelectedPackID = "xiaodai_local"

    public var opacity: Double
    public var size: Double
    public var animationEnabled: Bool
    public var audioEnabled: Bool
    public var hidden: Bool
    public var selectedPackID: String
    public var placement: PetPlacementMode
    public var customOriginX: Double?
    public var customOriginY: Double?
    public var hoverStatusEnabled: Bool
    public var idleSourceActionIDByPack: [String: String]
    public var intentSourceActionIDByPack: [String: [String: String]]

    public init(
        opacity: Double = 0.94,
        size: Double = 150,
        animationEnabled: Bool = true,
        audioEnabled: Bool = true,
        hidden: Bool = false,
        selectedPackID: String = Self.defaultSelectedPackID,
        placement: PetPlacementMode = .bottomRight,
        customOriginX: Double? = nil,
        customOriginY: Double? = nil,
        hoverStatusEnabled: Bool = true,
        idleSourceActionIDByPack: [String: String] = [:],
        intentSourceActionIDByPack: [String: [String: String]] = [:]
    ) {
        self.opacity = min(1, max(0.35, opacity))
        self.size = min(260, max(96, size))
        self.animationEnabled = animationEnabled
        self.audioEnabled = audioEnabled
        self.hidden = hidden
        self.selectedPackID = selectedPackID
        self.placement = placement
        self.customOriginX = customOriginX
        self.customOriginY = customOriginY
        self.hoverStatusEnabled = hoverStatusEnabled
        self.idleSourceActionIDByPack = idleSourceActionIDByPack
        self.intentSourceActionIDByPack = intentSourceActionIDByPack
        for (packID, sourceActionID) in idleSourceActionIDByPack
            where self.intentSourceActionIDByPack[packID]?[PetIntentKind.quietCompanion.rawValue] == nil {
            self.intentSourceActionIDByPack[packID, default: [:]][PetIntentKind.quietCompanion.rawValue] = sourceActionID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case opacity
        case size
        case animationEnabled
        case audioEnabled
        case hidden
        case selectedPackID
        case placement
        case customOriginX
        case customOriginY
        case hoverStatusEnabled
        case idleSourceActionIDByPack
        case intentSourceActionIDByPack
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.94,
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? 150,
            animationEnabled: try container.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? true,
            audioEnabled: try container.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? true,
            hidden: try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false,
            selectedPackID: try container.decodeIfPresent(String.self, forKey: .selectedPackID) ?? Self.defaultSelectedPackID,
            placement: try container.decodeIfPresent(PetPlacementMode.self, forKey: .placement) ?? .bottomRight,
            customOriginX: try container.decodeIfPresent(Double.self, forKey: .customOriginX),
            customOriginY: try container.decodeIfPresent(Double.self, forKey: .customOriginY),
            hoverStatusEnabled: try container.decodeIfPresent(Bool.self, forKey: .hoverStatusEnabled) ?? true,
            idleSourceActionIDByPack: try container.decodeIfPresent([String: String].self, forKey: .idleSourceActionIDByPack) ?? [:],
            intentSourceActionIDByPack: try container.decodeIfPresent([String: [String: String]].self, forKey: .intentSourceActionIDByPack) ?? [:]
        )
    }

    public func sourceActionID(for intent: PetIntentKind, packID: String) -> String? {
        intentSourceActionIDByPack[packID]?[intent.rawValue]
    }

    public mutating func setSourceActionID(_ sourceActionID: String?, for intent: PetIntentKind, packID: String) {
        if let sourceActionID {
            intentSourceActionIDByPack[packID, default: [:]][intent.rawValue] = sourceActionID
            if intent == .quietCompanion {
                idleSourceActionIDByPack[packID] = sourceActionID
            }
        } else {
            intentSourceActionIDByPack[packID]?[intent.rawValue] = nil
            if intentSourceActionIDByPack[packID]?.isEmpty == true {
                intentSourceActionIDByPack[packID] = nil
            }
            if intent == .quietCompanion {
                idleSourceActionIDByPack[packID] = nil
            }
        }
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var privacy: WindowTitlePrivacy
    public var reminder: ReminderSettings
    public var retention: DataRetentionSettings
    public var judgment: JudgmentSettings
    public var pet: PetSettings
    public var focusTargetMinutes: Int
    public var breakMinutes: Int
    public var autoStartBreak: Bool

    public init(
        hasCompletedOnboarding: Bool = false,
        privacy: WindowTitlePrivacy = .default,
        reminder: ReminderSettings = ReminderSettings(),
        retention: DataRetentionSettings = DataRetentionSettings(),
        judgment: JudgmentSettings = JudgmentSettings(),
        pet: PetSettings = PetSettings(),
        focusTargetMinutes: Int = 25,
        breakMinutes: Int = 5,
        autoStartBreak: Bool = true
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.privacy = privacy
        self.reminder = reminder
        self.retention = retention
        self.judgment = judgment
        self.pet = pet
        self.focusTargetMinutes = max(1, focusTargetMinutes)
        self.breakMinutes = max(1, breakMinutes)
        self.autoStartBreak = autoStartBreak
    }

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case privacy
        case reminder
        case retention
        case judgment
        case pet
        case focusTargetMinutes
        case breakMinutes
        case autoStartBreak
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hasCompletedOnboarding: try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false,
            privacy: try container.decodeIfPresent(WindowTitlePrivacy.self, forKey: .privacy) ?? .default,
            reminder: try container.decodeIfPresent(ReminderSettings.self, forKey: .reminder) ?? ReminderSettings(),
            retention: try container.decodeIfPresent(DataRetentionSettings.self, forKey: .retention) ?? DataRetentionSettings(),
            judgment: try container.decodeIfPresent(JudgmentSettings.self, forKey: .judgment) ?? JudgmentSettings(),
            pet: try container.decodeIfPresent(PetSettings.self, forKey: .pet) ?? PetSettings(),
            focusTargetMinutes: try container.decodeIfPresent(Int.self, forKey: .focusTargetMinutes) ?? 25,
            breakMinutes: try container.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 5,
            autoStartBreak: try container.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? true
        )
    }
}

public struct RetentionResult: Codable, Hashable, Sendable {
    public var removedStateSegments: Int
    public var removedAppUsageSegments: Int
    public var removedInputActivityBuckets: Int
    public var removedFocusSessions: Int
    public var removedBreakSessions: Int
    public var removedNudges: Int

    public var totalRemoved: Int {
        removedStateSegments
            + removedAppUsageSegments
            + removedInputActivityBuckets
            + removedFocusSessions
            + removedBreakSessions
            + removedNudges
    }

    public init(
        removedStateSegments: Int,
        removedAppUsageSegments: Int,
        removedInputActivityBuckets: Int = 0,
        removedFocusSessions: Int,
        removedBreakSessions: Int,
        removedNudges: Int
    ) {
        self.removedStateSegments = max(0, removedStateSegments)
        self.removedAppUsageSegments = max(0, removedAppUsageSegments)
        self.removedInputActivityBuckets = max(0, removedInputActivityBuckets)
        self.removedFocusSessions = max(0, removedFocusSessions)
        self.removedBreakSessions = max(0, removedBreakSessions)
        self.removedNudges = max(0, removedNudges)
    }
}

public struct DataRetentionManager: Sendable {
    public init() {}

    public func prune(
        now: Date,
        settings: DataRetentionSettings,
        stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        inputActivity: [InputActivityBucket] = [],
        focusSessions: [FocusSession],
        breakSessions: [BreakSession],
        nudges: [NudgeEvent]
    ) -> (
        stateSegments: [StateSegment],
        appUsage: [AppUsageSegment],
        inputActivity: [InputActivityBucket],
        focusSessions: [FocusSession],
        breakSessions: [BreakSession],
        nudges: [NudgeEvent],
        result: RetentionResult
    ) {
        let keptState = stateSegments.filter { $0.end >= cutoff(now: now, days: settings.stateRetentionDays) }
        let keptUsage = appUsage.filter { $0.end >= cutoff(now: now, days: settings.appUsageRetentionDays) }
        let keptInputActivity = inputActivity.filter { $0.end >= cutoff(now: now, days: settings.inputActivityRetentionDays) }
        let keptFocus = focusSessions.filter { ($0.end ?? $0.start) >= cutoff(now: now, days: settings.sessionRetentionDays) }
        let keptBreaks = breakSessions.filter { ($0.end ?? $0.start) >= cutoff(now: now, days: settings.sessionRetentionDays) }
        let keptNudges = nudges.filter { $0.time >= cutoff(now: now, days: settings.nudgeRetentionDays) }

        return (
            keptState,
            keptUsage,
            keptInputActivity,
            keptFocus,
            keptBreaks,
            keptNudges,
            RetentionResult(
                removedStateSegments: stateSegments.count - keptState.count,
                removedAppUsageSegments: appUsage.count - keptUsage.count,
                removedInputActivityBuckets: inputActivity.count - keptInputActivity.count,
                removedFocusSessions: focusSessions.count - keptFocus.count,
                removedBreakSessions: breakSessions.count - keptBreaks.count,
                removedNudges: nudges.count - keptNudges.count
            )
        )
    }

    private func cutoff(now: Date, days: Int) -> Date {
        now.addingTimeInterval(-Double(max(1, days)) * 86_400)
    }
}

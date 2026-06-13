import Foundation

public enum NudgeReason: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case distractedOverThreshold
    case distractedStrong
    case longFocusRest
    case veryLongFocusRest
    case breakEnding
    case welcomeBack
    case frequentSwitching

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .distractedOverThreshold: "走神过久"
        case .distractedStrong: "走神持续过久"
        case .longFocusRest: "长时间专注"
        case .veryLongFocusRest: "超长专注"
        case .breakEnding: "休息将结束"
        case .welcomeBack: "回到电脑"
        case .frequentSwitching: "频繁切换"
        }
    }
}

public struct NudgeEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var time: Date
    public var reason: NudgeReason
    public var state: FocusState
    public var appName: String
    public var category: ActivityCategory
    public var petIntent: PetIntentKind
    public var channel: String
    public var cooldownSeconds: TimeInterval
    public var message: String

    public init(
        id: String = UUID().uuidString,
        time: Date,
        reason: NudgeReason,
        state: FocusState,
        appName: String,
        category: ActivityCategory,
        petIntent: PetIntentKind,
        channel: String = "desktop",
        cooldownSeconds: TimeInterval,
        message: String
    ) {
        self.id = id
        self.time = time
        self.reason = reason
        self.state = state
        self.appName = appName
        self.category = category
        self.petIntent = petIntent
        self.channel = channel
        self.cooldownSeconds = cooldownSeconds
        self.message = message
    }

    public init(
        id: String = UUID().uuidString,
        time: Date,
        reason: NudgeReason,
        state: FocusState,
        appName: String,
        category: ActivityCategory,
        petAction: PetAction,
        channel: String = "desktop",
        cooldownSeconds: TimeInterval,
        message: String
    ) {
        self.init(
            id: id,
            time: time,
            reason: reason,
            state: state,
            appName: appName,
            category: category,
            petIntent: PetIntentKind(legacyAction: petAction),
            channel: channel,
            cooldownSeconds: cooldownSeconds,
            message: message
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case time
        case reason
        case state
        case appName
        case category
        case petIntent
        case petAction
        case channel
        case cooldownSeconds
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        time = try container.decode(Date.self, forKey: .time)
        reason = try container.decode(NudgeReason.self, forKey: .reason)
        state = try container.decode(FocusState.self, forKey: .state)
        appName = try container.decode(String.self, forKey: .appName)
        category = try container.decode(ActivityCategory.self, forKey: .category)
        if let decodedIntent = try container.decodeIfPresent(PetIntentKind.self, forKey: .petIntent) {
            petIntent = decodedIntent
        } else if let legacyAction = try container.decodeIfPresent(PetAction.self, forKey: .petAction) {
            petIntent = PetIntentKind(legacyAction: legacyAction)
        } else {
            petIntent = reason.defaultPetIntent
        }
        channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? "desktop"
        cooldownSeconds = try container.decode(TimeInterval.self, forKey: .cooldownSeconds)
        message = try container.decode(String.self, forKey: .message)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(time, forKey: .time)
        try container.encode(reason, forKey: .reason)
        try container.encode(state, forKey: .state)
        try container.encode(appName, forKey: .appName)
        try container.encode(category, forKey: .category)
        try container.encode(petIntent, forKey: .petIntent)
        try container.encode(channel, forKey: .channel)
        try container.encode(cooldownSeconds, forKey: .cooldownSeconds)
        try container.encode(message, forKey: .message)
    }

    public var petAction: PetAction {
        petIntent.legacyPetAction
    }
}

public struct NudgePolicyThresholds: Codable, Hashable, Sendable {
    public var lightDistractedSeconds: TimeInterval
    public var strongDistractedSeconds: TimeInterval
    public var longFocusSeconds: TimeInterval
    public var veryLongFocusSeconds: TimeInterval
    public var cooldownSeconds: TimeInterval

    public init(
        lightDistractedSeconds: TimeInterval = 8 * 60,
        strongDistractedSeconds: TimeInterval = 15 * 60,
        longFocusSeconds: TimeInterval = 25 * 60,
        veryLongFocusSeconds: TimeInterval = 60 * 60,
        cooldownSeconds: TimeInterval = 10 * 60
    ) {
        self.lightDistractedSeconds = lightDistractedSeconds
        self.strongDistractedSeconds = strongDistractedSeconds
        self.longFocusSeconds = longFocusSeconds
        self.veryLongFocusSeconds = veryLongFocusSeconds
        self.cooldownSeconds = cooldownSeconds
    }
}

public struct NudgePolicy: Sendable {
    public var thresholds: NudgePolicyThresholds

    public init(thresholds: NudgePolicyThresholds = NudgePolicyThresholds()) {
        self.thresholds = thresholds
    }

    public func nudge(
        for state: FocusStateSnapshot,
        previousState: FocusState?,
        now: Date,
        lastTriggeredAt: [NudgeReason: Date]
    ) -> NudgeEvent? {
        if previousState == .away, state.state != .away {
            return event(.welcomeBack, state: state, now: now, intent: .welcomeBack, message: "欢迎回来，要继续吗？", lastTriggeredAt: lastTriggeredAt)
        }

        switch state.state {
        case .focus:
            if state.stableDuration >= thresholds.veryLongFocusSeconds {
                return event(.veryLongFocusRest, state: state, now: now, intent: .focusRestHint, message: "已经专注很久了，要休息一下吗？", lastTriggeredAt: lastTriggeredAt)
            }
            if state.stableDuration >= thresholds.longFocusSeconds {
                return event(.longFocusRest, state: state, now: now, intent: .focusRestHint, message: "已经专注一阵子了，要休息一下吗？", lastTriggeredAt: lastTriggeredAt)
            }
        case .distracted:
            if state.stableDuration >= thresholds.strongDistractedSeconds {
                return event(.distractedStrong, state: state, now: now, intent: .nudgeStrong, message: "已经偏离一会儿啦，要回来吗？", lastTriggeredAt: lastTriggeredAt)
            }
            if state.stableDuration >= thresholds.lightDistractedSeconds {
                return event(.distractedOverThreshold, state: state, now: now, intent: .nudgeGentle, message: "要不要回到刚才的任务？", lastTriggeredAt: lastTriggeredAt)
            }
        case .breakTime, .away:
            return nil
        }

        return nil
    }

    private func event(
        _ reason: NudgeReason,
        state: FocusStateSnapshot,
        now: Date,
        intent: PetIntentKind,
        message: String,
        lastTriggeredAt: [NudgeReason: Date]
    ) -> NudgeEvent? {
        if let last = lastTriggeredAt[reason],
           now.timeIntervalSince(last) < thresholds.cooldownSeconds {
            return nil
        }

        return NudgeEvent(
            time: now,
            reason: reason,
            state: state.state,
            appName: state.appName,
            category: state.category,
            petIntent: intent,
            cooldownSeconds: thresholds.cooldownSeconds,
            message: message
        )
    }
}

public extension NudgeReason {
    var defaultPetIntent: PetIntentKind {
        switch self {
        case .distractedOverThreshold:
            .nudgeGentle
        case .distractedStrong, .frequentSwitching:
            .nudgeStrong
        case .longFocusRest, .veryLongFocusRest:
            .focusRestHint
        case .breakEnding:
            .breakEnding
        case .welcomeBack:
            .welcomeBack
        }
    }
}

public extension PetIntentKind {
    init(legacyAction: PetAction) {
        switch legacyAction {
        case .idle, .blink, .breath, .focusStart, .focusStable, .wake:
            self = .quietCompanion
        case .sleep:
            self = .sleep
        case .stretch:
            self = .focusRestHint
        case .distractedLook:
            self = .distractedObserve
        case .nudgeGentle:
            self = .nudgeGentle
        case .nudgeStrong:
            self = .nudgeStrong
        case .breakRelax:
            self = .breakCompanion
        case .breakEnd:
            self = .breakEnding
        case .welcomeBack:
            self = .welcomeBack
        case .dragged:
            self = .dragged
        case .landing:
            self = .landing
        case .run, .screenTransfer:
            self = .moveRight
        case .mouseSummon:
            self = .mouseSummon
        }
    }

    var legacyPetAction: PetAction {
        switch self {
        case .quietCompanion:
            .idle
        case .focusRestHint:
            .stretch
        case .distractedObserve:
            .distractedLook
        case .nudgeGentle:
            .nudgeGentle
        case .nudgeStrong:
            .nudgeStrong
        case .breakCompanion:
            .breakRelax
        case .breakEnding:
            .breakEnd
        case .sleep:
            .sleep
        case .welcomeBack:
            .welcomeBack
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            .run
        case .dragged:
            .dragged
        case .landing:
            .landing
        case .mouseSummon:
            .mouseSummon
        case .dashboardGuide:
            .welcomeBack
        }
    }
}

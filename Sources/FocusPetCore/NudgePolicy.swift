import Foundation

public enum NudgeReason: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case distractedOverThreshold
    case distractedStrong
    case longFocusRest
    case veryLongFocusRest
    case focusSessionCompleted
    case breakEnding
    case welcomeBack
    case frequentSwitching

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .distractedOverThreshold: "注意力提醒"
        case .distractedStrong: "需要收束一下"
        case .longFocusRest: "建议休息"
        case .veryLongFocusRest: "该休息了"
        case .focusSessionCompleted: "专注完成"
        case .breakEnding: "休息结束"
        case .welcomeBack: "回到电脑"
        case .frequentSwitching: "切换过多"
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
    public var welcomeBackAwaySeconds: TimeInterval
    public var cooldownSeconds: TimeInterval

    public init(
        lightDistractedSeconds: TimeInterval = 5 * 60,
        strongDistractedSeconds: TimeInterval = 12 * 60,
        longFocusSeconds: TimeInterval = 45 * 60,
        veryLongFocusSeconds: TimeInterval = 90 * 60,
        welcomeBackAwaySeconds: TimeInterval = 30 * 60,
        cooldownSeconds: TimeInterval = 10 * 60
    ) {
        self.lightDistractedSeconds = lightDistractedSeconds
        self.strongDistractedSeconds = strongDistractedSeconds
        self.longFocusSeconds = longFocusSeconds
        self.veryLongFocusSeconds = veryLongFocusSeconds
        self.welcomeBackAwaySeconds = welcomeBackAwaySeconds
        self.cooldownSeconds = cooldownSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case lightDistractedSeconds
        case strongDistractedSeconds
        case longFocusSeconds
        case veryLongFocusSeconds
        case welcomeBackAwaySeconds
        case cooldownSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lightDistractedSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .lightDistractedSeconds) ?? 5 * 60,
            strongDistractedSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .strongDistractedSeconds) ?? 12 * 60,
            longFocusSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .longFocusSeconds) ?? 45 * 60,
            veryLongFocusSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .veryLongFocusSeconds) ?? 90 * 60,
            welcomeBackAwaySeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .welcomeBackAwaySeconds) ?? 30 * 60,
            cooldownSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .cooldownSeconds) ?? 10 * 60
        )
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
        previousStateDuration: TimeInterval? = nil,
        now: Date,
        lastTriggeredAt: [NudgeReason: Date]
    ) -> NudgeEvent? {
        if previousState == .away,
           state.state == .focus,
           (previousStateDuration ?? 0) >= thresholds.welcomeBackAwaySeconds {
            return event(.welcomeBack, state: state, now: now, intent: .welcomeBack, message: "欢迎回来，先接上刚才的节奏。", lastTriggeredAt: lastTriggeredAt)
        }

        switch state.state {
        case .focus:
            if state.stableDuration >= thresholds.veryLongFocusSeconds {
                return event(.veryLongFocusRest, state: state, now: now, intent: .focusRestHint, message: "已经连续专注很久了，先离屏活动几分钟。", lastTriggeredAt: lastTriggeredAt)
            }
            if state.stableDuration >= thresholds.longFocusSeconds {
                return event(.longFocusRest, state: state, now: now, intent: .focusRestHint, message: "这段专注已经够长了，可以安排一次短休息。", lastTriggeredAt: lastTriggeredAt)
            }
        case .distracted:
            if state.stableDuration >= thresholds.strongDistractedSeconds {
                return event(.distractedStrong, state: state, now: now, intent: .nudgeStrong, message: "这段已经偏离比较久了，建议暂停一下或回到任务。", lastTriggeredAt: lastTriggeredAt)
            }
            if state.stableDuration >= thresholds.lightDistractedSeconds {
                return event(.distractedOverThreshold, state: state, now: now, intent: .nudgeGentle, message: "先回到当前任务两分钟，节奏会更容易接上。", lastTriggeredAt: lastTriggeredAt)
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
        let cooldownSeconds = cooldownSeconds(for: reason)
        for cooldownReason in cooldownReasons(for: reason) {
            if let last = lastTriggeredAt[cooldownReason],
               now.timeIntervalSince(last) < cooldownSeconds {
                return nil
            }
        }

        return NudgeEvent(
            time: now,
            reason: reason,
            state: state.state,
            appName: state.appName,
            category: state.category,
            petIntent: intent,
            cooldownSeconds: cooldownSeconds,
            message: message
        )
    }

    private func cooldownSeconds(for reason: NudgeReason) -> TimeInterval {
        switch reason {
        case .longFocusRest, .veryLongFocusRest:
            return max(thresholds.cooldownSeconds, 30 * 60)
        case .welcomeBack:
            return max(thresholds.cooldownSeconds, 2 * 60 * 60)
        case .distractedOverThreshold, .distractedStrong, .frequentSwitching, .focusSessionCompleted, .breakEnding:
            return thresholds.cooldownSeconds
        }
    }

    private func cooldownReasons(for reason: NudgeReason) -> [NudgeReason] {
        switch reason {
        case .distractedOverThreshold, .distractedStrong, .frequentSwitching:
            return [.distractedOverThreshold, .distractedStrong, .frequentSwitching]
        case .longFocusRest, .veryLongFocusRest:
            return [.longFocusRest, .veryLongFocusRest]
        case .focusSessionCompleted:
            return [.focusSessionCompleted]
        case .breakEnding:
            return [.breakEnding]
        case .welcomeBack:
            return [.welcomeBack]
        }
    }
}

public extension NudgeReason {
    var defaultPetIntent: PetIntentKind {
        switch self {
        case .distractedOverThreshold:
            .nudgeGentle
        case .distractedStrong, .frequentSwitching:
            .nudgeStrong
        case .longFocusRest, .veryLongFocusRest, .focusSessionCompleted:
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

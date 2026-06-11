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
    public var petAction: PetAction
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
        petAction: PetAction,
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
        self.petAction = petAction
        self.channel = channel
        self.cooldownSeconds = cooldownSeconds
        self.message = message
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
            return event(.welcomeBack, state: state, now: now, action: .welcomeBack, message: "欢迎回来，要继续吗？", lastTriggeredAt: lastTriggeredAt)
        }

        switch state.state {
        case .focus:
            if state.stableDuration >= thresholds.veryLongFocusSeconds {
                return event(.veryLongFocusRest, state: state, now: now, action: .stretch, message: "已经专注很久了，要休息一下吗？", lastTriggeredAt: lastTriggeredAt)
            }
            if state.stableDuration >= thresholds.longFocusSeconds {
                return event(.longFocusRest, state: state, now: now, action: .stretch, message: "已经专注一阵子了，要休息一下吗？", lastTriggeredAt: lastTriggeredAt)
            }
        case .distracted:
            if state.stableDuration >= thresholds.strongDistractedSeconds {
                return event(.distractedStrong, state: state, now: now, action: .nudgeStrong, message: "已经偏离一会儿啦，要回来吗？", lastTriggeredAt: lastTriggeredAt)
            }
            if state.stableDuration >= thresholds.lightDistractedSeconds {
                return event(.distractedOverThreshold, state: state, now: now, action: .nudgeGentle, message: "要不要回到刚才的任务？", lastTriggeredAt: lastTriggeredAt)
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
        action: PetAction,
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
            petAction: action,
            cooldownSeconds: thresholds.cooldownSeconds,
            message: message
        )
    }
}

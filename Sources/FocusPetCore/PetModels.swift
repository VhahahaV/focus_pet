import Foundation

public enum PetPlacementMode: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case dockAttached
    case bottomRightCorner
    case bottomLeftCorner
    case manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dockAttached: "Dock 上方"
        case .bottomRightCorner: "右下角"
        case .bottomLeftCorner: "左下角"
        case .manual: "手动"
        }
    }
}

public enum PetBehaviorState: String, Codable, Hashable, Sendable, CaseIterable {
    case idle
    case sleeping
    case walking
    case stretching
    case observing
    case nudgeDistracted
    case nudgeEntertainment
    case welcomeBack
    case dragged
    case landing
    case hidden

    public var title: String {
        switch self {
        case .idle: "待机"
        case .sleeping: "睡觉"
        case .walking: "散步"
        case .stretching: "伸懒腰"
        case .observing: "观察"
        case .nudgeDistracted: "轻提醒"
        case .nudgeEntertainment: "娱乐提醒"
        case .welcomeBack: "欢迎回来"
        case .dragged: "抱起"
        case .landing: "落地"
        case .hidden: "隐藏"
        }
    }
}

public enum PetAction: String, Codable, Hashable, Sendable, CaseIterable {
    case sleep
    case idle
    case blink
    case stretch
    case shortWalk
    case nudgeDistracted
    case nudgeEntertainment
    case welcomeBack
    case dragged
    case landing
    case hidden
}

public enum PetBubbleKind: String, Codable, Hashable, Sendable {
    case light
    case distracted
    case entertainment
    case welcomeBack
}

public struct PetBubble: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: PetBubbleKind
    public var message: String
    public var primaryActionTitle: String?
    public var secondaryActionTitle: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: PetBubbleKind,
        message: String,
        primaryActionTitle: String? = nil,
        secondaryActionTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.createdAt = createdAt
    }
}

public struct PetBehaviorController: Sendable {
    public init() {}

    public func behavior(
        for state: FusedUserState,
        previousState: FusedUserState?,
        latestReminder: ReminderDecision?
    ) -> PetBehaviorState {
        if previousState?.userState == .away, state.userState != .away {
            return .welcomeBack
        }

        if isEntertainmentNudge(state: state, latestReminder: latestReminder) {
            return .nudgeEntertainment
        }

        switch state.userState {
        case .focused:
            return .sleeping
        case .distracted:
            return .nudgeDistracted
        case .away:
            return .sleeping
        }
    }

    private func isEntertainmentNudge(state: FusedUserState, latestReminder: ReminderDecision?) -> Bool {
        if latestReminder?.ruleID == FocusRule.entertainmentDistraction.id {
            return true
        }

        return state.userState == .distracted && state.context == .entertainment
    }
}

public struct PetActionScheduler: Sendable {
    private var lastIdleActionAt = Date.distantPast
    private var lastNudgeAt: [PetBehaviorState: Date] = [:]
    private var idleActionIndex = 0
    private let idleActionInterval: TimeInterval
    private let nudgeCooldown: TimeInterval

    public init(idleActionInterval: TimeInterval = 18, nudgeCooldown: TimeInterval = 300) {
        self.idleActionInterval = idleActionInterval
        self.nudgeCooldown = nudgeCooldown
    }

    public mutating func nextAction(behavior: PetBehaviorState, now: Date = Date()) -> PetAction {
        switch behavior {
        case .idle:
            return .idle
        case .sleeping:
            return quietAction(now: now)
        case .walking:
            return .shortWalk
        case .stretching:
            return .stretch
        case .observing:
            return .blink
        case .nudgeDistracted:
            return canNudge(.nudgeDistracted, now: now) ? .nudgeDistracted : .idle
        case .nudgeEntertainment:
            return canNudge(.nudgeEntertainment, now: now) ? .nudgeEntertainment : .idle
        case .welcomeBack:
            return .welcomeBack
        case .dragged:
            return .dragged
        case .landing:
            return .landing
        case .hidden:
            return .hidden
        }
    }

    private mutating func quietAction(now: Date) -> PetAction {
        if lastIdleActionAt == .distantPast {
            lastIdleActionAt = now
            return .sleep
        }

        guard now.timeIntervalSince(lastIdleActionAt) >= idleActionInterval else {
            return .sleep
        }

        lastIdleActionAt = now
        let actions: [PetAction] = [.blink, .stretch, .shortWalk]
        defer { idleActionIndex = (idleActionIndex + 1) % actions.count }
        return actions[idleActionIndex]
    }

    private mutating func canNudge(_ state: PetBehaviorState, now: Date) -> Bool {
        let last = lastNudgeAt[state] ?? .distantPast
        guard now.timeIntervalSince(last) >= nudgeCooldown else {
            return false
        }

        lastNudgeAt[state] = now
        return true
    }
}

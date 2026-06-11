import Foundation

public enum PetAction: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case idle
    case blink
    case breath
    case sleep
    case wake
    case focusStart
    case focusStable
    case stretch
    case distractedLook
    case nudgeGentle
    case nudgeStrong
    case breakRelax
    case breakEnd
    case welcomeBack
    case dragged
    case landing
    case run
    case screenTransfer
    case mouseSummon

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .idle: "待机"
        case .blink: "眨眼"
        case .breath: "呼吸"
        case .sleep: "睡觉"
        case .wake: "醒来"
        case .focusStart: "进入专注"
        case .focusStable: "稳定专注"
        case .stretch: "伸懒腰"
        case .distractedLook: "走神提醒"
        case .nudgeGentle: "轻提醒"
        case .nudgeStrong: "强提醒"
        case .breakRelax: "休息"
        case .breakEnd: "休息结束"
        case .welcomeBack: "欢迎回来"
        case .dragged: "拖拽"
        case .landing: "落地"
        case .run: "移动"
        case .screenTransfer: "切屏"
        case .mouseSummon: "召回"
        }
    }
}

public struct PetBehaviorPolicy: Sendable {
    public var nudgeActionVisibleSeconds: TimeInterval

    public init(nudgeActionVisibleSeconds: TimeInterval = 22) {
        self.nudgeActionVisibleSeconds = max(1, nudgeActionVisibleSeconds)
    }

    public func action(
        for state: FocusState,
        previousState: FocusState?,
        latestNudge: NudgeEvent?,
        now: Date = Date()
    ) -> PetAction {
        if previousState == .away, state != .away {
            return .welcomeBack
        }

        if let latestNudge,
           now.timeIntervalSince(latestNudge.time) <= nudgeActionVisibleSeconds {
            return latestNudge.petAction
        }

        switch state {
        case .focus:
            return previousState == .focus ? focusAmbientAction(now: now) : .focusStart
        case .distracted:
            return .distractedLook
        case .breakTime:
            return .breakRelax
        case .away:
            return .sleep
        }
    }

    private func focusAmbientAction(now: Date) -> PetAction {
        let slot = Int(now.timeIntervalSince1970 / 10) % 12
        switch slot {
        case 0, 6:
            return .blink
        case 9:
            return .stretch
        default:
            return .breath
        }
    }
}

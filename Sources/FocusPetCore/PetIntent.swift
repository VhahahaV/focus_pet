import Foundation

public enum PetIntentSource: String, Codable, Hashable, Sendable, CaseIterable {
    case state
    case nudge
    case interaction
    case physicalInteraction

    public var priority: Int {
        switch self {
        case .physicalInteraction: 500
        case .nudge: 400
        case .interaction: 300
        case .state: 100
        }
    }
}

public enum PetIntentKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case quietCompanion
    case focusRestHint
    case distractedObserve
    case nudgeGentle
    case nudgeStrong
    case breakCompanion
    case breakEnding
    case sleep
    case welcomeBack
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case dragged
    case landing
    case mouseSummon
    case dashboardGuide

    public var id: String { rawValue }

    public static let userMappingCases: [PetIntentKind] = [
        .quietCompanion,
        .focusRestHint,
        .distractedObserve,
        .nudgeGentle,
        .nudgeStrong,
        .breakCompanion,
        .breakEnding,
        .sleep
    ]

    public static let advancedMappingCases: [PetIntentKind] = [
        .welcomeBack,
        .mouseSummon,
        .dragged,
        .landing,
        .moveLeft,
        .moveRight,
        .moveUp,
        .moveDown
    ]

    public var title: String {
        switch self {
        case .quietCompanion: "安静陪伴"
        case .focusRestHint: "专注休息提示"
        case .distractedObserve: "走神观察"
        case .nudgeGentle: "温和提醒"
        case .nudgeStrong: "强提醒"
        case .breakCompanion: "休息陪伴"
        case .breakEnding: "休息结束"
        case .sleep: "暂离睡觉"
        case .welcomeBack: "欢迎回来"
        case .moveLeft: "向左移动"
        case .moveRight: "向右移动"
        case .moveUp: "向上移动"
        case .moveDown: "向下移动"
        case .dragged: "拖拽中"
        case .landing: "落地"
        case .mouseSummon: "鼠标召回"
        case .dashboardGuide: "面板引导"
        }
    }

    public var symbolName: String {
        switch self {
        case .quietCompanion: "leaf.fill"
        case .focusRestHint: "figure.cooldown"
        case .distractedObserve: "eye.trianglebadge.exclamationmark"
        case .nudgeGentle: "hand.tap.fill"
        case .nudgeStrong: "bell.badge.fill"
        case .breakCompanion: "cup.and.saucer.fill"
        case .breakEnding: "alarm.fill"
        case .sleep: "moon.zzz.fill"
        case .welcomeBack: "hand.wave.fill"
        case .moveLeft: "arrow.left"
        case .moveRight: "arrow.right"
        case .moveUp: "arrow.up"
        case .moveDown: "arrow.down"
        case .dragged: "hand.draw.fill"
        case .landing: "arrow.down.to.line"
        case .mouseSummon: "cursorarrow.motionlines"
        case .dashboardGuide: "rectangle.3.group.fill"
        }
    }

    public var preferredSourceActionIDs: [String] {
        switch self {
        case .quietCompanion:
            ["default", "idle", "work", "focus", "normal", "onfloor", "stand", "breath"]
        case .focusRestHint:
            ["stretch", "grooming", "blink", "idle", "default"]
        case .distractedObserve:
            ["distractedLook", "disturbed", "distracted", "nudgeGentle", "default", "idle"]
        case .nudgeGentle:
            ["nudgeGentle", "distractedLook", "patpat", "patpat1", "disturbed", "default"]
        case .nudgeStrong:
            ["nudgeStrong", "disturbed", "shake", "nudgeGentle", "distractedLook", "default"]
        case .breakCompanion:
            ["breakRelax", "break", "relax", "onfloor", "sleep", "default", "idle"]
        case .breakEnding:
            ["breakEnd", "mouseSummon", "cursorPounce", "welcomeBack", "wake", "default"]
        case .sleep:
            ["sleep", "sleeping", "nap", "onfloor", "default"]
        case .welcomeBack:
            ["welcomeBack", "wake", "mouseSummon", "default", "idle"]
        case .moveLeft:
            ["left_walk", "leftwalk", "left", "run", "right_walk", "right"]
        case .moveRight:
            ["right_walk", "rightwalk", "right", "run", "left_walk", "left"]
        case .moveUp:
            ["up", "climb", "screenTransfer", "run", "right_walk", "left_walk"]
        case .moveDown:
            ["down", "fall", "climb", "screenTransfer", "run", "onfloor"]
        case .dragged:
            ["drag", "dragged", "idle", "default"]
        case .landing:
            ["landing", "fall", "onfloor", "default", "idle"]
        case .mouseSummon:
            ["mouseSummon", "cursorPounce", "welcomeBack", "run", "default"]
        case .dashboardGuide:
            ["welcomeBack", "stretch", "default", "idle"]
        }
    }
}

public struct PetIntent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: PetIntentKind
    public var source: PetIntentSource
    public var priority: Int
    public var startedAt: Date
    public var expiresAt: Date?
    public var message: String?
    public var interruptible: Bool

    public init(
        id: String = UUID().uuidString,
        kind: PetIntentKind,
        source: PetIntentSource,
        priority: Int? = nil,
        startedAt: Date = Date(),
        expiresAt: Date? = nil,
        message: String? = nil,
        interruptible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.priority = priority ?? source.priority
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.message = message
        self.interruptible = interruptible
    }
}

import Foundation

public enum PetPackDefaults {
    public static let focusDinoID = "focus_dino"
    public static let luoXiaoHeiLocalID = "luo_xiaohei_local"
}

public enum PetPackSource: String, Codable, Hashable, Sendable {
    case bundled
    case userImported
    case localOnlyTest
}

public enum PetPackDistribution: String, Codable, Hashable, Sendable {
    case redistributable
    case localOnly
    case unknown
}

public enum PetPackAnchor: String, Codable, Hashable, Sendable {
    case dockAttached
    case bottomRightCorner
    case bottomLeftCorner
    case manual
}

public enum PetRenderer: String, Codable, Hashable, Sendable {
    case pngSequence
}

public enum PetAnimationKey: String, Codable, Hashable, Sendable, CaseIterable {
    case sleeping
    case idle
    case blink
    case stretch
    case walkLeft
    case walkRight
    case nudgeDistracted
    case nudgeEntertainment
    case welcomeBack
    case dragged
    case landing
    case shakeHead
    case idleSpecial
    case playfulIdle

    public init?(manifestKey: String) {
        if let key = Self(rawValue: manifestKey) {
            self = key
            return
        }

        switch manifestKey {
        case "sleep":
            self = .sleeping
        case "walk_left":
            self = .walkLeft
        case "walk_right":
            self = .walkRight
        case "nudge_distracted":
            self = .nudgeDistracted
        case "nudge_entertainment":
            self = .nudgeEntertainment
        case "welcome_back":
            self = .welcomeBack
        case "idle_special":
            self = .idleSpecial
        case "playful_idle":
            self = .playfulIdle
        default:
            return nil
        }
    }
}

public struct PetPackSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct PetHitBox: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PetPackLicense: Codable, Hashable, Sendable {
    public var type: String
    public var note: String?

    public init(type: String, note: String? = nil) {
        self.type = type
        self.note = note
    }
}

public struct PetAnimationSpec: Codable, Hashable, Sendable {
    public var folder: String
    public var fps: Int
    public var loop: Bool
    public var frameCount: Int?
    public var renderer: PetRenderer

    public init(
        folder: String,
        fps: Int,
        loop: Bool,
        frameCount: Int?,
        renderer: PetRenderer = .pngSequence
    ) {
        self.folder = folder
        self.fps = fps
        self.loop = loop
        self.frameCount = frameCount
        self.renderer = renderer
    }

    private enum CodingKeys: String, CodingKey {
        case folder
        case fps
        case loop
        case frameCount
        case renderer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decode(String.self, forKey: .folder)
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 8
        loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? true
        frameCount = try container.decodeIfPresent(Int.self, forKey: .frameCount)
        renderer = try container.decodeIfPresent(PetRenderer.self, forKey: .renderer) ?? .pngSequence
    }
}

public struct PetPack: Codable, Hashable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var source: PetPackSource
    public var distribution: PetPackDistribution
    public var style: String?
    public var license: PetPackLicense?
    public var defaultSize: PetPackSize
    public var defaultScale: Double
    public var anchor: PetPackAnchor
    public var hitBox: PetHitBox?
    public var animations: [PetAnimationKey: PetAnimationSpec]
    public var actionAliases: [PetAnimationKey: PetAnimationKey]

    public init(
        schemaVersion: Int,
        id: String,
        name: String,
        source: PetPackSource,
        distribution: PetPackDistribution,
        style: String?,
        license: PetPackLicense?,
        defaultSize: PetPackSize,
        defaultScale: Double,
        anchor: PetPackAnchor,
        hitBox: PetHitBox?,
        animations: [PetAnimationKey: PetAnimationSpec],
        actionAliases: [PetAnimationKey: PetAnimationKey]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.source = source
        self.distribution = distribution
        self.style = style
        self.license = license
        self.defaultSize = defaultSize
        self.defaultScale = defaultScale
        self.anchor = anchor
        self.hitBox = hitBox
        self.animations = animations
        self.actionAliases = actionAliases
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case source
        case distribution
        case style
        case license
        case defaultSize
        case defaultScale
        case anchor
        case hitBox
        case animations
        case actionAliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decodeIfPresent(PetPackSource.self, forKey: .source) ?? .bundled
        distribution = try container.decodeIfPresent(PetPackDistribution.self, forKey: .distribution) ?? .unknown
        style = try container.decodeIfPresent(String.self, forKey: .style)
        license = try container.decodeIfPresent(PetPackLicense.self, forKey: .license)
        defaultSize = try container.decodeIfPresent(PetPackSize.self, forKey: .defaultSize)
            ?? PetPackSize(width: 128, height: 128)
        defaultScale = try container.decodeIfPresent(Double.self, forKey: .defaultScale) ?? 1
        anchor = try container.decodeIfPresent(PetPackAnchor.self, forKey: .anchor) ?? .dockAttached
        hitBox = try container.decodeIfPresent(PetHitBox.self, forKey: .hitBox)

        let rawAnimations = try container.decodeIfPresent([String: PetAnimationSpec].self, forKey: .animations) ?? [:]
        animations = Dictionary(uniqueKeysWithValues: rawAnimations.compactMap { rawKey, spec in
            guard let key = PetAnimationKey(manifestKey: rawKey) else { return nil }
            return (key, spec)
        })

        let rawAliases = try container.decodeIfPresent([String: String].self, forKey: .actionAliases) ?? [:]
        actionAliases = Dictionary(uniqueKeysWithValues: rawAliases.compactMap { rawKey, rawValue in
            guard let key = PetAnimationKey(manifestKey: rawKey),
                  let value = PetAnimationKey(manifestKey: rawValue) else {
                return nil
            }
            return (key, value)
        })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(source, forKey: .source)
        try container.encode(distribution, forKey: .distribution)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(license, forKey: .license)
        try container.encode(defaultSize, forKey: .defaultSize)
        try container.encode(defaultScale, forKey: .defaultScale)
        try container.encode(anchor, forKey: .anchor)
        try container.encodeIfPresent(hitBox, forKey: .hitBox)
        try container.encode(
            Dictionary(uniqueKeysWithValues: animations.map { ($0.key.rawValue, $0.value) }),
            forKey: .animations
        )
        try container.encode(
            Dictionary(uniqueKeysWithValues: actionAliases.map { ($0.key.rawValue, $0.value.rawValue) }),
            forKey: .actionAliases
        )
    }

    public func animationKey(for action: PetAction) -> PetAnimationKey? {
        let target = PetAnimationKey(action)
        if animations[target] != nil {
            return target
        }
        if let alias = actionAliases[target], animations[alias] != nil {
            return alias
        }
        if animations[.idle] != nil {
            return .idle
        }
        if animations[.sleeping] != nil {
            return .sleeping
        }
        return animations.keys.sorted { $0.rawValue < $1.rawValue }.first
    }
}

public extension PetAnimationKey {
    init(_ action: PetAction) {
        switch action {
        case .sleep:
            self = .sleeping
        case .idle:
            self = .idle
        case .blink:
            self = .blink
        case .stretch:
            self = .stretch
        case .shortWalk:
            self = .walkRight
        case .nudgeDistracted:
            self = .nudgeDistracted
        case .nudgeEntertainment:
            self = .nudgeEntertainment
        case .welcomeBack:
            self = .welcomeBack
        case .dragged:
            self = .dragged
        case .landing:
            self = .landing
        case .hidden:
            self = .idle
        }
    }
}

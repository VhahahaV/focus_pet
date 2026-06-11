import FocusPetCore
import Foundation

public struct PetPackSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = max(1, width)
        self.height = max(1, height)
    }
}

public struct PetPackAnchor: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PetAnimationSpec: Codable, Hashable, Sendable {
    public var folder: String
    public var fps: Double
    public var loop: Bool
    public var frameCount: Int?

    public init(folder: String, fps: Double, loop: Bool, frameCount: Int?) {
        self.folder = folder
        self.fps = max(1, fps)
        self.loop = loop
        self.frameCount = frameCount.map { max(0, $0) }
    }

    private enum CodingKeys: String, CodingKey {
        case folder
        case fps
        case loop
        case frameCount
    }
}

public struct PetPack: Identifiable, Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var author: String
    public var style: String
    public var license: String
    public var distribution: String
    public var defaultSize: PetPackSize
    public var anchor: PetPackAnchor
    public var animations: [PetAction: PetAnimationSpec]

    public init(
        schemaVersion: Int,
        id: String,
        name: String,
        author: String,
        style: String,
        license: String,
        distribution: String,
        defaultSize: PetPackSize,
        anchor: PetPackAnchor,
        animations: [PetAction: PetAnimationSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.author = author
        self.style = style
        self.license = license
        self.distribution = distribution
        self.defaultSize = defaultSize
        self.anchor = anchor
        self.animations = animations
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case author
        case style
        case license
        case distribution
        case defaultSize
        case anchor
        case animations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "Focus Pet"
        style = try container.decodeIfPresent(String.self, forKey: .style) ?? "minimal_2d"
        if let decodedLicense = try? container.decodeIfPresent(String.self, forKey: .license) {
            license = decodedLicense
        } else if let legacyLicense = try? container.decodeIfPresent(LegacyLicense.self, forKey: .license) {
            license = [legacyLicense.type, legacyLicense.note]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
                .joined(separator: " · ")
        } else {
            license = ""
        }
        distribution = try container.decodeIfPresent(String.self, forKey: .distribution) ?? ""
        defaultSize = try container.decode(PetPackSize.self, forKey: .defaultSize)
        anchor = (try? container.decode(PetPackAnchor.self, forKey: .anchor))
            ?? PetPackAnchor(x: 0.5, y: 1.0)

        let keyedAnimations = try container.decode([String: PetAnimationSpec].self, forKey: .animations)
        animations = keyedAnimations.reduce(into: [:]) { result, item in
            let (key, value) = item
            guard let action = PetAction(rawValue: key) ?? Self.legacyAction(for: key),
                  result[action] == nil else {
                return
            }
            result[action] = value
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(style, forKey: .style)
        try container.encode(license, forKey: .license)
        try container.encode(distribution, forKey: .distribution)
        try container.encode(defaultSize, forKey: .defaultSize)
        try container.encode(anchor, forKey: .anchor)
        let keyedAnimations = Dictionary(uniqueKeysWithValues: animations.map { ($0.key.rawValue, $0.value) })
        try container.encode(keyedAnimations, forKey: .animations)
    }

    private static func legacyAction(for key: String) -> PetAction? {
        switch key {
        case "sleeping":
            return .sleep
        case "nudgeDistracted":
            return .nudgeGentle
        case "nudgeEntertainment":
            return .nudgeStrong
        case "welcomeBack":
            return .welcomeBack
        case "idleSpecial", "playfulIdle":
            return .breakRelax
        default:
            return nil
        }
    }
}

public struct PetActionResolver: Sendable {
    public init() {}

    public func animationKey(for action: PetAction, in pack: PetPack) -> PetAction? {
        if pack.animations[action] != nil {
            return action
        }

        for fallback in fallbacks(for: action) where pack.animations[fallback] != nil {
            return fallback
        }

        return pack.animations.keys.sorted { $0.rawValue < $1.rawValue }.first
    }

    public func fallbacks(for action: PetAction) -> [PetAction] {
        switch action {
        case .blink:
            return [.idle]
        case .wake:
            return [.welcomeBack, .idle]
        case .focusStart, .focusStable, .stretch, .dragged, .landing:
            return [.idle]
        case .distractedLook:
            return [.idle]
        case .nudgeStrong:
            return [.nudgeGentle, .distractedLook, .idle]
        case .breakEnd:
            return [.idle]
        case .breath:
            return [.idle]
        case .idle, .sleep, .nudgeGentle, .breakRelax, .welcomeBack:
            return [.idle, .sleep]
        }
    }
}

public struct PetPackRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { pack.id }
    public var pack: PetPack
    public var rootURL: URL?
    public var isBundled: Bool
    public var validation: PetPackValidationResult

    public init(pack: PetPack, rootURL: URL?, isBundled: Bool, validation: PetPackValidationResult? = nil) {
        self.pack = pack
        self.rootURL = rootURL
        self.isBundled = isBundled
        self.validation = validation ?? PetPackValidator().validate(pack, rootURL: rootURL)
    }

    public var previewURL: URL? {
        guard let rootURL else { return nil }
        let url = rootURL.appendingPathComponent("preview.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public var originTitle: String {
        isBundled ? "内置" : "本地"
    }

    public func frameURLs(for action: PetAction) -> [URL] {
        guard let rootURL,
              let animationKey = PetActionResolver().animationKey(for: action, in: pack),
              let spec = pack.animations[animationKey] else {
            return []
        }

        let folderURL = rootURL.appendingPathComponent(spec.folder, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func coverage(for actions: [PetAction] = PetAction.allCases) -> [PetActionCoverage] {
        let resolver = PetActionResolver()
        return actions.map { action in
            let resolved = resolver.animationKey(for: action, in: pack)
            let frameCount = resolved.map { frameURLs(for: $0).count } ?? 0
            let status: PetActionCoverageStatus
            if resolved == action {
                status = .native
            } else if resolved != nil {
                status = .fallback
            } else {
                status = .missing
            }

            return PetActionCoverage(
                action: action,
                resolvedAction: resolved,
                status: status,
                frameCount: frameCount
            )
        }
    }
}

public enum PetActionCoverageStatus: String, Codable, Hashable, Sendable {
    case native
    case fallback
    case missing

    public var title: String {
        switch self {
        case .native: "原生"
        case .fallback: "Fallback"
        case .missing: "缺失"
        }
    }
}

public struct PetActionCoverage: Identifiable, Codable, Hashable, Sendable {
    public var id: String { action.rawValue }
    public var action: PetAction
    public var resolvedAction: PetAction?
    public var status: PetActionCoverageStatus
    public var frameCount: Int

    public init(action: PetAction, resolvedAction: PetAction?, status: PetActionCoverageStatus, frameCount: Int) {
        self.action = action
        self.resolvedAction = resolvedAction
        self.status = status
        self.frameCount = max(0, frameCount)
    }
}

private struct LegacyLicense: Codable {
    var type: String?
    var note: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

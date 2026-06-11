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
            return .distractedLook
        case "nudgeEntertainment":
            return .nudgeStrong
        case "welcomeBack":
            return .welcomeBack
        case "idleSpecial", "playfulIdle":
            return key == "idleSpecial" ? .breakRelax : .run
        default:
            return nil
        }
    }
}

public struct PetActionResolver: Sendable {
    public init() {}

    public func animationKey(for action: PetAction, in pack: PetPack) -> PetAction? {
        if let semanticKey = semanticAnimationKey(for: action, in: pack) {
            return semanticKey
        }

        return pack.animations.keys.sorted { $0.rawValue < $1.rawValue }.first
    }

    public func semanticAnimationKey(for action: PetAction, in pack: PetPack) -> PetAction? {
        if pack.animations[action] != nil {
            return action
        }

        for fallback in fallbacks(for: action) where pack.animations[fallback] != nil {
            return fallback
        }

        return nil
    }

    public func fallbacks(for action: PetAction) -> [PetAction] {
        switch action {
        case .blink, .breath, .focusStable:
            return [.idle]
        case .wake:
            return [.welcomeBack, .idle]
        case .focusStart:
            return [.welcomeBack, .idle]
        case .stretch:
            return [.idle]
        case .dragged:
            return [.run, .idle]
        case .landing:
            return [.welcomeBack, .idle]
        case .run:
            return [.idle]
        case .screenTransfer:
            return [.run, .welcomeBack, .idle]
        case .mouseSummon:
            return [.welcomeBack, .distractedLook, .idle]
        case .distractedLook:
            return [.nudgeGentle, .idle]
        case .nudgeGentle:
            return [.distractedLook, .idle]
        case .nudgeStrong:
            return [.distractedLook, .nudgeGentle, .welcomeBack, .idle]
        case .breakEnd:
            return [.welcomeBack, .idle]
        case .sleep:
            return [.breakRelax, .idle]
        case .breakRelax:
            return [.idle]
        case .idle, .welcomeBack:
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

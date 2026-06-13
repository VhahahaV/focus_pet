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

public struct PetAudioSpec: Codable, Hashable, Sendable {
    public var file: String
    public var volume: Double

    public init(file: String, volume: Double = 0.55) {
        self.file = file
        self.volume = min(1, max(0, volume))
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let file = try? container.decode(String.self) {
            self.init(file: file)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            file: try container.decode(String.self, forKey: .file),
            volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.55
        )
    }

    private enum CodingKeys: String, CodingKey {
        case file
        case volume
    }
}

public struct PetSourceActionSpec: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var folder: String
    public var fps: Double
    public var loop: Bool
    public var frameCount: Int?
    public var audio: PetAudioSpec?

    public init(
        id: String,
        title: String,
        folder: String,
        fps: Double,
        loop: Bool,
        frameCount: Int?,
        audio: PetAudioSpec? = nil
    ) {
        self.id = id
        self.title = title.isEmpty ? id : title
        self.folder = folder
        self.fps = max(1, fps)
        self.loop = loop
        self.frameCount = frameCount.map { max(0, $0) }
        self.audio = audio
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
    public var audio: [PetAction: PetAudioSpec]
    public var sourceActions: [PetSourceActionSpec]
    public var idleSourceActionIDs: [String]

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
        animations: [PetAction: PetAnimationSpec],
        audio: [PetAction: PetAudioSpec] = [:],
        sourceActions: [PetSourceActionSpec] = [],
        idleSourceActionIDs: [String] = []
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
        self.audio = audio
        self.sourceActions = sourceActions
        self.idleSourceActionIDs = idleSourceActionIDs
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
        case audio
        case sourceActions
        case idleSourceActionIDs
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

        let keyedAudio = (try? container.decodeIfPresent([String: PetAudioSpec].self, forKey: .audio)) ?? [:]
        audio = keyedAudio.reduce(into: [:]) { result, item in
            let (key, value) = item
            guard let action = PetAction(rawValue: key) ?? Self.legacyAction(for: key),
                  result[action] == nil else {
                return
            }
            result[action] = value
        }
        sourceActions = try container.decodeIfPresent([PetSourceActionSpec].self, forKey: .sourceActions) ?? []
        idleSourceActionIDs = try container.decodeIfPresent([String].self, forKey: .idleSourceActionIDs) ?? []
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
        if !audio.isEmpty {
            let keyedAudio = Dictionary(uniqueKeysWithValues: audio.map { ($0.key.rawValue, $0.value) })
            try container.encode(keyedAudio, forKey: .audio)
        }
        if !sourceActions.isEmpty {
            try container.encode(sourceActions, forKey: .sourceActions)
        }
        if !idleSourceActionIDs.isEmpty {
            try container.encode(idleSourceActionIDs, forKey: .idleSourceActionIDs)
        }
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

        return PetPackFrameURLCache.frameURLs(rootURL: rootURL, folder: spec.folder)
    }

    public var previewSourceActions: [PetSourceActionSpec] {
        if !pack.sourceActions.isEmpty {
            return pack.sourceActions
        }

        return pack.animations
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { action, animation in
                PetSourceActionSpec(
                    id: action.rawValue,
                    title: action.title,
                    folder: animation.folder,
                    fps: animation.fps,
                    loop: animation.loop,
                    frameCount: animation.frameCount
                )
            }
    }

    public var idleSourceActions: [PetSourceActionSpec] {
        let sourceActions = previewSourceActions
        guard !pack.idleSourceActionIDs.isEmpty else {
            return sourceActions.filter { $0.loop }
        }

        let actionByID = Dictionary(uniqueKeysWithValues: sourceActions.map { ($0.id, $0) })
        let selected = pack.idleSourceActionIDs.compactMap { actionByID[$0] }
        return selected.isEmpty ? sourceActions.filter { $0.loop } : selected
    }

    public var playableSourceActions: [PetSourceActionSpec] {
        let available = previewSourceActions.filter {
            !frameURLs(forSourceActionID: $0.id).isEmpty
        }
        let candidates = available.isEmpty ? previewSourceActions : available
        return deduplicatedSourceActions(candidates)
    }

    public func defaultSourceAction(for intent: PetIntentKind) -> PetSourceActionSpec? {
        let actions = playableSourceActions
        guard !actions.isEmpty else { return nil }

        let normalizedPreferred = intent.preferredSourceActionIDs.map(Self.normalizedActionKey)
        for preferred in normalizedPreferred {
            if let exact = actions.first(where: { Self.normalizedActionKey($0.id) == preferred }) {
                return exact
            }
        }

        for preferred in normalizedPreferred {
            if let titleMatch = actions.first(where: {
                Self.normalizedActionKey($0.title).contains(preferred)
                    || preferred.contains(Self.normalizedActionKey($0.title))
            }) {
                return titleMatch
            }
        }

        switch intent {
        case .quietCompanion, .distractedObserve:
            return actions.first(where: \.loop) ?? actions.first
        case .sleep:
            return actions.first(where: { Self.normalizedActionKey($0.id).contains("sleep") })
                ?? actions.first(where: \.loop)
                ?? actions.first
        case .breakCompanion:
            return actions.first(where: { Self.normalizedActionKey($0.id).contains("break") })
                ?? actions.first(where: \.loop)
                ?? actions.first
        default:
            return actions.first
        }
    }

    public func sourceAction(
        for intent: PetIntentKind,
        mappedSourceActionID: String?
    ) -> PetSourceActionSpec? {
        if let mappedSourceActionID,
           let mapped = sourceAction(id: mappedSourceActionID),
           !frameURLs(forSourceActionID: mapped.id).isEmpty {
            return mapped
        }

        return defaultSourceAction(for: intent)
    }

    public func sourceAction(id: String) -> PetSourceActionSpec? {
        previewSourceActions.first { $0.id == id }
    }

    public func frameURLs(forSourceActionID id: String) -> [URL] {
        guard let action = sourceAction(id: id) else {
            return []
        }

        return frameURLs(forFolder: action.folder)
    }

    public func frameURLs(forFolder folder: String) -> [URL] {
        guard let rootURL else {
            return []
        }

        return PetPackFrameURLCache.frameURLs(rootURL: rootURL, folder: folder)
    }

    private func deduplicatedSourceActions(_ actions: [PetSourceActionSpec]) -> [PetSourceActionSpec] {
        var seenRenderKeys = Set<String>()
        var result: [PetSourceActionSpec] = []

        for action in actions {
            let key = sourceActionRenderKey(action)
            guard !seenRenderKeys.contains(key) else { continue }
            seenRenderKeys.insert(key)
            result.append(action)
        }

        return result
    }

    private func sourceActionRenderKey(_ action: PetSourceActionSpec) -> String {
        let frames = frameURLs(forSourceActionID: action.id)
        guard !frames.isEmpty else {
            return "folder|\(action.folder.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }

        return frames
            .map { $0.standardizedFileURL.path }
            .joined(separator: "|")
    }

    public func audioSpec(for action: PetAction) -> PetAudioSpec? {
        if let spec = pack.audio[action] {
            return spec
        }

        let resolver = PetActionResolver()
        if let animationKey = resolver.animationKey(for: action, in: pack),
           let spec = pack.audio[animationKey] {
            return spec
        }

        for fallback in resolver.fallbacks(for: action) where pack.audio[fallback] != nil {
            return pack.audio[fallback]
        }

        return nil
    }

    public func audioURL(for action: PetAction) -> URL? {
        guard let rootURL,
              let spec = audioSpec(for: action) else {
            return nil
        }

        let url = rootURL.appendingPathComponent(spec.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func audioURL(forSourceActionID id: String) -> URL? {
        guard let rootURL,
              let action = sourceAction(id: id),
              let spec = action.audio else {
            return nil
        }

        let url = rootURL.appendingPathComponent(spec.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

}

enum PetPackFrameURLCache {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var urlsByKey: [String: [URL]] = [:]

    static func frameURLs(rootURL: URL, folder: String) -> [URL] {
        let key = cacheKey(rootURL: rootURL, folder: folder)
        lock.lock()
        if let cached = urlsByKey[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let folderURL = rootURL.appendingPathComponent(folder, isDirectory: true)
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        lock.lock()
        urlsByKey[key] = urls
        lock.unlock()
        return urls
    }

    static func invalidate(rootURL: URL) {
        let pathPrefix = rootURL.standardizedFileURL.path + "|"
        lock.lock()
        urlsByKey = urlsByKey.filter { !$0.key.hasPrefix(pathPrefix) }
        lock.unlock()
    }

    private static func cacheKey(rootURL: URL, folder: String) -> String {
        "\(rootURL.standardizedFileURL.path)|\(folder)"
    }
}

private extension PetPackRecord {
    static func normalizedActionKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
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

import Foundation

public struct PetPackValidationResult: Codable, Hashable, Sendable {
    public var pack: PetPack?
    public var isValid: Bool { errors.isEmpty }
    public var errors: [PetPackValidationError]
    public var warnings: [PetPackValidationWarning]

    public init(
        pack: PetPack?,
        errors: [PetPackValidationError],
        warnings: [PetPackValidationWarning]
    ) {
        self.pack = pack
        self.errors = errors
        self.warnings = warnings
    }
}

public enum PetPackValidationError: String, Codable, Hashable, Sendable {
    case missingManifest
    case unreadableManifest
    case invalidID
    case emptyAnimations
    case noPlayableFrames
    case invalidDefaultSize
    case invalidFPS
}

public enum PetPackValidationWarning: String, Codable, Hashable, Sendable {
    case missingPreview
    case missingIdleOrSleeping
    case missingAnimationFolder
    case emptyAnimationFolder
    case unknownLicense
    case unknownDistribution
    case highFrameCount
}

public struct PetPackValidator: Sendable {
    public init() {}

    public func validate(rootURL: URL) -> PetPackValidationResult {
        let manifestURL = rootURL.appendingPathComponent("pet.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return PetPackValidationResult(pack: nil, errors: [.missingManifest], warnings: [])
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let pack = try? JSONDecoder().decode(PetPack.self, from: data) else {
            return PetPackValidationResult(pack: nil, errors: [.unreadableManifest], warnings: [])
        }
        return validate(pack: pack, rootURL: rootURL)
    }

    public func validate(pack: PetPack, rootURL: URL) -> PetPackValidationResult {
        var errors: Set<PetPackValidationError> = []
        var warnings: Set<PetPackValidationWarning> = []

        if !Self.isValidID(pack.id) {
            errors.insert(.invalidID)
        }
        if pack.animations.isEmpty {
            errors.insert(.emptyAnimations)
        }
        if pack.defaultSize.width < 64
            || pack.defaultSize.width > 512
            || pack.defaultSize.height < 64
            || pack.defaultSize.height > 512 {
            errors.insert(.invalidDefaultSize)
        }
        if !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("preview.png").path) {
            warnings.insert(.missingPreview)
        }
        if pack.license?.type == "unknown" {
            warnings.insert(.unknownLicense)
        }
        if pack.distribution == .unknown {
            warnings.insert(.unknownDistribution)
        }
        if pack.animations[.idle] == nil && pack.animations[.sleeping] == nil {
            warnings.insert(.missingIdleOrSleeping)
        }

        var playableCount = 0
        for spec in pack.animations.values {
            if spec.fps < 1 || spec.fps > 60 {
                errors.insert(.invalidFPS)
            }

            let folderURL = rootURL.appendingPathComponent(spec.folder, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                warnings.insert(.missingAnimationFolder)
                continue
            }

            let frames = Self.pngFrames(in: folderURL)
            if frames.isEmpty {
                warnings.insert(.emptyAnimationFolder)
            } else {
                playableCount += 1
            }
            if frames.count > 240 {
                warnings.insert(.highFrameCount)
            }
        }

        if playableCount == 0 {
            errors.insert(.noPlayableFrames)
        }

        return PetPackValidationResult(
            pack: pack,
            errors: errors.sorted { $0.rawValue < $1.rawValue },
            warnings: warnings.sorted { $0.rawValue < $1.rawValue }
        )
    }

    public static func pngFrames(in folderURL: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}

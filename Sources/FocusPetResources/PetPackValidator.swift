import FocusPetCore
import Foundation

public enum PetPackValidationError: Codable, Hashable, Sendable {
    case unsupportedSchema
    case missingID
    case missingName
    case missingRequiredAction(PetAction)
    case invalidFrameCount(PetAction)
    case missingAnimationFolder(PetAction)
    case missingAnimationFrames(PetAction)

    public var title: String {
        switch self {
        case .unsupportedSchema:
            "不支持的 schema"
        case .missingID:
            "缺少 ID"
        case .missingName:
            "缺少名称"
        case .missingRequiredAction(let action):
            "缺少必要动作：\(action.title)"
        case .invalidFrameCount(let action):
            "帧数无效：\(action.title)"
        case .missingAnimationFolder(let action):
            "缺少动作文件夹：\(action.title)"
        case .missingAnimationFrames(let action):
            "缺少 PNG 帧：\(action.title)"
        }
    }
}

public enum PetPackValidationWarning: String, Codable, Hashable, Sendable, CaseIterable {
    case missingPreview
    case missingLicense
    case missingDistribution

    public var title: String {
        switch self {
        case .missingPreview:
            "缺少 preview.png"
        case .missingLicense:
            "缺少授权说明"
        case .missingDistribution:
            "缺少分发说明"
        }
    }
}

public struct PetPackValidationResult: Codable, Hashable, Sendable {
    public var errors: [PetPackValidationError]
    public var warnings: [PetPackValidationWarning]

    public var isValid: Bool {
        errors.isEmpty
    }
}

public struct PetPackValidator: Sendable {
    public var requiredActions: [PetAction]

    public init(requiredActions: [PetAction] = [.idle, .sleep, .nudgeGentle, .welcomeBack, .breakRelax]) {
        self.requiredActions = requiredActions
    }

    public func validate(_ pack: PetPack, previewExists: Bool = true) -> PetPackValidationResult {
        validate(pack, rootURL: nil, previewExists: previewExists)
    }

    public func validate(_ pack: PetPack, rootURL: URL?, previewExists: Bool? = nil) -> PetPackValidationResult {
        var errors: [PetPackValidationError] = []
        var warnings: [PetPackValidationWarning] = []
        let fileManager = FileManager.default

        if pack.schemaVersion != 1 {
            errors.append(.unsupportedSchema)
        }
        if pack.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingID)
        }
        if pack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingName)
        }
        for action in requiredActions where pack.animations[action] == nil {
            errors.append(.missingRequiredAction(action))
        }
        for (action, animation) in pack.animations where (animation.frameCount ?? 1) < 0 {
            errors.append(.invalidFrameCount(action))
        }
        if let rootURL {
            for (action, animation) in pack.animations {
                let folderURL = rootURL.appendingPathComponent(animation.folder, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    errors.append(.missingAnimationFolder(action))
                    continue
                }

                let frameURLs = (try? fileManager.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                if frameURLs.filter({ $0.pathExtension.lowercased() == "png" }).isEmpty {
                    errors.append(.missingAnimationFrames(action))
                }
            }
        }

        let hasPreview = previewExists ?? rootURL.map { root in
            fileManager.fileExists(atPath: root.appendingPathComponent("preview.png").path)
        } ?? true
        if !hasPreview {
            warnings.append(.missingPreview)
        }
        if pack.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(.missingLicense)
        }
        if pack.distribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(.missingDistribution)
        }

        return PetPackValidationResult(errors: errors, warnings: warnings)
    }
}

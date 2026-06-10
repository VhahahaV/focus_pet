import FocusPetCore
import Foundation

struct ImportedPetPack: Hashable {
    var pack: PetPack
    var installedURL: URL
    var validation: PetPackValidationResult
}

enum PetPackImportError: LocalizedError {
    case validationFailed([PetPackValidationError])
    case missingDecodedPack
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let errors):
            "资源包校验失败：\(errors.map(\.rawValue).joined(separator: ", "))"
        case .missingDecodedPack:
            "资源包 manifest 无法解析。"
        case .copyFailed(let message):
            "资源包复制失败：\(message)"
        }
    }
}

struct PetPackImporter {
    var installRootURL: URL

    func importPack(from sourceURL: URL) throws -> ImportedPetPack {
        let validation = PetPackValidator().validate(rootURL: sourceURL)
        guard validation.errors.isEmpty else {
            throw PetPackImportError.validationFailed(validation.errors)
        }
        guard var pack = validation.pack else {
            throw PetPackImportError.missingDecodedPack
        }

        pack.source = .userImported
        let installURL = installRootURL.appendingPathComponent(pack.id, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: installRootURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: installURL.path) {
                try FileManager.default.removeItem(at: installURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: installURL)
            let manifestURL = installURL.appendingPathComponent("pet.json")
            let data = try JSONEncoder.focusPet.encode(pack)
            try data.write(to: manifestURL, options: [.atomic])
        } catch {
            throw PetPackImportError.copyFailed(error.localizedDescription)
        }

        return ImportedPetPack(
            pack: pack,
            installedURL: installURL,
            validation: validation
        )
    }
}

private extension JSONEncoder {
    static var focusPet: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

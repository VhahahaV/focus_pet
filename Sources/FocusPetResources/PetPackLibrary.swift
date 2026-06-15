import FocusPetCore
import Foundation

public struct ImportedPetPack: Hashable, Sendable {
    public var record: PetPackRecord

    public init(record: PetPackRecord) {
        self.record = record
    }
}

public enum PetPackImportError: LocalizedError, Hashable, Sendable {
    case manifestNotFound
    case manifestInvalid
    case validationFailed([PetPackValidationError])
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .manifestNotFound:
            "资源包里没有 pet.json。"
        case .manifestInvalid:
            "资源包 manifest 无法解析。"
        case .validationFailed(let errors):
            "资源包校验失败：\(errors.map(\.title).joined(separator: "、"))"
        case .copyFailed(let message):
            "资源包复制失败：\(message)"
        }
    }
}

public struct PetPackLibrary: Sendable {
    public var installRootURL: URL

    public init(installRootURL: URL = Self.defaultInstallRootURL()) {
        self.installRootURL = installRootURL
    }

    public static func defaultInstallRootURL() -> URL {
        FocusPetDataPaths.petPacksRootURL()
    }

    public func importPack(from selectedURL: URL) throws -> ImportedPetPack {
        let sourceRoot = sourceRootURL(from: selectedURL)
        guard FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("pet.json").path) else {
            throw PetPackImportError.manifestNotFound
        }
        guard let pack = PetPackCatalog().loadPack(at: sourceRoot) else {
            throw PetPackImportError.manifestInvalid
        }

        let validation = PetPackValidator().validate(pack, rootURL: sourceRoot)
        guard validation.isValid else {
            throw PetPackImportError.validationFailed(validation.errors)
        }

        let destinationURL = installRootURL.appendingPathComponent(safeDirectoryName(for: pack.id), isDirectory: true)
        let sourcePath = sourceRoot.standardizedFileURL.path
        let destinationPath = destinationURL.standardizedFileURL.path

        do {
            try FileManager.default.createDirectory(at: installRootURL, withIntermediateDirectories: true)
            if sourcePath != destinationPath {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceRoot, to: destinationURL)
            }
            PetPackFrameURLCache.invalidate(rootURL: destinationURL)
        } catch {
            throw PetPackImportError.copyFailed(error.localizedDescription)
        }

        guard let record = PetPackCatalog().record(at: destinationURL, isBundled: false) else {
            throw PetPackImportError.manifestInvalid
        }
        return ImportedPetPack(record: record)
    }

    public func deletePack(id: String) throws {
        let url = installRootURL.appendingPathComponent(safeDirectoryName(for: id), isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        PetPackFrameURLCache.invalidate(rootURL: url)
    }

    private func sourceRootURL(from selectedURL: URL) -> URL {
        if selectedURL.lastPathComponent == "pet.json" {
            return selectedURL.deletingLastPathComponent()
        }
        return selectedURL
    }

    private func safeDirectoryName(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }
}

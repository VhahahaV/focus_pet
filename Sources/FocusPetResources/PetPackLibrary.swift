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
    case archiveExtractionFailed(String)
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .manifestNotFound:
            "资源包里没有可导入的 pet.json。"
        case .manifestInvalid:
            "资源包 manifest 无法解析。"
        case .validationFailed(let errors):
            "资源包校验失败：\(errors.map(\.title).joined(separator: "、"))"
        case .archiveExtractionFailed(let message):
            "资源包解压失败：\(message)"
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
        guard let imported = try importPacks(from: selectedURL).first else {
            throw PetPackImportError.manifestNotFound
        }
        return imported
    }

    public func importPacks(from selectedURL: URL) throws -> [ImportedPetPack] {
        if selectedURL.pathExtension.lowercased() == "zip" {
            return try importArchive(from: selectedURL)
        }

        let sourceRoot = sourceRootURL(from: selectedURL)
        let roots = importablePackRoots(in: sourceRoot, recursive: false)
        return try importPackRoots(roots)
    }

    public func deletePack(id: String) throws {
        let url = installRootURL.appendingPathComponent(safeDirectoryName(for: id), isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        PetPackFrameURLCache.invalidate(rootURL: url)
    }

    private struct ValidatedPetPackSource {
        var rootURL: URL
        var pack: PetPack
    }

    private func importArchive(from archiveURL: URL) throws -> [ImportedPetPack] {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        do {
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        } catch {
            throw PetPackImportError.archiveExtractionFailed(error.localizedDescription)
        }

        try extractArchive(archiveURL, to: temporaryRoot)
        return try importPackRoots(importablePackRoots(in: temporaryRoot, recursive: true))
    }

    private func importPackRoots(_ roots: [URL]) throws -> [ImportedPetPack] {
        let sources = try validatedSources(from: roots)
        return try sources.map { try importValidatedPack($0) }
    }

    private func validatedSources(from roots: [URL]) throws -> [ValidatedPetPackSource] {
        guard !roots.isEmpty else {
            throw PetPackImportError.manifestNotFound
        }

        return try roots.map { root in
            guard let pack = PetPackCatalog().loadPack(at: root) else {
                throw PetPackImportError.manifestInvalid
            }

            let validation = PetPackValidator().validate(pack, rootURL: root)
            guard validation.isValid else {
                throw PetPackImportError.validationFailed(validation.errors)
            }

            return ValidatedPetPackSource(rootURL: root, pack: pack)
        }
    }

    private func importValidatedPack(_ source: ValidatedPetPackSource) throws -> ImportedPetPack {
        let destinationURL = installRootURL.appendingPathComponent(safeDirectoryName(for: source.pack.id), isDirectory: true)
        let sourcePath = source.rootURL.standardizedFileURL.path
        let destinationPath = destinationURL.standardizedFileURL.path

        do {
            try FileManager.default.createDirectory(at: installRootURL, withIntermediateDirectories: true)
            if sourcePath != destinationPath {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: source.rootURL, to: destinationURL)
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

    private func sourceRootURL(from selectedURL: URL) -> URL {
        if selectedURL.lastPathComponent == "pet.json" {
            return selectedURL.deletingLastPathComponent()
        }
        return selectedURL
    }

    private func importablePackRoots(in rootURL: URL, recursive: Bool) -> [URL] {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: rootURL.appendingPathComponent("pet.json").path) {
            return [rootURL]
        }

        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            var roots: [URL] = []
            for case let url as URL in enumerator where url.lastPathComponent == "pet.json" {
                let packRoot = url.deletingLastPathComponent()
                if packRoot.pathComponents.contains("__MACOSX") {
                    continue
                }
                roots.append(packRoot)
            }
            return uniqueSortedRoots(roots)
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let roots = children.filter { child in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return false
            }
            return fileManager.fileExists(atPath: child.appendingPathComponent("pet.json").path)
        }
        return uniqueSortedRoots(roots)
    }

    private func uniqueSortedRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .filter { root in
                let path = root.standardizedFileURL.path
                guard !seen.contains(path) else { return false }
                seen.insert(path)
                return true
            }
    }

    private func extractArchive(_ archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PetPackImportError.archiveExtractionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
                ?? "ditto 退出码 \(process.terminationStatus)"
            throw PetPackImportError.archiveExtractionFailed(message)
        }
    }

    private func safeDirectoryName(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }
}

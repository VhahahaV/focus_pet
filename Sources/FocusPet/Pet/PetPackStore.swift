import FocusPetCore
import Foundation

struct PetPackRecord: Identifiable, Hashable {
    var id: String { pack.id }
    var pack: PetPack
    var rootURL: URL
    var validation: PetPackValidationResult
}

struct PetPackStore {
    var userRootURL: URL

    func installGeneratedLuoXiaoHeiPackIfAvailable() -> ImportedPetPack? {
        guard let sourceURL = generatedLuoXiaoHeiPackURL() else { return nil }
        return try? PetPackImporter(installRootURL: userRootURL).importPack(from: sourceURL)
    }

    func records() -> [PetPackRecord] {
        preferredUniqueRecords(bundledRecords() + userRecords() + generatedRecords())
    }

    func record(id: String) -> PetPackRecord? {
        records().first { $0.id == id } ?? bundledRecords().first
    }

    private func bundledRecords() -> [PetPackRecord] {
        guard let petsURL = Bundle.module.resourceURL?.appendingPathComponent("Pets", isDirectory: true),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: petsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return urls.compactMap { record(url: $0) }
    }

    private func userRecords() -> [PetPackRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: userRootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.compactMap { record(url: $0) }
    }

    private func generatedRecords() -> [PetPackRecord] {
        guard let url = generatedLuoXiaoHeiPackURL(),
              let record = record(url: url) else {
            return []
        }
        return [record]
    }

    private func record(url: URL) -> PetPackRecord? {
        let validation = PetPackValidator().validate(rootURL: url)
        guard let pack = validation.pack else { return nil }
        return PetPackRecord(pack: pack, rootURL: url, validation: validation)
    }

    private func preferredUniqueRecords(_ records: [PetPackRecord]) -> [PetPackRecord] {
        var result: [PetPackRecord] = []
        var seen: Set<String> = []

        for record in records.reversed() where seen.insert(record.id).inserted {
            result.append(record)
        }

        return result.reversed()
    }

    private func generatedLuoXiaoHeiPackURL() -> URL? {
        packURLCandidates()
            .first { url in
                let validation = PetPackValidator().validate(rootURL: url)
                return validation.pack?.id == PetPackDefaults.luoXiaoHeiLocalID && validation.isValid
            }
    }

    private func packURLCandidates() -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        for candidate in bundledLocalPackCandidates() where seen.insert(candidate.standardizedFileURL.path).inserted {
            candidates.append(candidate)
        }

        guard shouldSearchProjectSourcePacks else { return candidates }

        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let anchors = [cwd, sourceFileProjectRootURL()].compactMap { $0 }
        for anchor in anchors {
            for ancestor in ancestorURLs(from: anchor) {
                let candidate = ancestor
                    .appendingPathComponent("external_generated_packs", isDirectory: true)
                    .appendingPathComponent("LuoXiaoHeiLocal", isDirectory: true)
                if seen.insert(candidate.standardizedFileURL.path).inserted {
                    candidates.append(candidate)
                }
            }
        }

        return candidates
    }

    private func bundledLocalPackCandidates() -> [URL] {
        [
            Bundle.main.resourceURL,
            Bundle.module.resourceURL
        ]
        .compactMap { $0 }
        .map {
            $0
                .appendingPathComponent("LocalPetPacks", isDirectory: true)
                .appendingPathComponent("LuoXiaoHeiLocal", isDirectory: true)
        }
    }

    private var shouldSearchProjectSourcePacks: Bool {
        Bundle.main.bundleURL.pathExtension != "app"
    }

    private func ancestorURLs(from url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL

        for _ in 0..<10 {
            result.append(current)
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }

        return result
    }

    private func sourceFileProjectRootURL() -> URL? {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        var current = sourceFileURL.deletingLastPathComponent()

        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }

        return nil
    }
}

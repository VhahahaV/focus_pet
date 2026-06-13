import Foundation

public struct PetPackCatalog: Sendable {
    public static let bundledPackID = "focus_dino"
    public static let localLuoXiaoHeiPackID = "luo_xiaohei_local"
    public static let localXiaoDaiPackID = "xiaodai_local"
    public static let localPixelCatMemePackID = "pixel_cat_meme_local"

    public init() {}

    public func bundledPacks() -> [PetPackRecord] {
        []
    }

    public func availablePacks(userRootURL: URL = PetPackLibrary.defaultInstallRootURL()) -> [PetPackRecord] {
        var result: [PetPackRecord] = []

        result.append(contentsOf: records(in: userRootURL, isBundled: false))

        result.append(contentsOf: localGeneratedPackRecords())

        result.append(contentsOf: bundledPacks())

        var seen = Set<String>()
        return result.filter { record in
            guard !seen.contains(record.id) else { return false }
            seen.insert(record.id)
            return true
        }
    }

    public func loadPack(at rootURL: URL) -> PetPack? {
        let manifestURL = rootURL.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(PetPack.self, from: data)
    }

    public func record(at rootURL: URL, isBundled: Bool = false) -> PetPackRecord? {
        guard let pack = loadPack(at: rootURL) else { return nil }
        let validation = PetPackValidator().validate(pack, rootURL: rootURL)
        return PetPackRecord(pack: pack, rootURL: rootURL, isBundled: isBundled, validation: validation)
    }

    private func records(in rootURL: URL, isBundled: Bool) -> [PetPackRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { record(at: $0, isBundled: isBundled) }
    }

    private func localGeneratedPackRecords() -> [PetPackRecord] {
        localGeneratedPackRoots().flatMap { records(in: $0, isBundled: false) }
    }

    private func localGeneratedPackRoots() -> [URL] {
        let fileManager = FileManager.default
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let environmentRoot = ProcessInfo.processInfo.environment["FOCUS_PET_LOCAL_PACKS_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("LocalPetPacks", isDirectory: true),
            Bundle.module.resourceURL?
                .appendingPathComponent("LocalPetPacks", isDirectory: true),
            workingDirectory
                .appendingPathComponent("external_generated_packs", isDirectory: true),
            workingDirectory
                .appendingPathComponent("LocalPetPacks", isDirectory: true),
            environmentRoot
        ]

        var seen = Set<String>()
        return candidates.compactMap { $0 }.filter { url in
            guard fileManager.fileExists(atPath: url.path) else {
                return false
            }

            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else {
                return false
            }

            seen.insert(path)
            return true
        }
    }

    public static let fallbackPack = PetPack(
        schemaVersion: 1,
        id: bundledPackID,
        name: "Focus Dino",
        author: "Focus Pet",
        style: "minimal_2d",
        license: "original",
        distribution: "redistributable",
        defaultSize: PetPackSize(width: 160, height: 160),
        anchor: PetPackAnchor(x: 0.5, y: 1.0),
        animations: [
            .idle: PetAnimationSpec(folder: "idle", fps: 1, loop: true, frameCount: 1),
            .sleep: PetAnimationSpec(folder: "sleep", fps: 4, loop: true, frameCount: 1),
            .nudgeGentle: PetAnimationSpec(folder: "nudgeGentle", fps: 8, loop: false, frameCount: 1),
            .welcomeBack: PetAnimationSpec(folder: "welcomeBack", fps: 8, loop: false, frameCount: 1),
            .breakRelax: PetAnimationSpec(folder: "breakRelax", fps: 6, loop: true, frameCount: 1)
        ]
    )
}

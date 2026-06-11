import Foundation

public struct PetPackCatalog: Sendable {
    public static let bundledPackID = "focus_dino"
    public static let localLuoXiaoHeiPackID = "luo_xiaohei_local"

    public init() {}

    public func bundledPacks() -> [PetPackRecord] {
        guard let root = Bundle.module.url(forResource: "FocusDino", withExtension: nil, subdirectory: "Pets"),
              let pack = loadPack(at: root) else {
            return [PetPackRecord(pack: Self.fallbackPack, rootURL: nil, isBundled: true)]
        }

        return [PetPackRecord(pack: pack, rootURL: root, isBundled: true)]
    }

    public func availablePacks(userRootURL: URL = PetPackLibrary.defaultInstallRootURL()) -> [PetPackRecord] {
        var result: [PetPackRecord] = []

        result.append(contentsOf: records(in: userRootURL, isBundled: false))

        if let localRoot = localLuoXiaoHeiRoot(),
           let pack = loadPack(at: localRoot) {
            result.append(PetPackRecord(pack: pack, rootURL: localRoot, isBundled: false))
        }

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

    private func localLuoXiaoHeiRoot() -> URL? {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("LocalPetPacks", isDirectory: true)
                .appendingPathComponent("LuoXiaoHeiLocal", isDirectory: true),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("external_generated_packs", isDirectory: true)
                .appendingPathComponent("LuoXiaoHeiLocal", isDirectory: true),
            URL(fileURLWithPath: "/Users/vhahahav/Code/focus_pet/external_generated_packs/LuoXiaoHeiLocal", isDirectory: true)
        ]

        return candidates.compactMap { $0 }.first { url in
            fileManager.fileExists(atPath: url.appendingPathComponent("pet.json").path)
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

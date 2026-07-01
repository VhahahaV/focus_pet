import FocusPetCore
import Foundation

public struct PetPackCatalog: Sendable {
    public static let localLuoXiaoHeiPackID = "luo_xiaohei_local"
    public static let localXiaoDaiPackID = "xiaodai_local"
    public static let localPixelCatMemePackID = "pixel_cat_meme_local"

    public init() {}

    public func bundledPacks() -> [PetPackRecord] {
        []
    }

    public func availablePacks(
        userRootURL: URL = PetPackLibrary.defaultInstallRootURL(),
        hiddenPackIDs: Set<String> = []
    ) -> [PetPackRecord] {
        var result: [PetPackRecord] = []

        result.append(contentsOf: records(in: userRootURL, isBundled: false))

        result.append(contentsOf: localGeneratedPackRecords())

        result.append(contentsOf: bundledPacks())

        var seen = Set<String>()
        return result.filter { record in
            guard !hiddenPackIDs.contains(record.id),
                  !seen.contains(record.id) else { return false }
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

        return urls
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { record(at: $0, isBundled: isBundled) }
    }

    private func localGeneratedPackRecords() -> [PetPackRecord] {
        localGeneratedPackRoots().flatMap { records(in: $0, isBundled: false) }
    }

    private func localGeneratedPackRoots() -> [URL] {
        let fileManager = FileManager.default
        let environmentRoot = ProcessInfo.processInfo.environment["FOCUS_PET_LOCAL_PACKS_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let packagedResourceRoot = FocusPetPackagedResources.bundle(
            named: "FocusPet_FocusPetResources.bundle",
            fallback: Bundle.module
        )?.resourceURL
        let candidates: [URL?] = [
            Bundle.main.resourceURL?
                .appendingPathComponent("LocalPetPacks", isDirectory: true),
            packagedResourceRoot?
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

}

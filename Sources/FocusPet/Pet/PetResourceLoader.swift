import AppKit
import FocusPetCore
import Foundation

struct PetAnimationFrames {
    var key: PetAnimationKey
    var descriptor: PetAnimationSpec
    var images: [NSImage]
}

struct PetSpriteCatalog {
    var pack: PetPack?
    var animations: [PetAnimationKey: PetAnimationFrames]

    func frames(for action: PetAction) -> PetAnimationFrames? {
        guard let pack else {
            return firstPlayableAnimation()
        }

        for key in candidateKeys(for: action, pack: pack) {
            if let frames = animations[key], !frames.images.isEmpty {
                return frames
            }
        }

        return firstPlayableAnimation()
    }

    private func candidateKeys(for action: PetAction, pack: PetPack) -> [PetAnimationKey] {
        let target = PetAnimationKey(action)
        var keys: [PetAnimationKey] = [target]

        if let alias = pack.actionAliases[target] {
            keys.append(alias)
        }
        keys.append(.idle)
        keys.append(.sleeping)
        keys.append(contentsOf: pack.animations.keys.sorted { $0.rawValue < $1.rawValue })

        var seen: Set<PetAnimationKey> = []
        return keys.filter { seen.insert($0).inserted }
    }

    private func firstPlayableAnimation() -> PetAnimationFrames? {
        animations.values
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .first { !$0.images.isEmpty }
    }
}

enum PetResourceLoader {
    static func loadBundledPack(id: String) -> PetSpriteCatalog {
        if id == "focus_dino",
           let manifestURL = Bundle.module.url(
            forResource: "pet",
            withExtension: "json",
            subdirectory: "Pets/FocusDino"
           ) {
            return load(rootURL: manifestURL.deletingLastPathComponent())
        }

        guard let petsURL = Bundle.module.resourceURL?.appendingPathComponent("Pets", isDirectory: true),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: petsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return loadBundledFallback()
        }

        return urls
            .map { load(rootURL: $0) }
            .first { $0.pack?.id == id }
            ?? loadBundledFallback()
    }

    static func load(record: PetPackRecord) -> PetSpriteCatalog {
        load(rootURL: record.rootURL)
    }

    static func load(rootURL: URL) -> PetSpriteCatalog {
        let manifestURL = rootURL.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let pack = try? JSONDecoder().decode(PetPack.self, from: data) else {
            return PetSpriteCatalog(pack: nil, animations: [:])
        }

        let animations = pack.animations.reduce(into: [PetAnimationKey: PetAnimationFrames]()) { result, entry in
            let folderURL = rootURL.appendingPathComponent(entry.value.folder, isDirectory: true)
            let urls = PetPackValidator.pngFrames(in: folderURL)
            let images = urls.compactMap(NSImage.init(contentsOf:))
            result[entry.key] = PetAnimationFrames(
                key: entry.key,
                descriptor: entry.value,
                images: images
            )
        }

        return PetSpriteCatalog(pack: pack, animations: animations)
    }

    private static func loadBundledFallback() -> PetSpriteCatalog {
        guard let manifestURL = Bundle.module.url(
            forResource: "pet",
            withExtension: "json",
            subdirectory: "Pets/FocusDino"
        ) else {
            return PetSpriteCatalog(pack: nil, animations: [:])
        }
        return load(rootURL: manifestURL.deletingLastPathComponent())
    }
}

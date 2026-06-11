import FocusPetCore
import FocusPetResources
import Foundation

struct PetPackMVPProbe {
    func missingStrongNudgeFallsBackToGentle() -> Bool {
        let pack = PetPack(
            schemaVersion: 1,
            id: "minimal",
            name: "Minimal",
            author: "Focus Pet",
            style: "minimal_2d",
            license: "original",
            distribution: "redistributable",
            defaultSize: PetPackSize(width: 160, height: 160),
            anchor: PetPackAnchor(x: 0.5, y: 1.0),
            animations: [
                .idle: PetAnimationSpec(folder: "idle", fps: 6, loop: true, frameCount: 1),
                .sleep: PetAnimationSpec(folder: "sleep", fps: 4, loop: true, frameCount: 1),
                .nudgeGentle: PetAnimationSpec(folder: "nudgeGentle", fps: 8, loop: false, frameCount: 1),
                .welcomeBack: PetAnimationSpec(folder: "welcomeBack", fps: 8, loop: false, frameCount: 1),
                .breakRelax: PetAnimationSpec(folder: "breakRelax", fps: 6, loop: true, frameCount: 1)
            ]
        )

        return PetActionResolver().animationKey(for: .nudgeStrong, in: pack) == .nudgeGentle
    }

    func validatorAcceptsFallbackCoveredActions() -> Bool {
        let pack = PetPack(
            schemaVersion: 1,
            id: "minimal",
            name: "Minimal",
            author: "Focus Pet",
            style: "minimal_2d",
            license: "original",
            distribution: "redistributable",
            defaultSize: PetPackSize(width: 160, height: 160),
            anchor: PetPackAnchor(x: 0.5, y: 1.0),
            animations: [.idle: PetAnimationSpec(folder: "idle", fps: 6, loop: true, frameCount: 1)]
        )

        let result = PetPackValidator().validate(pack)
        return result.isValid
    }

    func validatorRejectsUnrenderablePack() -> Bool {
        let pack = PetPack(
            schemaVersion: 1,
            id: "bad",
            name: "Bad",
            author: "Focus Pet",
            style: "minimal_2d",
            license: "original",
            distribution: "redistributable",
            defaultSize: PetPackSize(width: 160, height: 160),
            anchor: PetPackAnchor(x: 0.5, y: 1.0),
            animations: [:]
        )

        let result = PetPackValidator().validate(pack)
        return result.isValid == false && result.errors.contains(.missingRequiredAction(.idle))
    }

    func validatorRejectsOnlyUnrelatedFallbackAction() -> Bool {
        let pack = PetPack(
            schemaVersion: 1,
            id: "bad_semantics",
            name: "Bad Semantics",
            author: "Focus Pet",
            style: "minimal_2d",
            license: "original",
            distribution: "redistributable",
            defaultSize: PetPackSize(width: 160, height: 160),
            anchor: PetPackAnchor(x: 0.5, y: 1.0),
            animations: [.run: PetAnimationSpec(folder: "run", fps: 8, loop: true, frameCount: 1)]
        )

        let result = PetPackValidator().validate(pack)
        return !result.isValid && result.errors.contains(.missingRequiredAction(.idle))
    }

    func legacyLuoXiaoHeiManifestDecodesDistinctActionNames() -> Bool {
        let manifest = """
        {
          "schemaVersion": 1,
          "id": "luo_xiaohei_local",
          "name": "罗小黑",
          "distribution": "localOnly",
          "style": "anime_gif",
          "license": {
            "type": "unknown",
            "note": "Local testing only."
          },
          "defaultSize": {"width": 128, "height": 128},
          "anchor": "dockAttached",
          "animations": {
            "idle": {"folder": "idle", "fps": 8, "loop": true, "frameCount": 8, "renderer": "pngSequence"},
            "nudgeDistracted": {"folder": "nudge_distracted", "fps": 8, "loop": true, "frameCount": 10, "renderer": "pngSequence"},
            "idleSpecial": {"folder": "idle_special", "fps": 8, "loop": true, "frameCount": 6, "renderer": "pngSequence"},
            "playfulIdle": {"folder": "playful_idle", "fps": 8, "loop": true, "frameCount": 22, "renderer": "pngSequence"},
            "welcomeBack": {"folder": "welcome_back", "fps": 8, "loop": false, "frameCount": 16, "renderer": "pngSequence"}
          }
        }
        """

        guard let data = manifest.data(using: .utf8),
              let pack = try? JSONDecoder().decode(PetPack.self, from: data) else {
            return false
        }

        return pack.id == "luo_xiaohei_local"
            && pack.animations[.distractedLook]?.folder == "nudge_distracted"
            && pack.animations[.breakRelax] != nil
            && pack.animations[.run]?.folder == "playful_idle"
            && pack.license.contains("Local testing only.")
    }

    func libraryImportsValidPack() -> Bool {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-pack-test-\(UUID().uuidString)", isDirectory: true)
        let source = tempRoot.appendingPathComponent("SourcePack", isDirectory: true)
        let install = tempRoot.appendingPathComponent("Installed", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let pack = PetPack(
            schemaVersion: 1,
            id: "imported_test",
            name: "Imported Test",
            author: "Focus Pet",
            style: "minimal_2d",
            license: "original",
            distribution: "localOnly",
            defaultSize: PetPackSize(width: 160, height: 160),
            anchor: PetPackAnchor(x: 0.5, y: 1.0),
            animations: [
                .idle: PetAnimationSpec(folder: "idle", fps: 6, loop: true, frameCount: 1),
                .sleep: PetAnimationSpec(folder: "sleep", fps: 4, loop: true, frameCount: 1),
                .nudgeGentle: PetAnimationSpec(folder: "nudgeGentle", fps: 8, loop: false, frameCount: 1),
                .welcomeBack: PetAnimationSpec(folder: "welcomeBack", fps: 8, loop: false, frameCount: 1),
                .breakRelax: PetAnimationSpec(folder: "breakRelax", fps: 6, loop: true, frameCount: 1)
            ]
        )

        do {
            try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(pack)
            try data.write(to: source.appendingPathComponent("pet.json"))
            try Data([0]).write(to: source.appendingPathComponent("preview.png"))
            for animation in pack.animations.values {
                let folder = source.appendingPathComponent(animation.folder, isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data([0]).write(to: folder.appendingPathComponent("000.png"))
            }

            let imported = try PetPackLibrary(installRootURL: install).importPack(from: source)
            return imported.record.id == "imported_test"
                && imported.record.validation.isValid
                && fileManager.fileExists(atPath: install.appendingPathComponent("imported_test/pet.json").path)
        } catch {
            return false
        }
    }
}

private let runPetPackMVPProbe: Void = {
    let probe = PetPackMVPProbe()
    precondition(probe.missingStrongNudgeFallsBackToGentle(), "nudgeStrong should fall back to nudgeGentle")
    precondition(probe.validatorAcceptsFallbackCoveredActions(), "validator should accept packs covered by fallback actions")
    precondition(probe.validatorRejectsUnrenderablePack(), "validator should reject packs with no renderable actions")
    precondition(probe.validatorRejectsOnlyUnrelatedFallbackAction(), "validator should reject packs covered only by unrelated runtime fallback")
    precondition(
        probe.legacyLuoXiaoHeiManifestDecodesDistinctActionNames(),
        "legacy Luo Xiaohei manifest should decode into distinct action names"
    )
    precondition(probe.libraryImportsValidPack(), "pet pack library should import valid local packs")
}()

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

    func manifestDecodesOptionalActionAudio() -> Bool {
        let manifest = """
        {
          "schemaVersion": 1,
          "id": "audio_pack",
          "name": "Audio Pack",
          "distribution": "localOnly",
          "style": "pixel",
          "license": "local",
          "defaultSize": {"width": 128, "height": 128},
          "anchor": {"x": 0.5, "y": 1.0},
          "animations": {
            "idle": {"folder": "idle", "fps": 6, "loop": true, "frameCount": 4}
          },
          "audio": {
            "focusStart": {"file": "audio/work.wav", "volume": 0.25},
            "nudgeDistracted": "audio/legacy.wav"
          },
          "sourceActions": [
            {"id": "work", "title": "work", "folder": "work", "fps": 8, "loop": true, "frameCount": 4}
          ],
          "idleSourceActionIDs": ["work"]
        }
        """

        guard let data = manifest.data(using: .utf8),
              let pack = try? JSONDecoder().decode(PetPack.self, from: data) else {
            return false
        }

        return pack.audio[.focusStart]?.file == "audio/work.wav"
            && pack.audio[.focusStart]?.volume == 0.25
            && pack.audio[.distractedLook]?.file == "audio/legacy.wav"
            && pack.audio[.distractedLook]?.volume == 0.55
            && pack.sourceActions.first?.id == "work"
            && pack.idleSourceActionIDs == ["work"]
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

    func libraryImportsMultiPackZip() -> Bool {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-pack-zip-test-\(UUID().uuidString)", isDirectory: true)
        let collection = tempRoot.appendingPathComponent("FocusPetLocalPetPacks", isDirectory: true)
        let install = tempRoot.appendingPathComponent("Installed", isDirectory: true)
        let archive = tempRoot.appendingPathComponent("FocusPetLocalPetPacks.zip")
        defer { try? fileManager.removeItem(at: tempRoot) }

        let firstPack = importablePack(id: "zip_pack_a", name: "Zip Pack A")
        let secondPack = importablePack(id: "zip_pack_b", name: "Zip Pack B")

        do {
            try writeImportablePack(firstPack, to: collection.appendingPathComponent("ZipPackA", isDirectory: true))
            try writeImportablePack(secondPack, to: collection.appendingPathComponent("ZipPackB", isDirectory: true))
            try archiveDirectory(collection, to: archive)

            let imported = try PetPackLibrary(installRootURL: install).importPacks(from: archive)
            let importedIDs = Set(imported.map(\.record.id))
            return importedIDs == Set(["zip_pack_a", "zip_pack_b"])
                && fileManager.fileExists(atPath: install.appendingPathComponent("zip_pack_a/pet.json").path)
                && fileManager.fileExists(atPath: install.appendingPathComponent("zip_pack_b/pet.json").path)
        } catch {
            return false
        }
    }

    func libraryImportsSinglePackZip() -> Bool {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-single-pack-zip-test-\(UUID().uuidString)", isDirectory: true)
        let source = tempRoot.appendingPathComponent("SinglePack", isDirectory: true)
        let install = tempRoot.appendingPathComponent("Installed", isDirectory: true)
        let archive = tempRoot.appendingPathComponent("SinglePack.zip")
        defer { try? fileManager.removeItem(at: tempRoot) }

        let pack = importablePack(id: "single_zip_pack", name: "Single Zip Pack")

        do {
            try writeImportablePack(pack, to: source)
            try archiveDirectory(source, to: archive)

            let imported = try PetPackLibrary(installRootURL: install).importPacks(from: archive)
            return imported.map(\.record.id) == ["single_zip_pack"]
                && fileManager.fileExists(atPath: install.appendingPathComponent("single_zip_pack/pet.json").path)
        } catch {
            return false
        }
    }

    func libraryDeletesImportedPack() -> Bool {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-pack-delete-test-\(UUID().uuidString)", isDirectory: true)
        let source = tempRoot.appendingPathComponent("SourcePack", isDirectory: true)
        let install = tempRoot.appendingPathComponent("Installed", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let pack = importablePack(id: "delete_test", name: "Delete Test")

        do {
            try writeImportablePack(pack, to: source)
            _ = try PetPackLibrary(installRootURL: install).importPack(from: source)
            try PetPackLibrary(installRootURL: install).deletePack(id: pack.id)
            let records = PetPackCatalog().availablePacks(userRootURL: install, hiddenPackIDs: [pack.id])
            return !fileManager.fileExists(atPath: install.appendingPathComponent("delete_test").path)
                && !records.contains { $0.id == pack.id }
        } catch {
            return false
        }
    }

    func catalogEmptyAfterDeletingEveryImportedPack() -> Bool {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-delete-all-test-\(UUID().uuidString)", isDirectory: true)
        let source = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let install = tempRoot.appendingPathComponent("Installed", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        do {
            let first = importablePack(id: "delete_all_one", name: "Delete All One")
            let second = importablePack(id: "delete_all_two", name: "Delete All Two")
            try writeImportablePack(first, to: source.appendingPathComponent("One", isDirectory: true))
            try writeImportablePack(second, to: source.appendingPathComponent("Two", isDirectory: true))

            let library = PetPackLibrary(installRootURL: install)
            let imported = try library.importPacks(from: source)
            guard Set(imported.map(\.record.id)) == Set(["delete_all_one", "delete_all_two"]) else {
                return false
            }
            try library.deletePack(id: first.id)
            try library.deletePack(id: second.id)

            let records = PetPackCatalog().availablePacks(
                userRootURL: install,
                hiddenPackIDs: [first.id, second.id]
            )
            return records.isEmpty
                && !fileManager.fileExists(atPath: install.appendingPathComponent(first.id).path)
                && !fileManager.fileExists(atPath: install.appendingPathComponent(second.id).path)
        } catch {
            return false
        }
    }

    func playableActionsDeduplicateIdenticalFolders() -> Bool {
        let pack = PetPack(
            schemaVersion: 1,
            id: "dedupe_pack",
            name: "Dedupe Pack",
            author: "Focus Pet",
            style: "pixel",
            license: "local",
            distribution: "localOnly",
            defaultSize: PetPackSize(width: 128, height: 128),
            anchor: PetPackAnchor(x: 0.5, y: 1.0),
            animations: [:],
            sourceActions: [
                PetSourceActionSpec(id: "default", title: "default", folder: "stand", fps: 5, loop: true, frameCount: 1),
                PetSourceActionSpec(id: "up", title: "up", folder: "stand", fps: 5, loop: false, frameCount: 1),
                PetSourceActionSpec(id: "down", title: "down", folder: "stand", fps: 5, loop: false, frameCount: 1),
                PetSourceActionSpec(id: "sleep", title: "sleep", folder: "sleep", fps: 5, loop: true, frameCount: 1)
            ]
        )
        let record = PetPackRecord(pack: pack, rootURL: nil, isBundled: false)
        return record.previewSourceActions.map(\.id) == ["default", "up", "down", "sleep"]
            && record.playableSourceActions.map(\.id) == ["default", "sleep"]
    }

    func randomizableActionsIncludeEveryPlayableLoopAction() -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("focus-pet-random-actions-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let sourceActions = [
            PetSourceActionSpec(id: "default", title: "default", folder: "default", fps: 5, loop: true, frameCount: 1),
            PetSourceActionSpec(id: "focus", title: "focus", folder: "focus", fps: 5, loop: true, frameCount: 1),
            PetSourceActionSpec(id: "sleep", title: "sleep", folder: "sleep", fps: 5, loop: true, frameCount: 1)
        ] + (1...10).map { index in
            PetSourceActionSpec(
                id: "action\(index)",
                title: "Action \(index)",
                folder: "action\(index)",
                fps: 5,
                loop: true,
                frameCount: 1
            )
        } + [
            PetSourceActionSpec(id: "wave", title: "Wave", folder: "wave", fps: 5, loop: false, frameCount: 1)
        ]

        let pack = PetPack(
            schemaVersion: 1,
            id: "wide_random_pack",
            name: "Wide Random Pack",
            author: "Focus Pet",
            style: "pixel",
            license: "local",
            distribution: "localOnly",
            defaultSize: PetPackSize(width: 128, height: 128),
            anchor: PetPackAnchor(x: 0.5, y: 1.0),
            animations: [:],
            sourceActions: sourceActions
        )

        do {
            try writeSourceActionFrames(for: pack, to: root)
            let record = PetPackRecord(pack: pack, rootURL: root, isBundled: false)
            let actions = record.randomizableSourceActions(
                for: .quietCompanion,
                mappedSourceActionID: "action8"
            )
            let actionIDs = actions.map(\.id)
            let expectedLoopIDs = Set(sourceActions.filter(\.loop).map(\.id))
            return actionIDs.first == "action8"
                && Set(actionIDs) == expectedLoopIDs
                && !actionIDs.contains("wave")
                && actions.count == expectedLoopIDs.count
        } catch {
            return false
        }
    }

    private func importablePack(id: String, name: String) -> PetPack {
        PetPack(
            schemaVersion: 1,
            id: id,
            name: name,
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
    }

    private func writeImportablePack(_ pack: PetPack, to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(pack).write(to: root.appendingPathComponent("pet.json"))
        try Data([0]).write(to: root.appendingPathComponent("preview.png"))
        for animation in pack.animations.values {
            let folder = root.appendingPathComponent(animation.folder, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([0]).write(to: folder.appendingPathComponent("000.png"))
        }
    }

    private func writeSourceActionFrames(for pack: PetPack, to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for action in pack.sourceActions {
            let folder = root.appendingPathComponent(action.folder, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([0]).write(to: folder.appendingPathComponent("000.png"))
        }
    }

    private func archiveDirectory(_ directory: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", directory.path, archive.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PetPackImportError.archiveExtractionFailed("ditto 退出码 \(process.terminationStatus)")
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
    precondition(probe.manifestDecodesOptionalActionAudio(), "pet pack manifest should decode optional action audio")
    precondition(probe.libraryImportsValidPack(), "pet pack library should import valid local packs")
    precondition(probe.libraryImportsMultiPackZip(), "pet pack library should import a zip containing multiple packs")
    precondition(probe.libraryImportsSinglePackZip(), "pet pack library should import a zip containing one pack")
    precondition(probe.libraryDeletesImportedPack(), "pet pack library should delete imported packs")
    precondition(probe.catalogEmptyAfterDeletingEveryImportedPack(), "pet pack catalog should be empty after every imported pack is deleted")
    precondition(probe.playableActionsDeduplicateIdenticalFolders(), "playable action list should hide duplicate render folders")
    precondition(probe.randomizableActionsIncludeEveryPlayableLoopAction(), "random action list should include every playable looping source action")
}()

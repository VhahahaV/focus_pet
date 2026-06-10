import Foundation
@testable import FocusPetCore

struct PetPackTests {
    func actionFallbackUsesAliasBeforeIdle() -> Bool {
        let pack = PetPack(
            schemaVersion: 1,
            id: "alias_pack",
            name: "Alias Pack",
            source: .userImported,
            distribution: .localOnly,
            style: nil,
            license: nil,
            defaultSize: PetPackSize(width: 128, height: 128),
            defaultScale: 1,
            anchor: .dockAttached,
            hitBox: nil,
            animations: [
                .idle: PetAnimationSpec(folder: "idle", fps: 6, loop: true, frameCount: nil, renderer: .pngSequence),
                .shakeHead: PetAnimationSpec(folder: "shake", fps: 8, loop: false, frameCount: nil, renderer: .pngSequence)
            ],
            actionAliases: [.nudgeDistracted: .shakeHead]
        )

        return pack.animationKey(for: .nudgeDistracted) == .shakeHead
    }

    func actionFallbackUsesIdleThenSleepingThenFirstAnimation() -> Bool {
        let idlePack = PetPack.minimumForTest(id: "idle", animations: [.idle: "idle"])
        guard idlePack.animationKey(for: .welcomeBack) == .idle else { return false }

        let sleepingPack = PetPack.minimumForTest(id: "sleeping", animations: [.sleeping: "sleeping"])
        guard sleepingPack.animationKey(for: .welcomeBack) == .sleeping else { return false }

        let firstPack = PetPack.minimumForTest(id: "first", animations: [.stretch: "stretch"])
        return firstPack.animationKey(for: .welcomeBack) == .stretch
    }

    func validatorRejectsMissingManifest() -> Bool {
        withTemporaryDirectory { root in
            let result = PetPackValidator().validate(rootURL: root)
            return !result.isValid && result.errors.contains(.missingManifest)
        }
    }

    func validatorAllowsWarningsWhenPlayableFramesExist() throws -> Bool {
        try withTemporaryDirectory { root in
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("idle"),
                withIntermediateDirectories: true
            )
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appendingPathComponent("idle/000.png"))
            let manifest = """
            {
              "schemaVersion": 1,
              "id": "warning_pack",
              "name": "Warning Pack",
              "source": "userImported",
              "distribution": "localOnly",
              "license": {"type": "unknown"},
              "defaultSize": {"width": 128, "height": 128},
              "defaultScale": 1.0,
              "anchor": "dockAttached",
              "animations": {
                "idle": {"folder": "idle", "fps": 8, "loop": true}
              }
            }
            """
            try manifest.data(using: .utf8)!.write(to: root.appendingPathComponent("pet.json"))

            let result = PetPackValidator().validate(rootURL: root)
            return result.isValid
                && result.warnings.contains(.missingPreview)
                && result.warnings.contains(.unknownLicense)
        }
    }
}

private let runPetPackRegressionProbe: Void = {
    let probe = PetPackTests()
    precondition(
        probe.actionFallbackUsesAliasBeforeIdle(),
        "PetPack should resolve explicit aliases before idle fallback"
    )
    precondition(
        probe.actionFallbackUsesIdleThenSleepingThenFirstAnimation(),
        "PetPack should fall back to idle, sleeping, then first available animation"
    )
    precondition(
        probe.validatorRejectsMissingManifest(),
        "PetPackValidator should reject missing pet.json"
    )
    precondition(
        (try? probe.validatorAllowsWarningsWhenPlayableFramesExist()) == true,
        "PetPackValidator should allow warnings when playable frames exist"
    )
}()

private extension PetPack {
    static func minimumForTest(id: String, animations: [PetAnimationKey: String]) -> PetPack {
        PetPack(
            schemaVersion: 1,
            id: id,
            name: id,
            source: .userImported,
            distribution: .localOnly,
            style: nil,
            license: nil,
            defaultSize: PetPackSize(width: 128, height: 128),
            defaultScale: 1,
            anchor: .dockAttached,
            hitBox: nil,
            animations: animations.mapValues {
                PetAnimationSpec(folder: $0, fps: 8, loop: true, frameCount: nil, renderer: .pngSequence)
            },
            actionAliases: [:]
        )
    }
}

private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}

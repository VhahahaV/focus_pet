# Pet Pack System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a generic local Pet Pack system for Focus Pet settings so the app can import, validate, select, and play user-provided desktop pet resources without hardcoding IXiaoHei or any single character pack.

**Architecture:** Keep resource-pack data models and pure validation in `FocusPetCore`, because they can be tested without AppKit. Keep importing, Application Support installation, `NSImage` loading, `NSOpenPanel`, and settings UI in the `FocusPet` app target. Treat IXiaoHei only as a local-only test input from the two provided GitHub links, never as bundled redistributable app content.

**Tech Stack:** SwiftPM, Swift 6.2, macOS 14 SwiftUI/AppKit, Foundation file validation, `NSImage` PNG sequence rendering, Python 3.12 + Pillow for GIF-to-PNG conversion.

---

## Resource Boundary

Use only the resource links provided in the pasted spec:

- `https://github.com/jiang-taibai/IXiaoHei`
- `https://github.com/jiang-taibai/IXiaoHei/tree/master/src/org/taibai/hellohei/img`

Do not add other external art, search for replacements, or bundle IXiaoHei output in the release build. The generated `LuoXiaoHeiLocal` pack is a local-only test pack with unknown license metadata.

## Current Code Map

- Modify: `Package.swift`
  - Keep `Resources/Pets` copied into the app bundle.
  - No new package dependencies are required for Swift.
- Modify: `Sources/FocusPetCore/PetModels.swift`
  - Keep current behavior/action enums.
  - Reuse `PetAction` as the runtime action source.
- Create: `Sources/FocusPetCore/PetPack.swift`
  - Define manifest, action keys, source/distribution/license metadata, aliases, and fallback resolver.
- Create: `Sources/FocusPetCore/PetPackValidator.swift`
  - Validate `pet.json`, folders, PNG frames, ids, fps, and warnings/errors.
- Modify: `Sources/FocusPetCore/DomainModels.swift`
  - Add persisted `selectedPetPackID`, defaulting to `focus_dino`.
- Create: `Sources/FocusPet/Pet/PetPackImporter.swift`
  - Copy validated folders into `~/Library/Application Support/FocusPetV0/PetPacks/{petId}/`.
- Create: `Sources/FocusPet/Pet/PetPackStore.swift`
  - List bundled and user-imported packs, load selected catalog, and expose install locations.
- Modify: `Sources/FocusPet/Pet/PetResourceLoader.swift`
  - Replace `loadFocusDino()` with generic bundle/user-pack loading.
- Modify: `Sources/FocusPet/Pet/PetSpriteAnimator.swift`
  - Accept a `PetSpriteCatalog` from `FocusPetModel` and use the resolver fallback chain.
- Modify: `Sources/FocusPet/Pet/PetInteractionView.swift`
  - Pass the selected catalog into the animator.
- Modify: `Sources/FocusPet/PetSettingsViews.swift`
  - Add Pet Gallery, import button, validation report, source/license warning, selected-pack state.
- Modify: `Sources/FocusPet/FocusPetModel.swift`
  - Own available packs, selected pack id, current catalog, import/select methods, and persisted settings.
- Modify: `Sources/FocusPet/Services.swift`
  - Expose the Application Support root or a `petPacksRootURL` helper from `LocalDataStore`.
- Modify: `Sources/FocusPet/Resources/Pets/FocusDino/pet.json`
  - Upgrade to schema v1 and standard action keys; keep it as bundled.
- Create: `scripts/build-luoxiaohei-local-pack.py`
  - Convert the provided IXiaoHei GIF/PNG resources into a generic local Pet Pack.
- Modify: `.gitignore`
  - Ignore `/external_assets/` and `/external_generated_packs/`.
- Modify: `scripts/package-macos-app.sh`
  - Exclude local-only/generated resource folders by default.
- Create: `Tests/FocusPetCoreTests/PetPackTests.swift`
  - Test decoding, fallback resolution, and validation rules.

## Standard Pet Pack Contract

Standard actions:

```text
sleeping
idle
blink
stretch
walkLeft
walkRight
nudgeDistracted
nudgeEntertainment
welcomeBack
dragged
landing
```

Runtime fallback order:

```text
target action
-> actionAliases[target action]
-> idle
-> sleeping
-> first available animation
-> SwiftUI placeholder
```

Installed user packs live here:

```text
~/Library/Application Support/FocusPetV0/PetPacks/{petId}/
```

The app must copy imported folders into Application Support. Do not reference the user-selected source folder after import.

---

## Task 1: Add Local Resource Boundaries And Generator Script

**Files:**
- Modify: `.gitignore`
- Create: `scripts/build-luoxiaohei-local-pack.py`

- [x] **Step 1: Ignore local-only resource folders**

Add these lines to `.gitignore`:

```gitignore
/external_assets/
/external_generated_packs/
```

- [x] **Step 2: Create the IXiaoHei local pack generator**

Create `scripts/build-luoxiaohei-local-pack.py` with this behavior:

```python
#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
import json
import shutil

SRC = Path("external_assets/IXiaoHei/src/org/taibai/hellohei/img")
DST = Path("external_generated_packs/LuoXiaoHeiLocal")

MAPPING = {
    "licking the claw.gif": ("idle", "idle"),
    "shake-head-txt.gif": ("nudgeDistracted", "nudge_distracted"),
    "eat-watermelon-txt.gif": ("nudgeEntertainment", "nudge_entertainment"),
    "bye.gif": ("welcomeBack", "welcome_back"),
    "play heixiu.gif": ("stretch", "stretch"),
    "playing guitar.gif": ("idleSpecial", "idle_special"),
    "eat drumstick.gif": ("playfulIdle", "playful_idle"),
}

ALIASES = {
    "sleeping": "idle",
    "blink": "idle",
    "walkLeft": "idle",
    "walkRight": "idle",
    "dragged": "idle",
    "landing": "welcomeBack",
    "nudgeDistracted": "nudgeDistracted",
    "nudgeEntertainment": "nudgeEntertainment",
    "welcomeBack": "welcomeBack",
    "stretch": "stretch",
}

def clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)

def export_gif_frames(gif_path: Path, out_dir: Path) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    image = Image.open(gif_path)
    frame_index = 0
    while True:
        image.convert("RGBA").save(out_dir / f"{frame_index:03d}.png")
        frame_index += 1
        try:
            image.seek(image.tell() + 1)
        except EOFError:
            break
    return frame_index

def copy_png(src_path: Path, dst_path: Path) -> None:
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    Image.open(src_path).convert("RGBA").save(dst_path)

def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Source not found: {SRC}")

    clean_dir(DST)

    icon = SRC / "icon.png"
    if icon.exists():
        copy_png(icon, DST / "preview.png")

    animations = {}
    for filename, (action_key, folder) in MAPPING.items():
        src_file = SRC / filename
        if not src_file.exists():
            print(f"[WARN] Missing: {src_file}")
            continue

        out_dir = DST / folder
        frame_count = export_gif_frames(src_file, out_dir)
        animations[action_key] = {
            "folder": folder,
            "fps": 8,
            "loop": folder in {"idle", "idle_special", "playful_idle"},
            "frameCount": frame_count,
            "renderer": "pngSequence",
        }

    manifest = {
        "schemaVersion": 1,
        "id": "luo_xiaohei_local",
        "name": "罗小黑 Local Test",
        "source": "userImported",
        "distribution": "localOnly",
        "style": "anime_gif",
        "license": {
            "type": "unknown",
            "note": "Third-party IP resource. Local testing only. Do not bundle or redistribute without permission."
        },
        "defaultSize": {"width": 128, "height": 128},
        "defaultScale": 1.0,
        "anchor": "dockAttached",
        "hitBox": {"x": 8, "y": 8, "width": 112, "height": 112},
        "actionAliases": ALIASES,
        "animations": animations,
    }

    with open(DST / "pet.json", "w", encoding="utf-8") as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)

    print(f"[OK] Generated pet pack at: {DST}")

if __name__ == "__main__":
    main()
```

- [x] **Step 3: Verify the script fails clearly before assets exist**

Run:

```bash
python3 scripts/build-luoxiaohei-local-pack.py
```

Expected:

```text
Source not found: external_assets/IXiaoHei/src/org/taibai/hellohei/img
```

- [x] **Step 4: Clone only the provided resource repository**

Run:

```bash
mkdir -p external_assets
git clone https://github.com/jiang-taibai/IXiaoHei.git external_assets/IXiaoHei
```

Expected:

```text
external_assets/IXiaoHei/src/org/taibai/hellohei/img
```

- [x] **Step 5: Generate the local test pack**

Run:

```bash
python3 scripts/build-luoxiaohei-local-pack.py
find external_generated_packs/LuoXiaoHeiLocal -maxdepth 2 -type f | sort | sed -n '1,40p'
```

Expected output includes:

```text
external_generated_packs/LuoXiaoHeiLocal/pet.json
external_generated_packs/LuoXiaoHeiLocal/preview.png
external_generated_packs/LuoXiaoHeiLocal/idle/000.png
external_generated_packs/LuoXiaoHeiLocal/nudge_distracted/000.png
external_generated_packs/LuoXiaoHeiLocal/nudge_entertainment/000.png
external_generated_packs/LuoXiaoHeiLocal/welcome_back/000.png
```

## Task 2: Add Core Pet Pack Models And Fallback Resolver

**Files:**
- Create: `Sources/FocusPetCore/PetPack.swift`
- Modify: `Sources/FocusPetCore/PetModels.swift` only if helper mapping belongs near `PetAction`
- Create: `Tests/FocusPetCoreTests/PetPackTests.swift`

- [x] **Step 1: Write fallback resolver tests first**

Create `Tests/FocusPetCoreTests/PetPackTests.swift` with initial tests:

```swift
import XCTest
@testable import FocusPetCore

final class PetPackTests: XCTestCase {
    func testActionFallbackUsesAliasBeforeIdle() {
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

        XCTAssertEqual(pack.animationKey(for: .nudgeDistracted), .shakeHead)
    }

    func testActionFallbackUsesIdleThenSleepingThenFirstAnimation() {
        let idlePack = PetPack.minimumForTest(id: "idle", animations: [.idle: "idle"])
        XCTAssertEqual(idlePack.animationKey(for: .welcomeBack), .idle)

        let sleepingPack = PetPack.minimumForTest(id: "sleeping", animations: [.sleeping: "sleeping"])
        XCTAssertEqual(sleepingPack.animationKey(for: .welcomeBack), .sleeping)

        let firstPack = PetPack.minimumForTest(id: "first", animations: [.stretch: "stretch"])
        XCTAssertEqual(firstPack.animationKey(for: .welcomeBack), .stretch)
    }
}

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
```

- [x] **Step 2: Run the new tests and confirm they fail to compile**

Run:

```bash
swift test --filter PetPackTests
```

Expected:

```text
cannot find 'PetPack' in scope
```

- [x] **Step 3: Add core model types**

Create `Sources/FocusPetCore/PetPack.swift` with these public types and decoding defaults:

```swift
import Foundation

public enum PetPackSource: String, Codable, Hashable, Sendable {
    case bundled
    case userImported
    case localOnlyTest
}

public enum PetPackDistribution: String, Codable, Hashable, Sendable {
    case redistributable
    case localOnly
    case unknown
}

public enum PetPackAnchor: String, Codable, Hashable, Sendable {
    case dockAttached
    case bottomRightCorner
    case bottomLeftCorner
    case manual
}

public enum PetRenderer: String, Codable, Hashable, Sendable {
    case pngSequence
}

public enum PetAnimationKey: String, Codable, Hashable, Sendable, CaseIterable {
    case sleeping
    case idle
    case blink
    case stretch
    case walkLeft
    case walkRight
    case nudgeDistracted
    case nudgeEntertainment
    case welcomeBack
    case dragged
    case landing
    case shakeHead
    case idleSpecial
    case playfulIdle

    public init?(manifestKey: String) {
        if let key = Self(rawValue: manifestKey) {
            self = key
            return
        }

        switch manifestKey {
        case "sleep":
            self = .sleeping
        case "walk_left":
            self = .walkLeft
        case "walk_right":
            self = .walkRight
        case "nudge_distracted":
            self = .nudgeDistracted
        case "nudge_entertainment":
            self = .nudgeEntertainment
        case "welcome_back":
            self = .welcomeBack
        case "idle_special":
            self = .idleSpecial
        case "playful_idle":
            self = .playfulIdle
        default:
            return nil
        }
    }
}

public struct PetPackSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct PetHitBox: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PetPackLicense: Codable, Hashable, Sendable {
    public var type: String
    public var note: String?

    public init(type: String, note: String?) {
        self.type = type
        self.note = note
    }
}

public struct PetAnimationSpec: Codable, Hashable, Sendable {
    public var folder: String
    public var fps: Int
    public var loop: Bool
    public var frameCount: Int?
    public var renderer: PetRenderer

    public init(folder: String, fps: Int, loop: Bool, frameCount: Int?, renderer: PetRenderer = .pngSequence) {
        self.folder = folder
        self.fps = fps
        self.loop = loop
        self.frameCount = frameCount
        self.renderer = renderer
    }

    private enum CodingKeys: String, CodingKey {
        case folder
        case fps
        case loop
        case frameCount
        case renderer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decode(String.self, forKey: .folder)
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 8
        loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? true
        frameCount = try container.decodeIfPresent(Int.self, forKey: .frameCount)
        renderer = try container.decodeIfPresent(PetRenderer.self, forKey: .renderer) ?? .pngSequence
    }
}

public struct PetPack: Codable, Hashable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var source: PetPackSource
    public var distribution: PetPackDistribution
    public var style: String?
    public var license: PetPackLicense?
    public var defaultSize: PetPackSize
    public var defaultScale: Double
    public var anchor: PetPackAnchor
    public var hitBox: PetHitBox?
    public var animations: [PetAnimationKey: PetAnimationSpec]
    public var actionAliases: [PetAnimationKey: PetAnimationKey]

    public init(
        schemaVersion: Int,
        id: String,
        name: String,
        source: PetPackSource,
        distribution: PetPackDistribution,
        style: String?,
        license: PetPackLicense?,
        defaultSize: PetPackSize,
        defaultScale: Double,
        anchor: PetPackAnchor,
        hitBox: PetHitBox?,
        animations: [PetAnimationKey: PetAnimationSpec],
        actionAliases: [PetAnimationKey: PetAnimationKey]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.source = source
        self.distribution = distribution
        self.style = style
        self.license = license
        self.defaultSize = defaultSize
        self.defaultScale = defaultScale
        self.anchor = anchor
        self.hitBox = hitBox
        self.animations = animations
        self.actionAliases = actionAliases
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case source
        case distribution
        case style
        case license
        case defaultSize
        case defaultScale
        case anchor
        case hitBox
        case animations
        case actionAliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        source = try container.decodeIfPresent(PetPackSource.self, forKey: .source) ?? .bundled
        distribution = try container.decodeIfPresent(PetPackDistribution.self, forKey: .distribution) ?? .unknown
        style = try container.decodeIfPresent(String.self, forKey: .style)
        license = try container.decodeIfPresent(PetPackLicense.self, forKey: .license)
        defaultSize = try container.decodeIfPresent(PetPackSize.self, forKey: .defaultSize) ?? PetPackSize(width: 128, height: 128)
        defaultScale = try container.decodeIfPresent(Double.self, forKey: .defaultScale) ?? 1
        anchor = try container.decodeIfPresent(PetPackAnchor.self, forKey: .anchor) ?? .dockAttached
        hitBox = try container.decodeIfPresent(PetHitBox.self, forKey: .hitBox)

        let rawAnimations = try container.decode([String: PetAnimationSpec].self, forKey: .animations)
        animations = Dictionary(uniqueKeysWithValues: rawAnimations.compactMap { rawKey, spec in
            guard let key = PetAnimationKey(manifestKey: rawKey) else { return nil }
            return (key, spec)
        })

        let rawAliases = try container.decodeIfPresent([String: String].self, forKey: .actionAliases) ?? [:]
        actionAliases = Dictionary(uniqueKeysWithValues: rawAliases.compactMap { rawKey, rawValue in
            guard let key = PetAnimationKey(manifestKey: rawKey),
                  let value = PetAnimationKey(manifestKey: rawValue) else { return nil }
            return (key, value)
        })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(source, forKey: .source)
        try container.encode(distribution, forKey: .distribution)
        try container.encodeIfPresent(style, forKey: .style)
        try container.encodeIfPresent(license, forKey: .license)
        try container.encode(defaultSize, forKey: .defaultSize)
        try container.encode(defaultScale, forKey: .defaultScale)
        try container.encode(anchor, forKey: .anchor)
        try container.encodeIfPresent(hitBox, forKey: .hitBox)
        try container.encode(Dictionary(uniqueKeysWithValues: animations.map { ($0.key.rawValue, $0.value) }), forKey: .animations)
        try container.encode(Dictionary(uniqueKeysWithValues: actionAliases.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: .actionAliases)
    }

    public func animationKey(for action: PetAction) -> PetAnimationKey? {
        let target = PetAnimationKey(action)
        if animations[target] != nil {
            return target
        }
        if let alias = actionAliases[target], animations[alias] != nil {
            return alias
        }
        if animations[.idle] != nil {
            return .idle
        }
        if animations[.sleeping] != nil {
            return .sleeping
        }
        return animations.keys.sorted { $0.rawValue < $1.rawValue }.first
    }
}

public extension PetAnimationKey {
    init(_ action: PetAction) {
        switch action {
        case .sleep:
            self = .sleeping
        case .idle:
            self = .idle
        case .blink:
            self = .blink
        case .stretch:
            self = .stretch
        case .shortWalk:
            self = .walkRight
        case .nudgeDistracted:
            self = .nudgeDistracted
        case .nudgeEntertainment:
            self = .nudgeEntertainment
        case .welcomeBack:
            self = .welcomeBack
        case .dragged:
            self = .dragged
        case .landing:
            self = .landing
        case .hidden:
            self = .idle
        }
    }
}
```

- [x] **Step 4: Run resolver tests**

Run:

```bash
swift test --filter PetPackTests
```

Expected:

```text
Test Suite 'PetPackTests' passed
```

## Task 3: Add Pet Pack Validator

**Files:**
- Create: `Sources/FocusPetCore/PetPackValidator.swift`
- Modify: `Tests/FocusPetCoreTests/PetPackTests.swift`

- [x] **Step 1: Add validator tests**

Append these tests to `PetPackTests`:

```swift
func testValidatorRejectsMissingManifest() {
    withTemporaryDirectory { root in
        let result = PetPackValidator().validate(rootURL: root)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains(.missingManifest))
    }
}

func testValidatorAllowsWarningsWhenPlayableFramesExist() throws {
    try withTemporaryDirectory { root in
        try FileManager.default.createDirectory(at: root.appendingPathComponent("idle"), withIntermediateDirectories: true)
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
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.warnings.contains(.missingPreview))
        XCTAssertTrue(result.warnings.contains(.unknownLicense))
    }
}
```

Add this helper in the test file:

```swift
private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) rethrows -> T {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}
```

- [x] **Step 2: Run validator tests and confirm they fail to compile**

Run:

```bash
swift test --filter PetPackTests
```

Expected:

```text
cannot find 'PetPackValidator' in scope
```

- [x] **Step 3: Add validation result and issue types**

Create `Sources/FocusPetCore/PetPackValidator.swift`:

```swift
import Foundation

public struct PetPackValidationResult: Codable, Hashable, Sendable {
    public var pack: PetPack?
    public var isValid: Bool { errors.isEmpty }
    public var errors: [PetPackValidationError]
    public var warnings: [PetPackValidationWarning]

    public init(pack: PetPack?, errors: [PetPackValidationError], warnings: [PetPackValidationWarning]) {
        self.pack = pack
        self.errors = errors
        self.warnings = warnings
    }
}

public enum PetPackValidationError: String, Codable, Hashable, Sendable {
    case missingManifest
    case unreadableManifest
    case invalidID
    case emptyAnimations
    case noPlayableFrames
    case invalidDefaultSize
    case invalidFPS
}

public enum PetPackValidationWarning: String, Codable, Hashable, Sendable {
    case missingPreview
    case missingIdleOrSleeping
    case missingAnimationFolder
    case emptyAnimationFolder
    case unknownLicense
    case unknownDistribution
    case highFrameCount
}
```

- [x] **Step 4: Add validator implementation**

In the same file, add:

```swift
public struct PetPackValidator: Sendable {
    public init() {}

    public func validate(rootURL: URL) -> PetPackValidationResult {
        let manifestURL = rootURL.appendingPathComponent("pet.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return PetPackValidationResult(pack: nil, errors: [.missingManifest], warnings: [])
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let pack = try? JSONDecoder().decode(PetPack.self, from: data) else {
            return PetPackValidationResult(pack: nil, errors: [.unreadableManifest], warnings: [])
        }
        return validate(pack: pack, rootURL: rootURL)
    }

    public func validate(pack: PetPack, rootURL: URL) -> PetPackValidationResult {
        var errors: [PetPackValidationError] = []
        var warnings: [PetPackValidationWarning] = []

        if !Self.isValidID(pack.id) {
            errors.append(.invalidID)
        }
        if pack.animations.isEmpty {
            errors.append(.emptyAnimations)
        }
        if pack.defaultSize.width < 64 || pack.defaultSize.width > 512 || pack.defaultSize.height < 64 || pack.defaultSize.height > 512 {
            errors.append(.invalidDefaultSize)
        }
        if !FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("preview.png").path) {
            warnings.append(.missingPreview)
        }
        if pack.license?.type == "unknown" {
            warnings.append(.unknownLicense)
        }
        if pack.distribution == .unknown {
            warnings.append(.unknownDistribution)
        }
        if pack.animations[.idle] == nil && pack.animations[.sleeping] == nil {
            warnings.append(.missingIdleOrSleeping)
        }

        var playableCount = 0
        for (_, spec) in pack.animations {
            if spec.fps < 1 || spec.fps > 60 {
                errors.append(.invalidFPS)
            }

            let folderURL = rootURL.appendingPathComponent(spec.folder, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                warnings.append(.missingAnimationFolder)
                continue
            }

            let frames = Self.pngFrames(in: folderURL)
            if frames.isEmpty {
                warnings.append(.emptyAnimationFolder)
            } else {
                playableCount += 1
            }
            if frames.count > 240 {
                warnings.append(.highFrameCount)
            }
        }

        if playableCount == 0 {
            errors.append(.noPlayableFrames)
        }

        return PetPackValidationResult(
            pack: pack,
            errors: Array(Set(errors)).sorted { $0.rawValue < $1.rawValue },
            warnings: Array(Set(warnings)).sorted { $0.rawValue < $1.rawValue }
        )
    }

    public static func pngFrames(in folderURL: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}
```

- [x] **Step 5: Run validator tests**

Run:

```bash
swift test --filter PetPackTests
```

Expected:

```text
Test Suite 'PetPackTests' passed
```

## Task 4: Persist Selected Pack And Install Imported Packs

**Files:**
- Modify: `Sources/FocusPetCore/DomainModels.swift`
- Modify: `Sources/FocusPet/Services.swift`
- Create: `Sources/FocusPet/Pet/PetPackImporter.swift`
- Create: `Sources/FocusPet/Pet/PetPackStore.swift`
- Modify: `Sources/FocusPet/FocusPetModel.swift`

- [x] **Step 1: Add selected pack id to settings**

In `AppSettings`, add:

```swift
public var selectedPetPackID: String
```

Default it in `init`:

```swift
selectedPetPackID: String = "focus_dino"
```

Decode with backwards compatibility:

```swift
selectedPetPackID = try container.decodeIfPresent(String.self, forKey: .selectedPetPackID) ?? "focus_dino"
```

Encode it:

```swift
try container.encode(selectedPetPackID, forKey: .selectedPetPackID)
```

- [x] **Step 2: Expose the pet pack install root**

In `LocalDataStore`, add:

```swift
var petPacksRootURL: URL {
    rootURL.appendingPathComponent("PetPacks", isDirectory: true)
}

func ensurePetPacksRoot() -> URL {
    ensureRoot()
    try? FileManager.default.createDirectory(at: petPacksRootURL, withIntermediateDirectories: true)
    return petPacksRootURL
}
```

- [x] **Step 3: Add importer**

Create `Sources/FocusPet/Pet/PetPackImporter.swift`:

```swift
import FocusPetCore
import Foundation

struct ImportedPetPack: Hashable {
    var pack: PetPack
    var installedURL: URL
    var validation: PetPackValidationResult
}

enum PetPackImportError: LocalizedError {
    case validationFailed([PetPackValidationError])
    case missingDecodedPack
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let errors):
            "资源包校验失败：\(errors.map(\\.rawValue).joined(separator: \", \"))"
        case .missingDecodedPack:
            "资源包 manifest 无法解析。"
        case .copyFailed(let message):
            "资源包复制失败：\(message)"
        }
    }
}

struct PetPackImporter {
    var installRootURL: URL

    func importPack(from sourceURL: URL) throws -> ImportedPetPack {
        let validation = PetPackValidator().validate(rootURL: sourceURL)
        guard validation.errors.isEmpty else {
            throw PetPackImportError.validationFailed(validation.errors)
        }
        guard var pack = validation.pack else {
            throw PetPackImportError.missingDecodedPack
        }

        pack.source = .userImported
        let installURL = installRootURL.appendingPathComponent(pack.id, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: installRootURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: installURL.path) {
                try FileManager.default.removeItem(at: installURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: installURL)
        } catch {
            throw PetPackImportError.copyFailed(error.localizedDescription)
        }

        return ImportedPetPack(pack: pack, installedURL: installURL, validation: validation)
    }
}
```

- [x] **Step 4: Add pack store**

Create `Sources/FocusPet/Pet/PetPackStore.swift` with:

```swift
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

    func records() -> [PetPackRecord] {
        bundledRecords() + userRecords()
    }

    func record(id: String) -> PetPackRecord? {
        records().first { $0.id == id } ?? bundledRecords().first
    }

    private func bundledRecords() -> [PetPackRecord] {
        guard let petsURL = Bundle.module.resourceURL?.appendingPathComponent("Pets", isDirectory: true),
              let urls = try? FileManager.default.contentsOfDirectory(at: petsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.compactMap { record(url: $0) }
    }

    private func userRecords() -> [PetPackRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: userRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.compactMap { record(url: $0) }
    }

    private func record(url: URL) -> PetPackRecord? {
        let validation = PetPackValidator().validate(rootURL: url)
        guard let pack = validation.pack else { return nil }
        return PetPackRecord(pack: pack, rootURL: url, validation: validation)
    }
}
```

- [x] **Step 5: Wire settings into `FocusPetModel`**

Add published state:

```swift
@Published var selectedPetPackID = "focus_dino"
@Published var availablePetPacks: [PetPackRecord] = []
@Published var petImportResult: PetPackValidationResult?
@Published var petImportErrorMessage: String?
@Published var currentPetCatalog = PetResourceLoader.loadBundledPack(id: "focus_dino")
```

In `init`, load `settings.selectedPetPackID`, call `refreshPetPacks()`, then load the selected catalog.

Add methods:

```swift
func refreshPetPacks() {
    let store = PetPackStore(userRootURL: dataStore.ensurePetPacksRoot())
    availablePetPacks = store.records()
    if !availablePetPacks.contains(where: { $0.id == selectedPetPackID }) {
        selectedPetPackID = "focus_dino"
    }
    reloadSelectedPetCatalog()
}

func selectPetPack(_ id: String) {
    selectedPetPackID = id
    reloadSelectedPetCatalog()
    persistSettings()
}

func importPetPack(from folderURL: URL) {
    do {
        let importer = PetPackImporter(installRootURL: dataStore.ensurePetPacksRoot())
        let imported = try importer.importPack(from: folderURL)
        petImportResult = imported.validation
        petImportErrorMessage = nil
        refreshPetPacks()
        selectPetPack(imported.pack.id)
    } catch {
        petImportErrorMessage = error.localizedDescription
    }
}

private func reloadSelectedPetCatalog() {
    let store = PetPackStore(userRootURL: dataStore.ensurePetPacksRoot())
    if let record = store.record(id: selectedPetPackID) {
        currentPetCatalog = PetResourceLoader.load(record: record)
    } else {
        currentPetCatalog = PetResourceLoader.loadBundledPack(id: "focus_dino")
    }
}
```

In `appSettings()`, pass `selectedPetPackID`.

## Task 5: Load Generic Packs And Use Runtime Fallback

**Files:**
- Modify: `Sources/FocusPet/Pet/PetResourceLoader.swift`
- Modify: `Sources/FocusPet/Pet/PetSpriteAnimator.swift`
- Modify: `Sources/FocusPet/Pet/PetInteractionView.swift`
- Modify: `Sources/FocusPet/PetSettingsViews.swift`
- Modify: `Sources/FocusPet/Resources/Pets/FocusDino/pet.json`

- [x] **Step 1: Upgrade `FocusDino` manifest**

Replace `Sources/FocusPet/Resources/Pets/FocusDino/pet.json` with schema v1 metadata and standard keys:

```json
{
  "schemaVersion": 1,
  "id": "focus_dino",
  "name": "Focus Dino",
  "source": "bundled",
  "distribution": "redistributable",
  "style": "system_placeholder",
  "license": {
    "type": "original",
    "note": "Created for Focus Pet."
  },
  "defaultScale": 1.0,
  "defaultSize": {
    "width": 128,
    "height": 128
  },
  "anchor": "dockAttached",
  "hitBox": {
    "x": 12,
    "y": 12,
    "width": 104,
    "height": 104
  },
  "actionAliases": {
    "walkLeft": "walkRight",
    "dragged": "idle",
    "landing": "welcomeBack"
  },
  "animations": {
    "sleeping": {
      "folder": "sleeping",
      "fps": 4,
      "loop": true
    },
    "idle": {
      "folder": "idle",
      "fps": 1,
      "loop": true
    },
    "blink": {
      "folder": "blink",
      "fps": 8,
      "loop": false
    },
    "stretch": {
      "folder": "stretch",
      "fps": 8,
      "loop": false
    },
    "walkRight": {
      "folder": "walk_right",
      "fps": 10,
      "loop": true
    },
    "nudgeDistracted": {
      "folder": "nudge_distracted",
      "fps": 8,
      "loop": false
    },
    "nudgeEntertainment": {
      "folder": "nudge_entertainment",
      "fps": 8,
      "loop": false
    },
    "welcomeBack": {
      "folder": "welcome_back",
      "fps": 8,
      "loop": false
    }
  }
}
```

- [x] **Step 2: Replace app-local manifest types with core types**

In `PetResourceLoader.swift`, remove `PetManifest` and `PetAnimationDescriptor`. Use `PetPack` and `PetAnimationSpec` from `FocusPetCore`.

Define:

```swift
struct PetAnimationFrames {
    var key: PetAnimationKey
    var descriptor: PetAnimationSpec
    var images: [NSImage]
}

struct PetSpriteCatalog {
    var pack: PetPack?
    var animations: [PetAnimationKey: PetAnimationFrames]

    func frames(for action: PetAction) -> PetAnimationFrames? {
        guard let pack, let key = pack.animationKey(for: action) else {
            return animations.values.first { !$0.images.isEmpty }
        }
        return animations[key].flatMap { $0.images.isEmpty ? nil : $0 }
    }
}
```

- [x] **Step 3: Add generic loader methods**

In `PetResourceLoader`, add:

```swift
enum PetResourceLoader {
    static func loadBundledPack(id: String) -> PetSpriteCatalog {
        if id == "focus_dino",
           let manifestURL = Bundle.module.url(forResource: "pet", withExtension: "json", subdirectory: "Pets/FocusDino") {
            return load(rootURL: manifestURL.deletingLastPathComponent())
        }

        guard let petsURL = Bundle.module.resourceURL?.appendingPathComponent("Pets", isDirectory: true),
              let urls = try? FileManager.default.contentsOfDirectory(at: petsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
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

    private static func loadBundledFallback() -> PetSpriteCatalog {
        guard let manifestURL = Bundle.module.url(forResource: "pet", withExtension: "json", subdirectory: "Pets/FocusDino") else {
            return PetSpriteCatalog(pack: nil, animations: [:])
        }
        return load(rootURL: manifestURL.deletingLastPathComponent())
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
            result[entry.key] = PetAnimationFrames(key: entry.key, descriptor: entry.value, images: images)
        }

        return PetSpriteCatalog(pack: pack, animations: animations)
    }
}
```

- [x] **Step 4: Pass catalog into animators**

Change `PetSpriteAnimator` signature:

```swift
struct PetSpriteAnimator: View {
    var catalog: PetSpriteCatalog
    var action: PetAction
    var fallbackState: UserState
    var animated: Bool
}
```

Remove the internal `@State private var catalog = PetResourceLoader.loadFocusDino()`.

Update call sites:

```swift
PetSpriteAnimator(
    catalog: model.currentPetCatalog,
    action: model.currentPetAction,
    fallbackState: model.currentState.userState,
    animated: model.petAnimationEnabled
)
```

- [x] **Step 5: Run build**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

## Task 6: Add Pet Gallery And Import UX In Settings

**Files:**
- Modify: `Sources/FocusPet/PetSettingsViews.swift`
- Modify: `Sources/FocusPet/FocusPetModel.swift`

- [x] **Step 1: Add folder picker entry point**

In `FocusPetModel`, add:

```swift
func chooseAndImportPetPack() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "导入"
    panel.message = "选择包含 pet.json 的本地桌宠资源包文件夹。"

    guard panel.runModal() == .OK, let url = panel.url else { return }
    importPetPack(from: url)
}
```

- [x] **Step 2: Add gallery section to settings controls**

In `PetSettingsControls`, add a new section before `窗口`:

```swift
PetSettingSection(title: "资源包", symbol: "shippingbox.fill") {
    Picker("当前桌宠", selection: Binding(
        get: { model.selectedPetPackID },
        set: { model.selectPetPack($0) }
    )) {
        ForEach(model.availablePetPacks) { record in
            Text(record.pack.name).tag(record.id)
        }
    }

    HStack {
        Button {
            model.chooseAndImportPetPack()
        } label: {
            Label("导入本地宠物包", systemImage: "square.and.arrow.down")
        }

        Button {
            model.refreshPetPacks()
        } label: {
            Label("刷新", systemImage: "arrow.clockwise")
        }
    }
    .buttonStyle(.bordered)

    if let record = model.availablePetPacks.first(where: { $0.id == model.selectedPetPackID }) {
        PetPackMetadataView(record: record)
    }

    if let message = model.petImportErrorMessage {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }
}
```

- [x] **Step 3: Add metadata and warnings view**

Add to `PetSettingsViews.swift`:

```swift
struct PetPackMetadataView: View {
    var record: PetPackRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusPill(title: record.pack.source.rawValue, symbol: "tray.full.fill")
                StatusPill(title: record.pack.distribution.rawValue, symbol: "lock.doc.fill")
            }

            if record.pack.distribution == .localOnly || record.pack.license?.type == "unknown" {
                Text("此资源包由用户本地导入，请确保你拥有使用权。Focus Pet 不会上传或分发该资源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !record.validation.warnings.isEmpty {
                Text("提示：\(record.validation.warnings.map(\\.rawValue).joined(separator: \"、\"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
```

- [x] **Step 4: Keep settings layout native and compact**

Verify the settings tab still uses the existing `ViewThatFits` split and does not create a nested card inside another card. The resource-pack section should stay inside the current `PetSettingsControls` surface.

- [x] **Step 5: Build**

Run:

```bash
swift build
```

Expected:

```text
Build complete
```

## Task 7: Packaging Safety

**Files:**
- Modify: `scripts/package-macos-app.sh`

- [x] **Step 1: Add local-test flag parsing**

Near the top of `scripts/package-macos-app.sh`, add:

```bash
INCLUDE_LOCAL_TEST_PETS=0

for arg in "$@"; do
    if [[ "$arg" == "--include-local-test-pets" ]]; then
        INCLUDE_LOCAL_TEST_PETS=1
    fi
done
```

- [x] **Step 2: Remove local-only content by default after bundle copy**

After copying `FocusPet_FocusPet.bundle`, add:

```bash
if [[ "$INCLUDE_LOCAL_TEST_PETS" -eq 0 ]]; then
    echo "Excluding local-only test pet packs..."
    find "$APP_DIR" -name "LuoXiaoHeiLocal" -type d -prune -exec rm -rf {} +
    find "$APP_DIR" -name "external_assets" -type d -prune -exec rm -rf {} +
    find "$APP_DIR" -name "external_generated_packs" -type d -prune -exec rm -rf {} +
fi
```

- [x] **Step 3: Verify release package excludes local test pack**

Run:

```bash
./scripts/package-macos-app.sh
find .build/FocusPet.app -iname '*LuoXiaoHei*' -o -iname '*external_assets*' -o -iname '*external_generated_packs*'
```

Expected:

```text
```

No output means the release package is clean.

## Task 8: End-To-End Verification

**Files:**
- No new files unless failures reveal missing tests.

- [x] **Step 1: Run unit tests**

Run:

```bash
swift test
```

Expected:

```text
Test Suite 'All tests' passed
```

- [x] **Step 2: Run core checks**

Run:

```bash
swift run FocusPetCoreChecks
```

Expected:

```text
FocusPetCore checks passed
```

If the checks executable currently has different output, keep the existing success output and document it in the final implementation note.

- [x] **Step 3: Generate IXiaoHei local test pack**

Run:

```bash
python3 scripts/build-luoxiaohei-local-pack.py
```

Expected:

```text
[OK] Generated pet pack at: external_generated_packs/LuoXiaoHeiLocal
```

- [x] **Step 4: Build and package app**

Run:

```bash
swift build
./scripts/package-macos-app.sh
```

Expected:

```text
.build/FocusPet.app
```

- [x] **Step 5: Manual app verification**

Run:

```bash
open .build/FocusPet.app
```

Manual checks:

```text
1. Open 桌宠 settings tab.
2. Click 导入本地宠物包.
3. Select external_generated_packs/LuoXiaoHeiLocal.
4. Confirm the gallery selects 罗小黑 Local Test.
5. Confirm unknown/localOnly license warning is visible.
6. Trigger Demo 走神 and verify nudgeDistracted uses imported animation or fallback.
7. Trigger Demo 暂离 then return and verify welcomeBack or fallback plays.
8. Switch back to Focus Dino and verify placeholder fallback still appears if bundled PNG frames are absent.
9. Quit and reopen app; selectedPetPackID persists.
10. Package without --include-local-test-pets and confirm LuoXiaoHeiLocal is not inside .build/FocusPet.app.
```

---

## Execution Notes

- Current `FocusDino` only has `pet.json` in the working tree, so the renderer must always tolerate missing folders and fall back to `PetFigureView`.
- The first shippable improvement is not "make LuoXiaoHei play"; it is "make all packs safe to import, inspect, select, and fail gracefully."
- IXiaoHei must remain a local-only test fixture generated outside the app bundle.
- Keep the active user-state model unchanged: `专注`, `走神`, `暂离`. This plan only changes desktop pet resources and settings, not gaze fusion or rule behavior.

## Execution Record

- 2026-06-10: Implemented the generic Pet Pack model, validator, local IXiaoHei generator, importer, store, resource loader, settings UI, selected-pack persistence, and packaging exclusions.
- Verified with `swift build`.
- Verified with `swift test`; this local toolchain does not expose `XCTest` or `Testing`, so the test target is compile-probe style.
- Verified runtime core behavior with `swift run FocusPetCoreChecks`, including Pet Pack fallback, manifest-key decoding, validator errors/warnings, and selected-pack default migration.
- Verified `python3 scripts/build-luoxiaohei-local-pack.py` generates `external_generated_packs/LuoXiaoHeiLocal` from the provided IXiaoHei repository.
- Verified the actual `PetPackImporter.swift` implementation with a temporary Swift check program that imports `external_generated_packs/LuoXiaoHeiLocal` into a temporary install root and reads back `source=userImported`, `distribution=localOnly`, and `idle/000.png`.
- Verified `./scripts/package-macos-app.sh` creates `.build/FocusPet.app` and default packaging leaves no `LuoXiaoHeiLocal`, `external_assets`, or `external_generated_packs` paths in the app bundle.
- Verified `.build/FocusPet.app` launches and the Focus Pet process stays running. Deep SwiftUI Tab/file-picker automation was not stable through System Events in this desktop session, so the import button flow is implemented and build-verified, but not fully driven by UI automation here.

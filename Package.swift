// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FocusPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FocusPet", targets: ["FocusPetMac"]),
        .executable(name: "FocusPetCoreChecks", targets: ["FocusPetCoreChecks"])
    ],
    targets: [
        .target(
            name: "FocusPetCore",
            resources: [
                .process("Resources/AppClassificationCatalog.json")
            ]
        ),
        .target(
            name: "FocusPetStorage",
            dependencies: ["FocusPetCore"]
        ),
        .target(
            name: "FocusPetResources",
            dependencies: ["FocusPetCore"],
            resources: [
                .copy("Resources/Pets")
            ]
        ),
        .target(
            name: "FocusPetRenderer",
            dependencies: ["FocusPetCore", "FocusPetResources"]
        ),
        .executableTarget(
            name: "FocusPetMac",
            dependencies: [
                "FocusPetCore",
                "FocusPetStorage",
                "FocusPetResources",
                "FocusPetRenderer"
            ],
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/StatusIcon.png")
            ]
        ),
        .executableTarget(
            name: "FocusPetCoreChecks",
            dependencies: ["FocusPetCore", "FocusPetResources", "FocusPetRenderer", "FocusPetStorage"]
        ),
        .testTarget(
            name: "FocusPetCoreTests",
            dependencies: ["FocusPetCore", "FocusPetResources", "FocusPetStorage"]
        )
    ]
)

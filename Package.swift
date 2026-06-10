// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FocusPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FocusPet", targets: ["FocusPet"]),
        .executable(name: "FocusPetCoreChecks", targets: ["FocusPetCoreChecks"])
    ],
    targets: [
        .target(
            name: "FocusPetCore"
        ),
        .executableTarget(
            name: "FocusPet",
            dependencies: ["FocusPetCore"],
            resources: [
                .copy("Resources/Pets"),
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .executableTarget(
            name: "FocusPetCoreChecks",
            dependencies: ["FocusPetCore"]
        ),
        .testTarget(
            name: "FocusPetCoreTests",
            dependencies: ["FocusPetCore"]
        )
    ]
)

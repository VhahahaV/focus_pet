import Foundation

public enum FocusPetDataPaths {
    public static let applicationSupportFolderName = "Focus Pet"
    public static let legacyApplicationSupportFolderNames = [
        "FocusPetMVP",
        "FocusPetV0",
        "FocusPetLegacy"
    ]

    public static func rootURL() -> URL {
        applicationSupportURL()
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
    }

    public static func petPacksRootURL() -> URL {
        rootURL().appendingPathComponent("PetPacks", isDirectory: true)
    }

    public static func legacyRootURLs() -> [URL] {
        legacyApplicationSupportFolderNames.map {
            applicationSupportURL().appendingPathComponent($0, isDirectory: true)
        }
    }

    private static func applicationSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}

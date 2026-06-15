import Foundation

public enum FocusPetPackagedResources {
    public static func bundle(named bundleName: String, fallback: @autoclosure () -> Bundle? = nil) -> Bundle? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName, isDirectory: true),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(bundleName, isDirectory: true)
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let bundle = Bundle(path: candidate.path) else {
                continue
            }
            return bundle
        }

        if Bundle.main.bundleURL.pathExtension == "app" {
            return nil
        }

        return fallback()
    }

    public static func url(
        inBundleNamed bundleName: String,
        forResource resourceName: String,
        withExtension resourceExtension: String?,
        fallback: @autoclosure () -> URL? = nil
    ) -> URL? {
        if let packagedBundle = bundle(named: bundleName) {
            return packagedBundle.url(forResource: resourceName, withExtension: resourceExtension)
        }

        if Bundle.main.bundleURL.pathExtension == "app" {
            return nil
        }

        return fallback()
    }
}

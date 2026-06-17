import FocusPetCore
import Foundation

public struct FocusPetWidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot.json"
    public var url: URL

    public init(url: URL = Self.defaultURL()) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        FocusPetDataPaths.rootURL().appendingPathComponent(fileName)
    }

    public func load() -> FocusPetWidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.focusPetWidget.decode(FocusPetWidgetSnapshot.self, from: data)
    }

    public func save(_ snapshot: FocusPetWidgetSnapshot) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder.focusPetWidget.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var focusPetWidget: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var focusPetWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

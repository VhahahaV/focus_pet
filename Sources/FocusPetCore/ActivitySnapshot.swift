import Foundation

public struct ActivitySnapshot: Codable, Hashable, Sendable {
    public var timestamp: Date
    public var appName: String
    public var bundleID: String?
    public var windowTitle: String?
    public var titleHash: String?
    public var titleStored: Bool
    public var titleDisplay: String?
    public var category: ActivityCategory
    public var idleSeconds: TimeInterval
    public var switchCountLast5Min: Int
    public var switchCountLast15Min: Int
    public var activeCategoryDuration: TimeInterval
    public var activeAppDuration: TimeInterval
    public var isFocusSessionActive: Bool
    public var isBreakActive: Bool
    public var isSystemSleeping: Bool
    public var isScreenLocked: Bool
    public var source: Set<ActivitySignalSource>

    public init(
        timestamp: Date,
        appName: String,
        bundleID: String?,
        windowTitle: String?,
        titleHash: String? = nil,
        titleStored: Bool = false,
        titleDisplay: String? = nil,
        category: ActivityCategory,
        idleSeconds: TimeInterval,
        switchCountLast5Min: Int,
        switchCountLast15Min: Int,
        activeCategoryDuration: TimeInterval,
        activeAppDuration: TimeInterval? = nil,
        isFocusSessionActive: Bool,
        isBreakActive: Bool,
        isSystemSleeping: Bool = false,
        isScreenLocked: Bool = false,
        source: Set<ActivitySignalSource> = [.frontmostApplication, .windowTitle, .idleTime, .appSwitching]
    ) {
        self.timestamp = timestamp
        self.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : appName
        self.bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.windowTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.titleHash = titleHash
        self.titleStored = titleStored
        self.titleDisplay = titleDisplay
        self.category = category
        self.idleSeconds = max(0, idleSeconds)
        self.switchCountLast5Min = max(0, switchCountLast5Min)
        self.switchCountLast15Min = max(0, switchCountLast15Min)
        self.activeCategoryDuration = max(0, activeCategoryDuration)
        self.activeAppDuration = max(0, activeAppDuration ?? activeCategoryDuration)
        self.isFocusSessionActive = isFocusSessionActive
        self.isBreakActive = isBreakActive
        self.isSystemSleeping = isSystemSleeping
        self.isScreenLocked = isScreenLocked
        self.source = source
    }
}

public struct SanitizedWindowTitle: Codable, Hashable, Sendable {
    public var rawTitle: String?
    public var titleDisplay: String?
    public var titleStored: Bool
    public var titleHash: String?
}

public struct WindowTitlePrivacy: Codable, Hashable, Sendable {
    public var storeRawTitle: Bool
    public var storeOnlyCategoryResult: Bool
    public var pauseActivityRecording: Bool

    public init(
        storeRawTitle: Bool = false,
        storeOnlyCategoryResult: Bool = false,
        pauseActivityRecording: Bool = false
    ) {
        self.storeRawTitle = storeOnlyCategoryResult ? false : storeRawTitle
        self.storeOnlyCategoryResult = storeOnlyCategoryResult
        self.pauseActivityRecording = pauseActivityRecording
    }

    public static let `default` = WindowTitlePrivacy(storeRawTitle: false)

    public func sanitize(_ title: String?) -> SanitizedWindowTitle {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return SanitizedWindowTitle(rawTitle: nil, titleDisplay: nil, titleStored: false, titleHash: nil)
        }

        if storeOnlyCategoryResult {
            return SanitizedWindowTitle(rawTitle: nil, titleDisplay: nil, titleStored: false, titleHash: nil)
        }

        return SanitizedWindowTitle(
            rawTitle: storeRawTitle ? title : nil,
            titleDisplay: storeRawTitle ? title : title.privacyRedactedTitle,
            titleStored: storeRawTitle,
            titleHash: String(title.hashValue)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case storeRawTitle
        case storeOnlyCategoryResult
        case pauseActivityRecording
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            storeRawTitle: try container.decodeIfPresent(Bool.self, forKey: .storeRawTitle) ?? false,
            storeOnlyCategoryResult: try container.decodeIfPresent(Bool.self, forKey: .storeOnlyCategoryResult) ?? false,
            pauseActivityRecording: try container.decodeIfPresent(Bool.self, forKey: .pauseActivityRecording) ?? false
        )
    }
}

public extension String {
    var privacyRedactedTitle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let capped = trimmed.count > 28 ? String(trimmed.prefix(28)) : trimmed
        return capped.replacingOccurrences(
            of: #"[A-Za-z0-9._%+-]{2,}"#,
            with: "•",
            options: .regularExpression
        )
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

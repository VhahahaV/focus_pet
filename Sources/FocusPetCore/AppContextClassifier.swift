import Foundation

public struct AppCategoryRule: Identifiable, Codable, Hashable, Sendable {
    public var id: String { bundleID ?? appName }
    public var appName: String
    public var bundleID: String?
    public var context: ContextType

    public init(appName: String, bundleID: String?, context: ContextType) {
        self.appName = appName
        self.bundleID = bundleID
        self.context = context
    }
}

public struct AppContextClassifier: Sendable {
    public var rules: [AppCategoryRule]

    public init(rules: [AppCategoryRule] = Self.defaultRules) {
        self.rules = rules
    }

    public func classify(appName: String?, bundleID: String?) -> ContextType {
        let normalizedName = appName?.lowercased() ?? ""
        let normalizedBundleID = bundleID?.lowercased()

        if let match = rules.first(where: { rule in
            if let ruleBundleID = rule.bundleID?.lowercased(),
               let normalizedBundleID,
               normalizedBundleID.contains(ruleBundleID) {
                return true
            }

            return normalizedName.contains(rule.appName.lowercased())
        }) {
            return match.context
        }

        return .neutral
    }
}

public extension AppContextClassifier {
    static let defaultRules: [AppCategoryRule] = [
        AppCategoryRule(appName: "Cursor", bundleID: nil, context: .work),
        AppCategoryRule(appName: "Visual Studio Code", bundleID: "com.microsoft.vscode", context: .work),
        AppCategoryRule(appName: "VS Code", bundleID: "com.microsoft.vscode", context: .work),
        AppCategoryRule(appName: "Xcode", bundleID: "com.apple.dt.Xcode", context: .work),
        AppCategoryRule(appName: "Terminal", bundleID: "com.apple.Terminal", context: .work),
        AppCategoryRule(appName: "iTerm", bundleID: "com.googlecode.iterm2", context: .work),
        AppCategoryRule(appName: "Obsidian", bundleID: "md.obsidian", context: .work),
        AppCategoryRule(appName: "Notion", bundleID: "notion.id", context: .work),
        AppCategoryRule(appName: "Microsoft Word", bundleID: "com.microsoft.Word", context: .work),
        AppCategoryRule(appName: "Preview", bundleID: "com.apple.Preview", context: .work),
        AppCategoryRule(appName: "YouTube", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "Bilibili", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "Netflix", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "Steam", bundleID: "com.valvesoftware.steam", context: .entertainment),
        AppCategoryRule(appName: "Zoom", bundleID: "us.zoom.xos", context: .meeting),
        AppCategoryRule(appName: "Microsoft Teams", bundleID: "com.microsoft.teams", context: .meeting),
        AppCategoryRule(appName: "Google Meet", bundleID: nil, context: .meeting),
        AppCategoryRule(appName: "Tencent Meeting", bundleID: nil, context: .meeting),
        AppCategoryRule(appName: "VooV Meeting", bundleID: nil, context: .meeting)
    ]
}

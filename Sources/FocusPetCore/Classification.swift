import Foundation

public enum RuleMatchKind: String, Codable, Hashable, Sendable, CaseIterable {
    case appName
    case bundleID
    case windowTitle

    public var title: String {
        switch self {
        case .appName: "App 名称"
        case .bundleID: "Bundle ID"
        case .windowTitle: "窗口标题"
        }
    }
}

public struct ClassificationRule: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var matchKind: RuleMatchKind
    public var pattern: String
    public var category: ActivityCategory
    public var priority: Int

    public init(
        id: String = UUID().uuidString,
        matchKind: RuleMatchKind,
        pattern: String,
        category: ActivityCategory,
        priority: Int = 0
    ) {
        self.id = id
        self.matchKind = matchKind
        self.pattern = pattern
        self.category = category
        self.priority = priority
    }
}

public struct ActivityClassifier: Sendable {
    public var rules: [ClassificationRule]

    public init(rules: [ClassificationRule] = Self.defaultRules) {
        self.rules = rules.sorted { $0.priority > $1.priority }
    }

    public func classify(appName: String, bundleID: String?, windowTitle: String?) -> ActivityCategory {
        let name = appName.lowercased()
        let bundle = bundleID?.lowercased() ?? ""
        let title = windowTitle?.lowercased() ?? ""

        for rule in rules {
            let pattern = rule.pattern.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }

            let matches: Bool
            switch rule.matchKind {
            case .appName:
                matches = name.contains(pattern)
            case .bundleID:
                matches = bundle.contains(pattern)
            case .windowTitle:
                matches = title.contains(pattern)
            }

            if matches {
                return rule.category
            }
        }

        return .neutral
    }
}

public extension ActivityClassifier {
    static let defaultRules: [ClassificationRule] = [
        ClassificationRule(matchKind: .appName, pattern: "Cursor", category: .work, priority: 100),
        ClassificationRule(matchKind: .appName, pattern: "Visual Studio Code", category: .work, priority: 100),
        ClassificationRule(matchKind: .bundleID, pattern: "com.microsoft.vscode", category: .work, priority: 100),
        ClassificationRule(matchKind: .appName, pattern: "Xcode", category: .work, priority: 100),
        ClassificationRule(matchKind: .appName, pattern: "Terminal", category: .work, priority: 100),
        ClassificationRule(matchKind: .appName, pattern: "iTerm", category: .work, priority: 100),
        ClassificationRule(matchKind: .appName, pattern: "Notion", category: .work, priority: 90),
        ClassificationRule(matchKind: .appName, pattern: "Obsidian", category: .work, priority: 90),
        ClassificationRule(matchKind: .appName, pattern: "Word", category: .work, priority: 80),
        ClassificationRule(matchKind: .appName, pattern: "PowerPoint", category: .work, priority: 80),
        ClassificationRule(matchKind: .appName, pattern: "Excel", category: .work, priority: 80),
        ClassificationRule(matchKind: .appName, pattern: "Figma", category: .work, priority: 80),
        ClassificationRule(matchKind: .windowTitle, pattern: "paper", category: .work, priority: 70),
        ClassificationRule(matchKind: .windowTitle, pattern: "论文", category: .work, priority: 70),
        ClassificationRule(matchKind: .windowTitle, pattern: "draft", category: .work, priority: 70),
        ClassificationRule(matchKind: .windowTitle, pattern: "report", category: .work, priority: 70),
        ClassificationRule(matchKind: .windowTitle, pattern: "project", category: .work, priority: 70),
        ClassificationRule(matchKind: .windowTitle, pattern: "GitHub", category: .work, priority: 70),
        ClassificationRule(matchKind: .windowTitle, pattern: "code", category: .work, priority: 70),
        ClassificationRule(matchKind: .windowTitle, pattern: "代码", category: .work, priority: 70),
        ClassificationRule(matchKind: .appName, pattern: "Steam", category: .entertainment, priority: 100),
        ClassificationRule(matchKind: .bundleID, pattern: "com.valvesoftware.steam", category: .entertainment, priority: 100),
        ClassificationRule(matchKind: .windowTitle, pattern: "YouTube", category: .entertainment, priority: 90),
        ClassificationRule(matchKind: .windowTitle, pattern: "Bilibili", category: .entertainment, priority: 90),
        ClassificationRule(matchKind: .windowTitle, pattern: "Netflix", category: .entertainment, priority: 90),
        ClassificationRule(matchKind: .windowTitle, pattern: "Twitch", category: .entertainment, priority: 90),
        ClassificationRule(matchKind: .windowTitle, pattern: "小红书", category: .entertainment, priority: 90),
        ClassificationRule(matchKind: .windowTitle, pattern: "抖音", category: .entertainment, priority: 90),
        ClassificationRule(matchKind: .windowTitle, pattern: "微博", category: .entertainment, priority: 90),
        ClassificationRule(matchKind: .windowTitle, pattern: "视频", category: .entertainment, priority: 80),
        ClassificationRule(matchKind: .windowTitle, pattern: "直播", category: .entertainment, priority: 80),
        ClassificationRule(matchKind: .windowTitle, pattern: "游戏", category: .entertainment, priority: 80),
        ClassificationRule(matchKind: .appName, pattern: "1Password", category: .ignore, priority: 100),
        ClassificationRule(matchKind: .appName, pattern: "System Settings", category: .ignore, priority: 100),
        ClassificationRule(matchKind: .appName, pattern: "Activity Monitor", category: .ignore, priority: 100)
    ]
}

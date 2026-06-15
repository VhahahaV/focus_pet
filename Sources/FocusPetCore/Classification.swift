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

public struct ClassificationCatalogEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var matchKind: RuleMatchKind
    public var patterns: [String]
    public var category: ActivityCategory
    public var priority: Int
    public var aliases: [String]
    public var regions: [String]
    public var notes: String?

    public init(
        id: String,
        matchKind: RuleMatchKind,
        patterns: [String],
        category: ActivityCategory,
        priority: Int,
        aliases: [String] = [],
        regions: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.matchKind = matchKind
        self.patterns = patterns
        self.category = category
        self.priority = priority
        self.aliases = aliases
        self.regions = regions
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case matchKind
        case patterns
        case category
        case priority
        case aliases
        case regions
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            matchKind: try container.decode(RuleMatchKind.self, forKey: .matchKind),
            patterns: try container.decode([String].self, forKey: .patterns),
            category: try container.decode(ActivityCategory.self, forKey: .category),
            priority: try container.decode(Int.self, forKey: .priority),
            aliases: try container.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            regions: try container.decodeIfPresent([String].self, forKey: .regions) ?? [],
            notes: try container.decodeIfPresent(String.self, forKey: .notes)
        )
    }
}

public struct ActivityClassifier: Sendable {
    public var rules: [ClassificationRule]
    private let compiledRules: [CompiledClassificationRule]

    public init(rules userRules: [ClassificationRule] = []) {
        let elevatedUserRules = userRules.enumerated().map { offset, rule in
            var copy = rule
            copy.priority = max(copy.priority, 10_000 - offset)
            return copy
        }
        let sortedRules = (elevatedUserRules + Self.defaultRules).sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.pattern.localizedCaseInsensitiveCompare(rhs.pattern) == .orderedAscending
            }
            return lhs.priority > rhs.priority
        }
        self.rules = sortedRules
        self.compiledRules = sortedRules.compactMap(CompiledClassificationRule.init(rule:))
    }

    public func classify(appName: String, bundleID: String?, windowTitle: String?) -> ActivityCategory {
        let name = appName.lowercased()
        let bundle = bundleID?.lowercased() ?? ""
        let title = windowTitle?.lowercased() ?? ""

        for rule in compiledRules {
            let matches: Bool
            switch rule.matchKind {
            case .appName:
                matches = name.contains(rule.pattern)
            case .bundleID:
                matches = bundle.contains(rule.pattern)
            case .windowTitle:
                matches = title.contains(rule.pattern)
            }

            if matches {
                return rule.category
            }
        }

        return .ignore
    }
}

public extension ActivityClassifier {
    static var catalogEntries: [ClassificationCatalogEntry] {
        cachedCatalogEntries
    }

    static var defaultRules: [ClassificationRule] {
        cachedDefaultRules
    }

    static func userRules(fromStored storedRules: [ClassificationRule]) -> [ClassificationRule] {
        let builtInKeys = Set(defaultRules.map(ruleKey))
        return storedRules.filter { !builtInKeys.contains(ruleKey($0)) && $0.category != .neutral }
    }

    private static func loadCatalogEntries() -> [ClassificationCatalogEntry] {
        guard let url = FocusPetPackagedResources.url(
            inBundleNamed: "FocusPet_FocusPetCore.bundle",
            forResource: "AppClassificationCatalog",
            withExtension: "json",
            fallback: Bundle.module.url(forResource: "AppClassificationCatalog", withExtension: "json")
        ),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ClassificationCatalogEntry].self, from: data) else {
            return fallbackRules.map {
                ClassificationCatalogEntry(
                    id: "\($0.matchKind.rawValue)-\($0.pattern)",
                    matchKind: $0.matchKind,
                    patterns: [$0.pattern],
                    category: $0.category,
                    priority: $0.priority
                )
            }
        }
        return entries
    }

    private static func ruleKey(_ rule: ClassificationRule) -> String {
        "\(rule.matchKind.rawValue)|\(rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(rule.category.rawValue)"
    }

    private static let cachedCatalogEntries: [ClassificationCatalogEntry] = loadCatalogEntries()

    private static let cachedDefaultRules: [ClassificationRule] = cachedCatalogEntries.flatMap { entry in
        entry.patterns.map {
            ClassificationRule(matchKind: entry.matchKind, pattern: $0, category: entry.category, priority: entry.priority)
        }
    }

    private static let fallbackRules: [ClassificationRule] = [
        ClassificationRule(matchKind: .appName, pattern: "Cursor", category: .work, priority: 500),
        ClassificationRule(matchKind: .appName, pattern: "Visual Studio Code", category: .work, priority: 500),
        ClassificationRule(matchKind: .appName, pattern: "Xcode", category: .work, priority: 500),
        ClassificationRule(matchKind: .appName, pattern: "Terminal", category: .work, priority: 500),
        ClassificationRule(matchKind: .appName, pattern: "Figma", category: .work, priority: 500),
        ClassificationRule(matchKind: .appName, pattern: "Steam", category: .entertainment, priority: 500),
        ClassificationRule(matchKind: .windowTitle, pattern: "YouTube", category: .entertainment, priority: 700),
        ClassificationRule(matchKind: .windowTitle, pattern: "Bilibili", category: .entertainment, priority: 700),
        ClassificationRule(matchKind: .windowTitle, pattern: "抖音", category: .entertainment, priority: 700),
        ClassificationRule(matchKind: .appName, pattern: "1Password", category: .ignore, priority: 500),
        ClassificationRule(matchKind: .appName, pattern: "System Settings", category: .ignore, priority: 500),
        ClassificationRule(matchKind: .appName, pattern: "Activity Monitor", category: .ignore, priority: 500)
    ]
}

private struct CompiledClassificationRule: Sendable {
    var matchKind: RuleMatchKind
    var pattern: String
    var category: ActivityCategory

    init?(rule: ClassificationRule) {
        let pattern = rule.pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !pattern.isEmpty else { return nil }
        self.matchKind = rule.matchKind
        self.pattern = pattern
        self.category = rule.category
    }
}

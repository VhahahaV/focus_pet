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

    public func classify(appName: String?, bundleID: String?, windowTitle: String? = nil) -> ContextType {
        classifyDetailed(appName: appName, bundleID: bundleID, windowTitle: windowTitle).context
    }

    public func classifyDetailed(appName: String?, bundleID: String?, windowTitle: String? = nil) -> AppContextClassification {
        let normalizedName = appName?.lowercased() ?? ""
        let normalizedBundleID = bundleID?.lowercased()
        let normalizedWindowTitle = windowTitle?.lowercased() ?? ""
        let normalizedAppText = "\(normalizedName) \(normalizedBundleID ?? "")"

        var workScore = 0.0
        var entertainmentScore = 0.0
        var meetingScore = 0.0
        var reason: [String] = []

        for rule in rules {
            let token = rule.appName.lowercased()
            var score: Double?
            var matchReason: String?

            if let ruleBundleID = rule.bundleID?.lowercased(),
               let normalizedBundleID,
               normalizedBundleID.contains(ruleBundleID) {
                score = 0.86
                matchReason = "bundle_match:\(ruleBundleID)"
            } else if normalizedWindowTitle.contains(token) {
                score = 0.88
                matchReason = "title_match:\(Self.reasonToken(token))"
            } else if normalizedAppText.contains(token) {
                score = 0.72
                matchReason = "app_match:\(Self.reasonToken(token))"
            }

            guard let score, let matchReason else { continue }

            switch rule.context {
            case .work:
                workScore = max(workScore, score)
            case .entertainment:
                entertainmentScore = max(entertainmentScore, score)
            case .meeting:
                meetingScore = max(meetingScore, score)
            case .neutral:
                break
            }
            reason.append(matchReason)
        }

        let neutralScore = reason.isEmpty ? 0.45 : 0.2
        let scoredContexts: [(ContextType, Double)] = [
            (.work, workScore),
            (.entertainment, entertainmentScore),
            (.meeting, meetingScore),
            (.neutral, neutralScore)
        ]
        let winner = scoredContexts.max { $0.1 < $1.1 } ?? (.neutral, neutralScore)

        return AppContextClassification(
            context: winner.0,
            confidence: winner.1,
            workScore: workScore,
            entertainmentScore: entertainmentScore,
            meetingScore: meetingScore,
            neutralScore: neutralScore,
            reason: reason.isEmpty ? ["no_app_context_match"] : reason
        )
    }

    private static func reasonToken(_ token: String) -> String {
        token
            .replacingOccurrences(of: ".com", with: "")
            .replacingOccurrences(of: " ", with: "_")
    }
}

public struct AppContextClassification: Codable, Hashable, Sendable {
    public var context: ContextType
    public var confidence: Double
    public var workScore: Double
    public var entertainmentScore: Double
    public var meetingScore: Double
    public var neutralScore: Double
    public var reason: [String]

    public init(
        context: ContextType,
        confidence: Double,
        workScore: Double,
        entertainmentScore: Double,
        meetingScore: Double,
        neutralScore: Double,
        reason: [String]
    ) {
        self.context = context
        self.confidence = confidence
        self.workScore = workScore
        self.entertainmentScore = entertainmentScore
        self.meetingScore = meetingScore
        self.neutralScore = neutralScore
        self.reason = reason
    }

    public static let neutral = AppContextClassification(
        context: .neutral,
        confidence: 0.45,
        workScore: 0,
        entertainmentScore: 0,
        meetingScore: 0,
        neutralScore: 0.45,
        reason: ["no_app_context_match"]
    )
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
        AppCategoryRule(appName: "youtube.com", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "Bilibili", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "bilibili.com", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "哔哩哔哩", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "Netflix", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "netflix.com", bundleID: nil, context: .entertainment),
        AppCategoryRule(appName: "Steam", bundleID: "com.valvesoftware.steam", context: .entertainment),
        AppCategoryRule(appName: "Zoom", bundleID: "us.zoom.xos", context: .meeting),
        AppCategoryRule(appName: "Microsoft Teams", bundleID: "com.microsoft.teams", context: .meeting),
        AppCategoryRule(appName: "Google Meet", bundleID: nil, context: .meeting),
        AppCategoryRule(appName: "meet.google.com", bundleID: nil, context: .meeting),
        AppCategoryRule(appName: "Tencent Meeting", bundleID: nil, context: .meeting),
        AppCategoryRule(appName: "腾讯会议", bundleID: nil, context: .meeting),
        AppCategoryRule(appName: "VooV Meeting", bundleID: nil, context: .meeting)
    ]
}

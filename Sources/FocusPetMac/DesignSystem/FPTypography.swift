import SwiftUI

enum FPTypography {
    static let windowTitle = Font.system(size: 24, weight: .semibold)
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let heroTitle = Font.system(size: 30, weight: .semibold)
    static let heroMetric = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12, weight: .regular)
    static let captionMedium = Font.system(size: 12, weight: .medium)
    static let badge = Font.system(size: 12, weight: .medium)
    static let small = Font.system(size: 11, weight: .regular)

    static func captionFont(weight: Font.Weight = .regular) -> Font {
        .system(size: 12, weight: weight)
    }

    static func caption2Font(weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight)
    }

    static func subheadlineFont(weight: Font.Weight = .regular) -> Font {
        .system(size: 13, weight: weight)
    }

    static func headlineFont(weight: Font.Weight = .semibold) -> Font {
        .system(size: 15, weight: weight)
    }

    static func title3Font(weight: Font.Weight = .semibold) -> Font {
        .system(size: 20, weight: weight, design: .rounded)
    }

    static func title2Font(weight: Font.Weight = .semibold) -> Font {
        .system(size: 22, weight: weight, design: .rounded)
    }
}

import SwiftUI

enum FPSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum FPRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let card: CGFloat = 20
    static let hero: CGFloat = 22
    static let pill: CGFloat = 999
}

enum FPSize {
    static let sidebarWidth: CGFloat = 240
    static let navItemHeight: CGFloat = 50
    static let buttonHeight: CGFloat = 40
    static let smallButtonHeight: CGFloat = 32
    static let badgeHeight: CGFloat = 28
    static let rowHeight: CGFloat = 56
    static let iconBox: CGFloat = 34
}

enum FPLayout {
    static let todayTopCardHeight: CGFloat = 212
    static let todayTopCardMinHeight: CGFloat = 184
    static let todayTopCardMaxHeight: CGFloat = 212
    static let todayBreakMinWidth: CGFloat = 312
    static let todayBreakMaxWidth: CGFloat = 382
    static let todayBreakResponsiveWidthRatio: CGFloat = 0.44
}

enum FPCardMetrics {
    static let defaultPadding: CGFloat = FPSpacing.xl
    static let compactPadding: CGFloat = FPSpacing.md
    static let heroPadding: CGFloat = FPSpacing.xl

    static let semanticStripWidth: CGFloat = 4
    static let semanticStripLeadingInset: CGFloat = FPSpacing.sm
    static let semanticStripVerticalInset: CGFloat = FPSpacing.lg
    static let semanticContentLeadingReserve: CGFloat = FPSpacing.lg
}

enum FPControlMetrics {
    static let restIconBox: CGFloat = 30
    static let restRingSize: CGFloat = 48
    static let restActionHeight: CGFloat = 38
    static let restMinuteSelectorHeight: CGFloat = 36
    static let restMinuteButtonHeight: CGFloat = 28
    static let restActionIconBox: CGFloat = 26
}

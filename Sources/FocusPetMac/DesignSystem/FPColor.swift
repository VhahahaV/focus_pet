import Foundation
import SwiftUI

extension Color {
    init(hex: String, opacity: Double = 1.0) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

enum FPColor {
    static let appBackgroundTop = Color(hex: "#F8FBFF")
    static let appBackgroundMiddle = Color(hex: "#F3F7FC")
    static let appBackgroundBottom = Color(hex: "#EEF4FA")

    static let sidebarTop = Color(hex: "#F2F7FC")
    static let sidebarBottom = Color(hex: "#EAF1F8")

    static let card = Color(hex: "#FFFFFF")
    static let cardSoft = Color(hex: "#FBFDFF")
    static let cardHover = Color(hex: "#F6FAFE")
    static let insetSurface = Color(hex: "#F4F8FC")
    static let controlSurface = Color(hex: "#F7FAFD")

    static let borderDefault = Color(hex: "#DCE7F2")
    static let borderSoft = Color(hex: "#E7EEF6")
    static let borderStrong = Color(hex: "#C9DAEC")
    static let divider = Color(hex: "#EAF0F6")

    static let textPrimary = Color(hex: "#243447")
    static let textSecondary = Color(hex: "#5E7188")
    static let textTertiary = Color(hex: "#8A9AAF")
    static let textDisabled = Color(hex: "#B4C0CF")

    static let focus600 = Color(hex: "#2F7EDB")
    static let focus500 = Color(hex: "#5AA6F8")
    static let focus400 = Color(hex: "#7BB9FA")
    static let focus300 = Color(hex: "#A8D2FD")
    static let focus200 = Color(hex: "#D8ECFF")
    static let focus100 = Color(hex: "#EEF7FF")
    static let focus050 = Color(hex: "#F5FAFF")

    static let distracted600 = Color(hex: "#C98422")
    static let distracted500 = Color(hex: "#F3B25B")
    static let distracted400 = Color(hex: "#F6C27B")
    static let distracted300 = Color(hex: "#F9D6A8")
    static let distracted200 = Color(hex: "#FDEBD3")
    static let distracted100 = Color(hex: "#FFF6EA")
    static let distracted050 = Color(hex: "#FFFAF2")

    static let rest600 = Color(hex: "#3D9964")
    static let rest500 = Color(hex: "#68BE8B")
    static let rest400 = Color(hex: "#85CDA1")
    static let rest300 = Color(hex: "#B6E2C4")
    static let rest200 = Color(hex: "#DDF4E5")
    static let rest100 = Color(hex: "#F2FBF5")
    static let rest050 = Color(hex: "#F7FCF9")

    static let away500 = Color(hex: "#9AA8B8")
    static let away300 = Color(hex: "#CBD5E1")
    static let away100 = Color(hex: "#F1F5F9")

    static let petWarm500 = Color(hex: "#D99A83")
    static let petWarm300 = Color(hex: "#F1C9B9")
    static let petWarm100 = Color(hex: "#FFF3ED")

    static let systemCyan500 = Color(hex: "#58BDD2")
    static let systemCyan300 = Color(hex: "#A9E0EA")
    static let systemCyan100 = Color(hex: "#EFFBFD")

    static let success = Color(hex: "#63B985")
    static let successBackground = Color(hex: "#EAF8F0")

    static let warning = Color(hex: "#E0A64F")
    static let warningBackground = Color(hex: "#FFF5E5")

    static let error = Color(hex: "#E16A6A")
    static let errorBackground = Color(hex: "#FDEEEE")

    static let selectionBlue = Color(hex: "#EAF5FF")
}

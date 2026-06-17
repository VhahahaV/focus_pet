import SwiftUI

enum FPChartPalette {
    static let focus = FPColor.focus500
    static let focusStrong = FPColor.focus600
    static let focusSoft = FPColor.focus300
    static let focusTrack = FPColor.focus100

    static let distracted = FPColor.distracted500
    static let distractedStrong = FPColor.distracted600
    static let distractedSoft = FPColor.distracted300
    static let distractedTrack = FPColor.distracted100

    static let rest = FPColor.rest500
    static let restStrong = FPColor.rest600
    static let restSoft = FPColor.rest300
    static let restTrack = FPColor.rest100

    static let away = FPColor.away300
    static let inputKeyboard = Color(hex: "#9B7CF6")
    static let inputKeyboardStrong = Color(hex: "#7756D9")
    static let inputPointer = Color(hex: "#45B7A8")
    static let inputPointerStrong = Color(hex: "#268E82")
    static let inputTrack = Color(hex: "#F0ECFF")
    static let inputSwitch = Color(hex: "#B8A7FF")
    static let neutralTrack = Color(hex: "#EAF1F7")
    static let gridLine = Color(hex: "#ECF2F8")
    static let axisText = FPColor.textTertiary
    static let donutEmpty = Color(hex: "#E7EEF6")
}

func fpChartColor(for status: FPStatus) -> Color {
    switch status {
    case .focus: return FPChartPalette.focus
    case .distracted: return FPChartPalette.distracted
    case .rest: return FPChartPalette.rest
    case .away: return FPChartPalette.away
    default: return FPColor.textTertiary
    }
}

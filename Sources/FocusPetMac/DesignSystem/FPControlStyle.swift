import SwiftUI

extension Toggle {
    func fpToggleTint(_ status: FPStatus) -> some View {
        tint(status.primary)
    }
}

extension View {
    func fpSliderTint(_ status: FPStatus) -> some View {
        tint(status.primary)
    }
}

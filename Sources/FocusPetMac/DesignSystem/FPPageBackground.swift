import SwiftUI

struct FPPageBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                FPColor.appBackgroundTop,
                FPColor.appBackgroundMiddle,
                FPColor.appBackgroundBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct FPSidebarBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                FPColor.sidebarTop,
                FPColor.sidebarBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

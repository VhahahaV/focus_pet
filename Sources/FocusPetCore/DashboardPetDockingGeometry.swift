import CoreGraphics

public enum DashboardPetDockingGeometry {
    public static let defaultSidebarWidth: CGFloat = 218
    public static let defaultBottomInset: CGFloat = 18
    public static let defaultDockHeight: CGFloat = 184

    public static func sidebarDockFrame(
        windowFrame: CGRect,
        sidebarWidth: CGFloat = defaultSidebarWidth,
        bottomInset: CGFloat = defaultBottomInset
    ) -> CGRect {
        let dockWidth = min(sidebarWidth, windowFrame.width)
        let dockHeight = min(defaultDockHeight, max(96, windowFrame.height * 0.26))
        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.minY + bottomInset,
            width: dockWidth,
            height: dockHeight
        )
    }
}

import AppKit
import FocusPetCore
import SwiftUI

@main
struct FocusPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = FocusPetModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            MenuBarLabelView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Focus Pet", id: "dashboard") {
            MainDashboardView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 760)
                .onAppear {
                    model.start()
                }
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct MenuBarLabelView: View {
    @EnvironmentObject private var model: FocusPetModel
    @Environment(\.openWindow) private var openWindow
    @State private var didOpenInitialDashboard = false

    var body: some View {
        StatusBarIconView(title: model.menuTitle)
            .task {
                model.start()
                registerDashboardOpener()
                openInitialDashboardIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusPetOpenDashboardRequested)) { notification in
                let tab = notification.object as? DashboardTab ?? model.selectedTab
                openDashboard(tab)
            }
    }

    private func registerDashboardOpener() {
        model.registerOpenDashboardRequest { [weak model] tab in
            guard let model else { return }
            openDashboard(tab, model: model)
        }
    }

    private func openInitialDashboardIfNeeded() {
        guard !didOpenInitialDashboard else { return }
        didOpenInitialDashboard = true
        openDashboard(model.selectedTab)
    }

    private func openDashboard(_ tab: DashboardTab, model explicitModel: FocusPetModel? = nil) {
        let targetModel = explicitModel ?? model
        targetModel.selectedTab = tab
        if !targetModel.bringDashboardWindowToFront() {
            openWindow(id: "dashboard")
        }
        Task { @MainActor in
            await Task.yield()
            if targetModel.bringDashboardWindowToFront() {
                targetModel.presentPetForDashboard(tab: tab)
            }
        }
    }
}

private struct StatusBarIconView: View {
    var title: String

    var body: some View {
        Image(nsImage: Self.image)
            .frame(width: 18, height: 18)
            .fixedSize()
            .accessibilityLabel(title)
    }

    private static let image: NSImage = {
        let image = FocusPetPackagedResources.url(
            inBundleNamed: "FocusPet_FocusPetMac.bundle",
            forResource: "StatusIcon",
            withExtension: "png",
            fallback: Bundle.module.url(forResource: "StatusIcon", withExtension: "png")
        )
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

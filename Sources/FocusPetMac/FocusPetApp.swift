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
                .frame(minWidth: 980, minHeight: 680)
                .onAppear {
                    model.start()
                }
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarLabelView: View {
    @EnvironmentObject private var model: FocusPetModel
    @Environment(\.openWindow) private var openWindow
    @State private var didOpenInitialDashboard = false

    var body: some View {
        Label(model.menuTitle, systemImage: model.menuSymbol)
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
            targetModel.bringDashboardWindowToFront()
        }
    }
}

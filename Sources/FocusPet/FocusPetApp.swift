import SwiftUI

@main
struct FocusPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = FocusPetModel.shared

    var body: some Scene {
        WindowGroup("Focus Pet", id: "main") {
            MainDashboardView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 640)
                .task {
                    await model.bootstrap()
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

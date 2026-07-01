import AppKit
import FocusPetWidgets
import SwiftUI

@main
struct FocusPetWidgetPreviewApp {
    @MainActor
    static func main() throws {
        let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("output/widget-preview/focus-pet-widgets-native.png")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let snapshot = FocusPetWidgetSnapshotStore().load() ?? .sample()
        let board = FocusPetWidgetPreviewBoard(snapshot: snapshot)
            .frame(width: 660, height: 250)

        let renderer = ImageRenderer(content: board)
        renderer.proposedSize = ProposedViewSize(width: 660, height: 250)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewRenderError.renderFailed
        }
        try png.write(to: outputURL, options: [.atomic])
        print(outputURL.path)
    }
}

private struct FocusPetWidgetPreviewBoard: View {
    var snapshot: FocusPetWidgetSnapshot

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.46, green: 0.62, blue: 0.70),
                    Color(red: 0.18, green: 0.36, blue: 0.34),
                    Color(red: 0.10, green: 0.20, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.clear,
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Focus Pet 小组件开发预览")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)

                HStack(alignment: .top, spacing: 18) {
                    FocusPetCurrentStatusWidgetView(snapshot: snapshot)
                    FocusPetRecentRhythmWidgetView(
                        snapshot: snapshot,
                        selectedWindowHours: 4,
                        showsWindowSwitcher: false
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
        }
    }
}

private enum PreviewRenderError: Error {
    case renderFailed
}

import AppKit
import SwiftUI

@MainActor
final class PetHoverMenuController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private let screenMargin: CGFloat = 10
    private let anchorGap: CGFloat = 8

    func show(anchorFrame: NSRect, model: FocusPetModel) {
        guard model.petHoverMenuEnabled else { return }
        hideTask?.cancel()

        if panel == nil {
            let view = PetHoverMenuView { [weak self] inside in
                if inside {
                    self?.cancelHide()
                } else {
                    self?.scheduleHide()
                }
            }
                .environmentObject(model)
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 316, height: 174)

            let panel = NSPanel(
                contentRect: hostingView.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }

        reposition(anchorFrame: anchorFrame)
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
    }

    func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                self?.hide()
            }
        }
    }

    func cancelHide() {
        hideTask?.cancel()
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    func reposition(anchorFrame: NSRect) {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = screen(containing: anchorFrame) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? anchorFrame
        panel.setFrame(
            resolvedFrame(anchorFrame: anchorFrame, size: size, visibleFrame: visibleFrame),
            display: true
        )
    }

    private func resolvedFrame(anchorFrame: NSRect, size: CGSize, visibleFrame: NSRect) -> NSRect {
        let safeFrame = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        let preferredX = anchorFrame.midX - size.width / 2
        let x = clamped(preferredX, min: safeFrame.minX, max: safeFrame.maxX - size.width)

        let aboveY = anchorFrame.maxY + anchorGap
        let belowY = anchorFrame.minY - size.height - anchorGap
        let preferredY: CGFloat
        if aboveY + size.height <= safeFrame.maxY {
            preferredY = aboveY
        } else if belowY >= safeFrame.minY {
            preferredY = belowY
        } else {
            preferredY = aboveY
        }

        let y = clamped(preferredY, min: safeFrame.minY, max: safeFrame.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let centered = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
            return centered
        }

        return NSScreen.screens
            .map { screen in (screen, screen.frame.intersection(frame).width * screen.frame.intersection(frame).height) }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}

private struct PetHoverMenuView: View {
    @EnvironmentObject private var model: FocusPetModel
    var onHoverChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "pawprint.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.currentPetPackName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(model.petIsHovered ? "罗小黑正在看你" : "罗小黑待命中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(model.currentState.userState.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stateTint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(stateTint)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                PetHoverInfoRow(symbol: "sparkles", title: "动作", value: model.currentPetBehavior.title)
                PetHoverInfoRow(symbol: "tag.fill", title: "来源", value: model.observationSourceTitle)
                PetHoverInfoRow(symbol: "macwindow", title: "前台", value: model.frontAppName)
                PetHoverInfoRow(symbol: "waveform.path.ecg", title: "置信", value: "\(Int(model.currentState.confidence * 100))%")
            }

            Text(model.lastReminderMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .foregroundStyle(.primary)
        .padding(12)
        .frame(width: 316, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .onHover(perform: onHoverChange)
    }

    private var stateTint: Color {
        switch model.currentState.userState {
        case .focused: .green
        case .distracted: .orange
        case .away: .indigo
        }
    }
}

private struct PetHoverInfoRow: View {
    var symbol: String
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

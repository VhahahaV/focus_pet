import FocusPetCore
import SwiftUI

struct PetSpriteAnimator: View {
    var catalog: PetSpriteCatalog
    var action: PetAction
    var fallbackState: UserState
    var animated: Bool

    @State private var animationStartedAt = Date()

    var body: some View {
        if let frames = catalog.frames(for: action) {
            SpriteFramesView(
                frames: frames,
                fallbackFrames: catalog.frames(for: .idle),
                animated: animated,
                startedAt: animationStartedAt
            )
                .onChange(of: action) { _, _ in
                    animationStartedAt = Date()
                }
        } else {
            PetFigureView(state: fallbackState, animated: animated)
        }
    }
}

private struct SpriteFramesView: View {
    var frames: PetAnimationFrames
    var fallbackFrames: PetAnimationFrames?
    var animated: Bool
    var startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: frameInterval)) { timeline in
            let displayFrames = framesToDisplay(at: timeline.date)
            let index = frameIndex(in: displayFrames, at: timeline.date)
            Image(nsImage: displayFrames.images[index])
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        }
    }

    private var frameInterval: TimeInterval {
        guard animated else { return 60 }
        return 1 / Double(max(frames.descriptor.fps, 1))
    }

    private func framesToDisplay(at date: Date) -> PetAnimationFrames {
        guard animated,
              !frames.descriptor.loop,
              let fallbackFrames,
              !fallbackFrames.images.isEmpty,
              hasFinishedPrimaryAnimation(at: date) else {
            return frames
        }

        return fallbackFrames
    }

    private func hasFinishedPrimaryAnimation(at date: Date) -> Bool {
        guard frames.images.count > 1 else { return false }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return elapsed >= frameInterval * Double(frames.images.count)
    }

    private func frameIndex(in displayFrames: PetAnimationFrames, at date: Date) -> Int {
        guard animated, displayFrames.images.count > 1 else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let interval = 1 / Double(max(displayFrames.descriptor.fps, 1))
        let frame = Int(elapsed / interval)

        if displayFrames.descriptor.loop || displayFrames.key != frames.key {
            return frame % displayFrames.images.count
        }

        return min(frame, displayFrames.images.count - 1)
    }
}

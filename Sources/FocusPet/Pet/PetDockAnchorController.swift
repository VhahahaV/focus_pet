import AppKit
import FocusPetCore

struct PetPlacementResolution {
    var mode: PetPlacementMode
    var frame: NSRect
    var manualOrigin: CGPoint?
}

final class PetDockAnchorController {
    private let margin: CGFloat = 8
    private let cornerMargin: CGFloat = 24

    func resolveFrame(
        screen: NSScreen = NSScreen.main ?? NSScreen.screens.first!,
        petSize: CGSize,
        placement: PetPlacementMode,
        manualOrigin: CGPoint?
    ) -> NSRect {
        let frame = screen.frame
        let visible = screen.visibleFrame

        switch placement {
        case .manual:
            if let manualOrigin {
                return NSRect(origin: manualOrigin, size: petSize)
            }
            return resolveFrame(screen: screen, petSize: petSize, placement: .dockAttached, manualOrigin: nil)

        case .dockAttached:
            if visible.minY > frame.minY + 5 {
                let x = visible.maxX - petSize.width - 80
                let y = visible.minY + margin
                return NSRect(x: x, y: y, width: petSize.width, height: petSize.height)
            }

            if visible.minX > frame.minX + 5 {
                let x = visible.minX + margin
                let y = visible.minY + 80
                return NSRect(x: x, y: y, width: petSize.width, height: petSize.height)
            }

            if visible.maxX < frame.maxX - 5 {
                let x = visible.maxX - petSize.width - margin
                let y = visible.minY + 80
                return NSRect(x: x, y: y, width: petSize.width, height: petSize.height)
            }

            return bottomRight(frame: visible, petSize: petSize)

        case .bottomRightCorner:
            return bottomRight(frame: visible, petSize: petSize)

        case .bottomLeftCorner:
            return bottomLeft(frame: visible, petSize: petSize)
        }
    }

    func resolveDrop(
        proposedFrame: NSRect,
        screen: NSScreen,
        petSize: CGSize
    ) -> PetPlacementResolution {
        let visible = screen.visibleFrame
        let full = screen.frame

        if isNearDock(proposedFrame: proposedFrame, screenFrame: full, visibleFrame: visible) {
            let frame = resolveFrame(screen: screen, petSize: petSize, placement: .dockAttached, manualOrigin: nil)
            return PetPlacementResolution(mode: .dockAttached, frame: frame, manualOrigin: nil)
        }

        let left = bottomLeft(frame: visible, petSize: petSize)
        if distance(from: proposedFrame.origin, to: left.origin) < 120 {
            return PetPlacementResolution(mode: .bottomLeftCorner, frame: left, manualOrigin: nil)
        }

        let right = bottomRight(frame: visible, petSize: petSize)
        if distance(from: proposedFrame.origin, to: right.origin) < 120 {
            return PetPlacementResolution(mode: .bottomRightCorner, frame: right, manualOrigin: nil)
        }

        return PetPlacementResolution(mode: .manual, frame: proposedFrame, manualOrigin: proposedFrame.origin)
    }

    private func bottomRight(frame: NSRect, petSize: CGSize) -> NSRect {
        NSRect(
            x: frame.maxX - petSize.width - cornerMargin,
            y: frame.minY + cornerMargin,
            width: petSize.width,
            height: petSize.height
        )
    }

    private func bottomLeft(frame: NSRect, petSize: CGSize) -> NSRect {
        NSRect(
            x: frame.minX + cornerMargin,
            y: frame.minY + cornerMargin,
            width: petSize.width,
            height: petSize.height
        )
    }

    private func isNearDock(proposedFrame: NSRect, screenFrame: NSRect, visibleFrame: NSRect) -> Bool {
        if visibleFrame.minY > screenFrame.minY + 5 {
            return abs(proposedFrame.minY - visibleFrame.minY) < 80
        }

        if visibleFrame.minX > screenFrame.minX + 5 {
            return abs(proposedFrame.minX - visibleFrame.minX) < 80
        }

        if visibleFrame.maxX < screenFrame.maxX - 5 {
            return abs(proposedFrame.maxX - visibleFrame.maxX) < 80
        }

        return false
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

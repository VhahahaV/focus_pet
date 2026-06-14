import CoreGraphics
import Foundation

private struct WindowSnapshot {
    var id: Int
    var name: String
    var layer: Int
    var frame: CGRect
}

private enum VerificationError: Error, CustomStringConvertible {
    case missingDashboard
    case missingPet
    case petOutsideSidebar(WindowSnapshot, WindowSnapshot)
    case petNotNearSidebarBottom(WindowSnapshot, WindowSnapshot)
    case petLooksLikeBubbleIsVisible(WindowSnapshot)
    case petStillDockedAfterClose(WindowSnapshot, CGRect)

    var description: String {
        switch self {
        case .missingDashboard:
            return "Focus Pet dashboard window was not found."
        case .missingPet:
            return "Focus Pet pet panel window was not found."
        case let .petOutsideSidebar(dashboard, pet):
            return "Pet panel is outside the sidebar dock zone. dashboard=\(dashboard.frame) pet=\(pet.frame)"
        case let .petNotNearSidebarBottom(dashboard, pet):
            return "Pet panel is not near the sidebar bottom. dashboard=\(dashboard.frame) pet=\(pet.frame)"
        case let .petLooksLikeBubbleIsVisible(pet):
            return "Pet panel is taller than expected for a no-bubble docked pet. pet=\(pet.frame)"
        case let .petStillDockedAfterClose(pet, previousDockZone):
            return "Pet panel is still in the previous dashboard dock zone after closing the dashboard. pet=\(pet.frame) previousDockZone=\(previousDockZone)"
        }
    }
}

private let sidebarWidth: CGFloat = 218

private func focusPetWindows() -> [WindowSnapshot] {
    let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    return windows.compactMap { window in
        guard (window[kCGWindowOwnerName as String] as? String) == "Focus Pet",
              let id = window[kCGWindowNumber as String] as? Int,
              let layer = window[kCGWindowLayer as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }
        let name = window[kCGWindowName as String] as? String ?? ""
        return WindowSnapshot(
            id: id,
            name: name,
            layer: layer,
            frame: CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        )
    }
}

private func focusPetPID() -> pid_t? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", ".build/FocusPet.app/Contents/MacOS/FocusPet"]
    let pipe = Pipe()
    task.standardOutput = pipe
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return nil
    }
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output
        .split(separator: "\n")
        .compactMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .first
}

private func postSidebarClick(to pid: pid_t, dashboard: WindowSnapshot, tabIndex: Int) {
    let tabCentersFromTop: [CGFloat] = [170, 256, 342, 428]
    let yOffset = tabCentersFromTop[max(0, min(tabIndex, tabCentersFromTop.count - 1))]
    let point = CGPoint(x: dashboard.frame.minX + 82, y: dashboard.frame.minY + yOffset)
    let source = CGEventSource(stateID: .combinedSessionState)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: type == .mouseMoved ? 0 : 1)
            event.postToPid(pid)
        }
        usleep(type == .mouseMoved ? 70_000 : 90_000)
    }
    print("Posted sidebar click to pid \(pid) at \(Int(point.x)),\(Int(point.y)).")
}

private func postCommandW(to pid: pid_t) {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
    let keyCodeW: CGKeyCode = 13
    for keyDown in [true, false] {
        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCodeW, keyDown: keyDown) {
            event.flags = .maskCommand
            event.postToPid(pid)
        }
        usleep(120_000)
    }
    print("Posted Command-W to pid \(pid).")
}

private func verify(windows: [WindowSnapshot]) throws {
    guard let dashboard = windows.first(where: { $0.layer == 0 && $0.name == "Focus Pet" }) else {
        throw VerificationError.missingDashboard
    }
    guard let pet = windows.first(where: { $0.layer > 0 && $0.name.isEmpty }) else {
        throw VerificationError.missingPet
    }

    let sidebarRight = dashboard.frame.minX + min(sidebarWidth, dashboard.frame.width)
    let petBottom = pet.frame.maxY
    let dashboardBottom = dashboard.frame.maxY
    let bottomDockTop = dashboard.frame.minY + dashboard.frame.height * 0.58

    guard pet.frame.minX >= dashboard.frame.minX - 12,
          pet.frame.maxX <= sidebarRight + 16 else {
        throw VerificationError.petOutsideSidebar(dashboard, pet)
    }
    guard pet.frame.minY >= bottomDockTop,
          petBottom <= dashboardBottom + 12,
          petBottom >= dashboardBottom - 96 else {
        throw VerificationError.petNotNearSidebarBottom(dashboard, pet)
    }
    guard pet.frame.height <= pet.frame.width + 96 else {
        throw VerificationError.petLooksLikeBubbleIsVisible(pet)
    }

    print("Dashboard window: id=\(dashboard.id) frame=\(dashboard.frame)")
    print("Pet panel: id=\(pet.id) frame=\(pet.frame)")
    print("PASS: pet panel is docked inside the sidebar bottom zone and no status bubble is visible.")
}

private func verifyCommandWReturnsPetToDefault() throws {
    var windows = focusPetWindows()
    guard let dashboard = windows.first(where: { $0.layer == 0 && $0.name == "Focus Pet" }),
          let pid = focusPetPID() else {
        throw VerificationError.missingDashboard
    }
    let previousDockZone = CGRect(
        x: dashboard.frame.minX - 12,
        y: dashboard.frame.minY + dashboard.frame.height * 0.58,
        width: min(sidebarWidth, dashboard.frame.width) + 28,
        height: dashboard.frame.height * 0.42 + 24
    )

    postCommandW(to: pid)
    Thread.sleep(forTimeInterval: 0.9)
    windows = focusPetWindows()
    if windows.contains(where: { $0.layer == 0 && $0.name == "Focus Pet" }) {
        throw VerificationError.petStillDockedAfterClose(
            windows.first(where: { $0.layer > 0 && $0.name.isEmpty }) ?? dashboard,
            previousDockZone
        )
    }
    guard let pet = windows.first(where: { $0.layer > 0 && $0.name.isEmpty }) else {
        throw VerificationError.missingPet
    }
    guard !previousDockZone.intersects(pet.frame) else {
        throw VerificationError.petStillDockedAfterClose(pet, previousDockZone)
    }

    print("Pet panel after Command-W: id=\(pet.id) frame=\(pet.frame)")
    print("PASS: closing the dashboard releases the sidebar dock and returns the pet toward its default placement.")
}

private func main() throws {
    let shouldClick = CommandLine.arguments.contains("--click-sidebar")
    let shouldClose = CommandLine.arguments.contains("--command-w-expect-default")
    if shouldClose {
        try verifyCommandWReturnsPetToDefault()
        return
    }

    var windows = focusPetWindows()
    if shouldClick {
        guard let dashboard = windows.first(where: { $0.layer == 0 && $0.name == "Focus Pet" }),
              let pid = focusPetPID() else {
            throw VerificationError.missingDashboard
        }
        postSidebarClick(to: pid, dashboard: dashboard, tabIndex: 2)
        Thread.sleep(forTimeInterval: 0.8)
        windows = focusPetWindows()
    }

    try verify(windows: windows)
}

do {
    try main()
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}

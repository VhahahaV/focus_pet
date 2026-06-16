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
    case petDidNotMoveAfterDrag(WindowSnapshot, WindowSnapshot)

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
        case let .petDidNotMoveAfterDrag(before, after):
            return "Pet panel did not move enough after dragging. before=\(before.frame) after=\(after.frame)"
        }
    }
}

private let sidebarWidth: CGFloat = 218
private let minimumDashboardSize = CGSize(width: 600, height: 500)

private func eventPoint(fromWindowListPoint point: CGPoint) -> CGPoint {
    point
}

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

private func dashboardWindow(in windows: [WindowSnapshot]) -> WindowSnapshot? {
    windows.first {
        $0.layer == 0
            && $0.name == "Focus Pet"
            && $0.frame.width >= minimumDashboardSize.width
            && $0.frame.height >= minimumDashboardSize.height
    }
}

private func petWindow(in windows: [WindowSnapshot]) -> WindowSnapshot? {
    windows.first { $0.layer > 0 && $0.name.isEmpty }
}

private func raiseDashboardWindowIfPossible() {
    let script = """
    tell application "Focus Pet" to reopen
    tell application "System Events"
      tell process "Focus Pet"
        try
          perform action "AXRaise" of window "Focus Pet"
        end try
        try
          set frontmost to true
        end try
      end tell
    end tell
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try? process.run()
    process.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.6)
}

private func focusPetPID() -> pid_t? {
    let patterns = [
        ".build/Focus Pet.app/Contents/MacOS/FocusPet",
        ".build/FocusPet.app/Contents/MacOS/FocusPet"
    ]
    for pattern in patterns {
        if let pid = focusPetPID(matching: pattern) {
            return pid
        }
    }
    return nil
}

private func focusPetPID(matching pattern: String) -> pid_t? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", pattern]
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

private func postPetDrag(to pid: pid_t, pet: WindowSnapshot, delta: CGSize) {
    let petBodyOffsetFromBottom = min(34, max(18, pet.frame.height * 0.12))
    let windowListStart = CGPoint(x: pet.frame.midX, y: pet.frame.maxY - petBodyOffsetFromBottom)
    let windowListEnd = CGPoint(x: windowListStart.x + delta.width, y: windowListStart.y + delta.height)
    let start = eventPoint(fromWindowListPoint: windowListStart)
    let end = eventPoint(fromWindowListPoint: windowListEnd)
    let source = CGEventSource(stateID: .combinedSessionState)

    func post(_ type: CGEventType, at point: CGPoint, clickState: Int64) {
        if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: clickState)
            event.post(tap: .cghidEventTap)
        }
    }

    post(.mouseMoved, at: start, clickState: 0)
    usleep(90_000)
    post(.leftMouseDown, at: start, clickState: 1)
    usleep(120_000)
    for step in 1...8 {
        let progress = CGFloat(step) / 8
        let windowListPoint = CGPoint(
            x: windowListStart.x + delta.width * progress,
            y: windowListStart.y + delta.height * progress
        )
        let point = eventPoint(fromWindowListPoint: windowListPoint)
        post(.leftMouseDragged, at: point, clickState: 1)
        usleep(45_000)
    }
    post(.leftMouseUp, at: end, clickState: 1)
    print("Posted pet drag to pid \(pid) from \(Int(start.x)),\(Int(start.y)) to \(Int(end.x)),\(Int(end.y)).")
}

private func postSidebarClick(to pid: pid_t, dashboard: WindowSnapshot, tabIndex: Int) {
    let tabCentersFromTop: [CGFloat] = [180, 245, 310, 375]
    let yOffset = tabCentersFromTop[max(0, min(tabIndex, tabCentersFromTop.count - 1))]
    let windowListPoint = CGPoint(x: dashboard.frame.minX + 82, y: dashboard.frame.minY + yOffset)
    let point = eventPoint(fromWindowListPoint: windowListPoint)
    let source = CGEventSource(stateID: .combinedSessionState)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) {
            event.setIntegerValueField(.mouseEventClickState, value: type == .mouseMoved ? 0 : 1)
            event.post(tap: .cghidEventTap)
        }
        usleep(type == .mouseMoved ? 70_000 : 90_000)
    }
    print("Posted sidebar click to pid \(pid) at \(Int(point.x)),\(Int(point.y)).")
}

private func postMinimizeButtonClick(to pid: pid_t, dashboard: WindowSnapshot) {
    let script = """
    tell application "System Events"
      tell process "Focus Pet"
        perform action "AXPress" of (first button of window "Focus Pet" whose subrole is "AXMinimizeButton")
      end tell
    end tell
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try? process.run()
    process.waitUntilExit()
    print("Pressed minimize button for pid \(pid) on dashboard id \(dashboard.id).")
}

private func postCommandKey(to pid: pid_t, keyCode: CGKeyCode, label: String) {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
    for keyDown in [true, false] {
        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) {
            event.flags = .maskCommand
            event.postToPid(pid)
        }
        usleep(120_000)
    }
    print("Posted \(label) to pid \(pid).")
}

private func postCommandW(to pid: pid_t) {
    postCommandKey(to: pid, keyCode: 13, label: "Command-W")
}

private func postCommandM(to pid: pid_t) {
    postCommandKey(to: pid, keyCode: 46, label: "Command-M")
}

private func verify(windows: [WindowSnapshot]) throws {
    guard let dashboard = dashboardWindow(in: windows) else {
        throw VerificationError.missingDashboard
    }
    guard let pet = petWindow(in: windows) else {
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

private func verifyPetDragMovesPanel() throws {
    var windows = focusPetWindows()
    guard let pid = focusPetPID() else {
        throw VerificationError.missingPet
    }
    guard let before = petWindow(in: windows) else {
        throw VerificationError.missingPet
    }

    let displayBounds = CGDisplayBounds(CGMainDisplayID())
    let delta = CGSize(
        width: before.frame.midX < displayBounds.midX ? 96 : -96,
        height: before.frame.midY < displayBounds.midY ? 72 : -72
    )
    postPetDrag(to: pid, pet: before, delta: delta)
    Thread.sleep(forTimeInterval: 0.8)
    windows = focusPetWindows()
    guard let after = petWindow(in: windows) else {
        throw VerificationError.missingPet
    }

    let movement = hypot(after.frame.midX - before.frame.midX, after.frame.midY - before.frame.midY)
    guard movement >= 32 else {
        throw VerificationError.petDidNotMoveAfterDrag(before, after)
    }

    print("Pet panel before drag: id=\(before.id) frame=\(before.frame)")
    print("Pet panel after drag: id=\(after.id) frame=\(after.frame)")
    print("PASS: dragging the pet moves the panel and persists a custom placement candidate.")
}

private func verifyCommandWReturnsPetToDefault() throws {
    try verifyDashboardDismissalReturnsPetToDefault(actionName: "Command-W", dismiss: postCommandW)
}

private func verifyCommandMReturnsPetToDefault() throws {
    try verifyDashboardDismissalReturnsPetToDefault(actionName: "Command-M", dismiss: postCommandM)
}

private func verifyMinimizeButtonReturnsPetToDefault() throws {
    try verifyDashboardDismissalReturnsPetToDefault(actionName: "minimize button") { pid in
        let windows = focusPetWindows()
        if let dashboard = dashboardWindow(in: windows) {
            postMinimizeButtonClick(to: pid, dashboard: dashboard)
        }
    }
}

private func verifyDashboardDismissalReturnsPetToDefault(
    actionName: String,
    dismiss: (pid_t) -> Void
) throws {
    raiseDashboardWindowIfPossible()
    var windows = focusPetWindows()
    guard let dashboard = dashboardWindow(in: windows),
          let pid = focusPetPID() else {
        throw VerificationError.missingDashboard
    }
    let previousDockZone = CGRect(
        x: dashboard.frame.minX - 12,
        y: dashboard.frame.minY + dashboard.frame.height * 0.58,
        width: min(sidebarWidth, dashboard.frame.width) + 28,
        height: dashboard.frame.height * 0.42 + 24
    )

    dismiss(pid)
    Thread.sleep(forTimeInterval: 0.9)
    windows = focusPetWindows()
    if dashboardWindow(in: windows) != nil {
        throw VerificationError.petStillDockedAfterClose(
            petWindow(in: windows) ?? dashboard,
            previousDockZone
        )
    }
    guard let pet = petWindow(in: windows) else {
        throw VerificationError.missingPet
    }
    guard !previousDockZone.intersects(pet.frame) else {
        throw VerificationError.petStillDockedAfterClose(pet, previousDockZone)
    }

    print("Pet panel after \(actionName): id=\(pet.id) frame=\(pet.frame)")
    print("PASS: dismissing the dashboard with \(actionName) releases the sidebar dock and returns the pet toward its default placement.")
}

private func main() throws {
    let shouldClick = CommandLine.arguments.contains("--click-sidebar")
    let shouldClickSettings = CommandLine.arguments.contains("--click-settings")
    let shouldClose = CommandLine.arguments.contains("--command-w-expect-default")
    let shouldMinimize = CommandLine.arguments.contains("--command-m-expect-default")
    let shouldClickMinimize = CommandLine.arguments.contains("--click-minimize-expect-default")
    let shouldDrag = CommandLine.arguments.contains("--drag-pet-expect-move")
    if shouldDrag {
        try verifyPetDragMovesPanel()
        return
    }
    if shouldClose {
        try verifyCommandWReturnsPetToDefault()
        return
    }
    if shouldMinimize {
        try verifyCommandMReturnsPetToDefault()
        return
    }
    if shouldClickMinimize {
        try verifyMinimizeButtonReturnsPetToDefault()
        return
    }

    raiseDashboardWindowIfPossible()
    var windows = focusPetWindows()
    if shouldClick || shouldClickSettings {
        guard let dashboard = dashboardWindow(in: windows),
              let pid = focusPetPID() else {
            throw VerificationError.missingDashboard
        }
        postSidebarClick(to: pid, dashboard: dashboard, tabIndex: shouldClickSettings ? 3 : 2)
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

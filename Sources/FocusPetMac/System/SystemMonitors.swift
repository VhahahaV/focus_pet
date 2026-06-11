import AppKit
import CoreGraphics
import FocusPetCore
import Foundation
import IOKit

struct FrontmostApplicationSnapshot: Sendable {
    var appName: String
    var bundleID: String?
    var windowTitle: String?
}

struct ForegroundAppMonitor: Sendable {
    func snapshot() -> FrontmostApplicationSnapshot {
        let application = NSWorkspace.shared.frontmostApplication
        return FrontmostApplicationSnapshot(
            appName: application?.localizedName ?? "Unknown",
            bundleID: application?.bundleIdentifier,
            windowTitle: frontWindowTitle(for: application?.processIdentifier)
        )
    }

    private func frontWindowTitle(for processID: pid_t?) -> String? {
        guard let processID,
              let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        return windowList.first { info in
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            let layer = info[kCGWindowLayer as String] as? Int
            return ownerPID == processID && layer == 0
        }
        .flatMap { info in
            let title = info[kCGWindowName as String] as? String
            return title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }
}

enum IdleMonitor {
    static func idleSeconds() -> TimeInterval {
        if let hidIdleSeconds {
            return hidIdleSeconds
        }

        return min(
            secondsSinceMostRecent([.keyDown]),
            secondsSinceMostRecent([
                .mouseMoved,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .scrollWheel
            ])
        )
    }

    private static var hidIdleSeconds: TimeInterval? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        if let idleNanoseconds = dictionary["HIDIdleTime"] as? UInt64 {
            return Double(idleNanoseconds) / 1_000_000_000
        }
        if let idleNanoseconds = dictionary["HIDIdleTime"] as? NSNumber {
            return idleNanoseconds.doubleValue / 1_000_000_000
        }
        return nil
    }

    private static func secondsSinceMostRecent(_ eventTypes: [CGEventType]) -> TimeInterval {
        eventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? 0
    }
}

@MainActor
final class AppSwitchTracker {
    private var currentIdentity: String?
    private var currentCategory: ActivityCategory = .neutral
    private var currentAppSince = Date()
    private var currentCategorySince = Date()
    private var switchHistory: [Date] = []

    func update(identity: String, category: ActivityCategory, now: Date) {
        if currentIdentity == nil {
            currentIdentity = identity
            currentCategory = category
            currentAppSince = now
            currentCategorySince = now
            return
        }

        if identity != currentIdentity {
            switchHistory.append(now)
            currentIdentity = identity
            currentAppSince = now
        }

        if category != currentCategory {
            currentCategory = category
            currentCategorySince = now
        }

        switchHistory = switchHistory.filter { now.timeIntervalSince($0) <= 15 * 60 }
    }

    func switchCount(seconds: TimeInterval, now: Date) -> Int {
        switchHistory.filter { now.timeIntervalSince($0) <= seconds }.count
    }

    func activeAppDuration(now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(currentAppSince))
    }

    func activeCategoryDuration(now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(currentCategorySince))
    }
}

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

struct ScreenPlacementHint: Hashable, Sendable {
    var screenFrame: CGRect
    var visibleFrame: CGRect
}

struct SessionActivitySnapshot: Sendable {
    var isScreenLocked: Bool
}

struct ActivitySamplerSnapshot: Sendable {
    var session: SessionActivitySnapshot
    var frontmostApplication: FrontmostApplicationSnapshot
    var idleSeconds: TimeInterval
}

struct InputEventCounts: Hashable, Sendable {
    var keyboardCount: Int
    var pointerCount: Int

    init(keyboardCount: Int = 0, pointerCount: Int = 0) {
        self.keyboardCount = max(0, keyboardCount)
        self.pointerCount = max(0, pointerCount)
    }

    var hasInput: Bool {
        keyboardCount > 0 || pointerCount > 0
    }
}

enum SessionActivityMonitor {
    static func snapshot() -> SessionActivitySnapshot {
        SessionActivitySnapshot(isScreenLocked: isScreenLocked)
    }

    static var isScreenLocked: Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let locked = dictionary["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        if let locked = dictionary["CGSSessionScreenIsLocked"] as? NSNumber {
            return locked.boolValue
        }
        return false
    }
}

struct ForegroundAppMonitor: Sendable {
    func snapshot(includeWindowTitle: Bool = true) -> FrontmostApplicationSnapshot {
        let application = NSWorkspace.shared.frontmostApplication
        return FrontmostApplicationSnapshot(
            appName: application?.localizedName ?? "Unknown",
            bundleID: application?.bundleIdentifier,
            windowTitle: includeWindowTitle ? frontWindowTitle(for: application?.processIdentifier) : nil
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

actor ActivitySampler {
    private let foregroundMonitor = ForegroundAppMonitor()
    private var lastFrontmostApplication: FrontmostApplicationSnapshot?
    private var lastWindowTitleSampleAt = Date.distantPast

    func snapshot(now: Date, windowTitleRefreshInterval: TimeInterval = 10) -> ActivitySamplerSnapshot {
        let session = SessionActivityMonitor.snapshot()
        if session.isScreenLocked {
            return ActivitySamplerSnapshot(
                session: session,
                frontmostApplication: FrontmostApplicationSnapshot(
                    appName: "Locked Screen",
                    bundleID: nil,
                    windowTitle: nil
                ),
                idleSeconds: IdleMonitor.idleSeconds()
            )
        }

        let appOnly = foregroundMonitor.snapshot(includeWindowTitle: false)
        let currentIdentity = Self.identity(for: appOnly)
        let previousIdentity = lastFrontmostApplication.map(Self.identity(for:))
        let shouldRefreshWindowTitle = previousIdentity != currentIdentity
            || now.timeIntervalSince(lastWindowTitleSampleAt) >= windowTitleRefreshInterval

        let frontmostApplication: FrontmostApplicationSnapshot
        if shouldRefreshWindowTitle {
            frontmostApplication = foregroundMonitor.snapshot(includeWindowTitle: true)
            lastWindowTitleSampleAt = now
        } else {
            frontmostApplication = FrontmostApplicationSnapshot(
                appName: appOnly.appName,
                bundleID: appOnly.bundleID,
                windowTitle: lastFrontmostApplication?.windowTitle
            )
        }

        lastFrontmostApplication = frontmostApplication
        return ActivitySamplerSnapshot(
            session: session,
            frontmostApplication: frontmostApplication,
            idleSeconds: IdleMonitor.idleSeconds()
        )
    }

    private static func identity(for snapshot: FrontmostApplicationSnapshot) -> String {
        "\(snapshot.bundleID ?? "")|\(snapshot.appName)"
    }
}

@MainActor
final class MouseScreenTracker {
    private let stabilitySeconds: TimeInterval
    private var stableScreenKey: String?
    private var candidateScreenKey: String?
    private var candidateScreenSince = Date()

    init(stabilitySeconds: TimeInterval = 3) {
        self.stabilitySeconds = max(0.5, stabilitySeconds)
    }

    func update(mouseLocation: CGPoint = NSEvent.mouseLocation, now: Date = Date()) -> ScreenPlacementHint? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else {
            return nil
        }

        let key = Self.key(for: screen)
        if stableScreenKey == nil {
            stableScreenKey = key
            candidateScreenKey = key
            candidateScreenSince = now
            return ScreenPlacementHint(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        }

        if candidateScreenKey != key {
            candidateScreenKey = key
            candidateScreenSince = now
            return nil
        }

        guard stableScreenKey != key,
              now.timeIntervalSince(candidateScreenSince) >= stabilitySeconds else {
            return nil
        }

        stableScreenKey = key
        return ScreenPlacementHint(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    private static func key(for screen: NSScreen) -> String {
        let frame = screen.frame
        return "\(Int(frame.origin.x))|\(Int(frame.origin.y))|\(Int(frame.width))|\(Int(frame.height))"
    }
}

enum IdleMonitor {
    static func idleSeconds() -> TimeInterval {
        if let hidIdleSeconds {
            return hidIdleSeconds
        }

        return min(
            keyboardIdleSeconds(),
            pointerIdleSeconds()
        )
    }

    static func keyboardIdleSeconds() -> TimeInterval {
        secondsSinceMostRecent([.keyDown])
    }

    static func pointerIdleSeconds() -> TimeInterval {
        secondsSinceMostRecent(pointerEventTypes)
    }

    static func fallbackInputCounts(seconds windowSeconds: TimeInterval) -> InputEventCounts {
        let tolerance = max(0.25, min(1.5, windowSeconds * 0.25))
        let window = max(0.5, windowSeconds) + tolerance
        return InputEventCounts(
            keyboardCount: keyboardIdleSeconds() <= window ? 1 : 0,
            pointerCount: pointerIdleSeconds() <= window ? 1 : 0
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

    private static let pointerEventTypes: [CGEventType] = [
        .mouseMoved,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel
    ]

    private static func secondsSinceMostRecent(_ eventTypes: [CGEventType]) -> TimeInterval {
        eventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? 0
    }
}

private let focusPetInputEventCallback: CGEventTapCallBack = { _, type, event, refcon in
    if let refcon {
        let monitor = Unmanaged<InputActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
        monitor.record(eventType: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

final class InputActivityMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyboardCount = 0
    private var pointerCount = 0
    private var lastKeyboardEvent: KeyboardEventFingerprint?
    private var pressedTextKeys: [PressedTextKey: UInt64] = [:]
    private var lastFallbackKeyboardBucket: Int64?
    private var lastFallbackPointerBucket: Int64?

    var isRunning: Bool {
        lock.withLock { eventTap != nil }
    }

    func start() {
        lock.lock()
        let alreadyRunning = eventTap != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        let mask = Self.eventMask(for: [
            .keyDown,
            .keyUp,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ])
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: focusPetInputEventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.withLock {
            eventTap = tap
            runLoopSource = source
        }
    }

    func stop() {
        let source: CFRunLoopSource?
        let tap: CFMachPort?
        lock.lock()
        source = runLoopSource
        tap = eventTap
        runLoopSource = nil
        eventTap = nil
        keyboardCount = 0
        pointerCount = 0
        lastKeyboardEvent = nil
        pressedTextKeys = [:]
        lastFallbackKeyboardBucket = nil
        lastFallbackPointerBucket = nil
        lock.unlock()

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func drainCounts(fallbackWindowSeconds: TimeInterval?) -> InputEventCounts {
        var counts: InputEventCounts
        let shouldUseFallback: Bool
        lock.lock()
        counts = InputEventCounts(keyboardCount: keyboardCount, pointerCount: pointerCount)
        keyboardCount = 0
        pointerCount = 0
        shouldUseFallback = eventTap == nil
        lock.unlock()

        if shouldUseFallback, let fallbackWindowSeconds {
            let fallback = IdleMonitor.fallbackInputCounts(seconds: fallbackWindowSeconds)
            if counts.keyboardCount == 0 {
                counts.keyboardCount = throttledFallbackKeyboardCount(fallback.keyboardCount)
            }
            if counts.pointerCount == 0 {
                counts.pointerCount = throttledFallbackPointerCount(fallback.pointerCount)
            }
        }
        return counts
    }

    func discardCounts() {
        lock.withLock {
            keyboardCount = 0
            pointerCount = 0
            lastKeyboardEvent = nil
            pressedTextKeys = [:]
            lastFallbackKeyboardBucket = nil
            lastFallbackPointerBucket = nil
        }
    }

    fileprivate func record(eventType: CGEventType, event: CGEvent) {
        switch eventType {
        case .keyDown:
            guard Self.isEstimatedTextInput(event) else { return }
            let fingerprint = Self.keyboardEventFingerprint(for: event)
            let pressedKey = Self.pressedTextKey(for: event)
            lock.withLock {
                let isAlreadyPressed = Self.isPressedTextKeyStillDown(
                    pressedKey,
                    at: fingerprint.timestamp,
                    pressedTextKeys: pressedTextKeys
                )
                if !isAlreadyPressed,
                   !Self.isDuplicateKeyboardEvent(fingerprint, previous: lastKeyboardEvent) {
                    keyboardCount += 1
                }
                pressedTextKeys[pressedKey] = fingerprint.timestamp
                lastKeyboardEvent = fingerprint
            }
        case .keyUp:
            let pressedKey = Self.pressedTextKey(for: event)
            lock.withLock {
                _ = pressedTextKeys.removeValue(forKey: pressedKey)
            }
        case .leftMouseDown,
             .rightMouseDown,
             .otherMouseDown:
            lock.withLock {
                pointerCount += 1
            }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.withLock {
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }
        default:
            break
        }
    }

    private static func eventMask(for eventTypes: [CGEventType]) -> CGEventMask {
        eventTypes.reduce(CGEventMask(0)) { result, type in
            result | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    private static func isEstimatedTextInput(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return false
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return false
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        return !nonTextKeyCodes.contains(keyCode)
    }

    private static func keyboardEventFingerprint(for event: CGEvent) -> KeyboardEventFingerprint {
        let timestamp = event.timestamp == 0 ? DispatchTime.now().uptimeNanoseconds : event.timestamp
        let textModifierFlags: CGEventFlags = [.maskShift, .maskAlphaShift, .maskAlternate]
        return KeyboardEventFingerprint(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            modifierFlags: event.flags.intersection(textModifierFlags).rawValue,
            timestamp: timestamp
        )
    }

    private static func pressedTextKey(for event: CGEvent) -> PressedTextKey {
        PressedTextKey(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            keyboardType: event.getIntegerValueField(.keyboardEventKeyboardType)
        )
    }

    private static func isPressedTextKeyStillDown(
        _ key: PressedTextKey,
        at timestamp: UInt64,
        pressedTextKeys: [PressedTextKey: UInt64]
    ) -> Bool {
        guard let previousTimestamp = pressedTextKeys[key] else {
            return false
        }

        let elapsed = timestamp >= previousTimestamp
            ? timestamp - previousTimestamp
            : previousTimestamp - timestamp
        return elapsed <= maxPressedKeyDurationNanoseconds
    }

    private func throttledFallbackKeyboardCount(_ count: Int) -> Int {
        throttledFallbackCount(count) { bucket in
            let shouldRecord = lastFallbackKeyboardBucket != bucket
            lastFallbackKeyboardBucket = bucket
            return shouldRecord
        }
    }

    private func throttledFallbackPointerCount(_ count: Int) -> Int {
        throttledFallbackCount(count) { bucket in
            let shouldRecord = lastFallbackPointerBucket != bucket
            lastFallbackPointerBucket = bucket
            return shouldRecord
        }
    }

    private func throttledFallbackCount(_ count: Int, markBucket: (Int64) -> Bool) -> Int {
        guard count > 0 else { return 0 }
        let bucket = Int64(Date().timeIntervalSince1970 / Self.fallbackBucketSeconds)
        return lock.withLock {
            markBucket(bucket) ? 1 : 0
        }
    }

    private static func isDuplicateKeyboardEvent(
        _ event: KeyboardEventFingerprint,
        previous: KeyboardEventFingerprint?
    ) -> Bool {
        guard let previous,
              previous.keyCode == event.keyCode,
              previous.modifierFlags == event.modifierFlags else {
            return false
        }

        let elapsed = event.timestamp >= previous.timestamp
            ? event.timestamp - previous.timestamp
            : previous.timestamp - event.timestamp
        return elapsed <= duplicateKeyboardEventThresholdNanoseconds
    }

    private static let duplicateKeyboardEventThresholdNanoseconds: UInt64 = 12_000_000
    private static let maxPressedKeyDurationNanoseconds: UInt64 = 30_000_000_000
    private static let fallbackBucketSeconds: TimeInterval = 60

    private struct KeyboardEventFingerprint {
        var keyCode: Int64
        var modifierFlags: UInt64
        var timestamp: UInt64
    }

    private struct PressedTextKey: Hashable {
        var keyCode: Int64
        var keyboardType: Int64
    }

    private static let nonTextKeyCodes: Set<Int64> = [
        36, 48, 51, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
        64, 71, 72, 73, 74, 76, 79, 80, 90, 96, 97, 98, 99, 100,
        101, 103, 105, 107, 109, 111, 113, 114, 115, 116, 117,
        118, 119, 120, 121, 122, 123, 124, 125, 126
    ]
}

final class ApplicationSwitchEventMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var observer: NSObjectProtocol?
    private var currentIdentity: String?
    private var pendingSwitchCount = 0

    var isRunning: Bool {
        lock.withLock { observer != nil }
    }

    func start() {
        lock.lock()
        let alreadyRunning = observer != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        lock.withLock {
            currentIdentity = NSWorkspace.shared.frontmostApplication.map(Self.identity(for:))
        }

        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }

        lock.withLock {
            observer = token
        }
    }

    func stop() {
        let token: NSObjectProtocol?
        lock.lock()
        token = observer
        observer = nil
        currentIdentity = nil
        pendingSwitchCount = 0
        lock.unlock()

        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func drainSwitchCount(fallbackSwitchCount: Int) -> Int {
        lock.lock()
        let count = pendingSwitchCount
        pendingSwitchCount = 0
        let running = observer != nil
        lock.unlock()

        return running ? count : max(0, fallbackSwitchCount)
    }

    private func handleActivation(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        let identity = Self.identity(for: application)
        lock.withLock {
            if currentIdentity == nil {
                currentIdentity = identity
                return
            }
            guard currentIdentity != identity else { return }
            pendingSwitchCount += 1
            currentIdentity = identity
        }
    }

    private static func identity(for application: NSRunningApplication) -> String {
        "\(application.bundleIdentifier ?? "")|\(application.localizedName ?? "Unknown")"
    }
}

@MainActor
final class AppSwitchTracker {
    private var currentIdentity: String?
    private var currentCategory: ActivityCategory = .ignore
    private var currentAppSince = Date()
    private var currentCategorySince = Date()
    private var switchHistory: [Date] = []

    @discardableResult
    func update(identity: String, category: ActivityCategory, now: Date) -> Bool {
        if currentIdentity == nil {
            currentIdentity = identity
            currentCategory = category
            currentAppSince = now
            currentCategorySince = now
            return false
        }

        var didSwitch = false
        if identity != currentIdentity {
            switchHistory.append(now)
            currentIdentity = identity
            currentAppSince = now
            didSwitch = true
        }

        if category != currentCategory {
            currentCategory = category
            currentCategorySince = now
        }

        switchHistory = switchHistory.filter { now.timeIntervalSince($0) <= 15 * 60 }
        return didSwitch
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

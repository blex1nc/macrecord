import CoreGraphics
import Foundation
import MacroCore
import os

/// A system-wide mouse-button shortcut via an active event tap on its own run-loop thread.
/// The button's presses and releases are consumed (so Back/Forward don't also reach the front app);
/// drags while it is held pass through as plain moves, so the cursor keeps moving during hold-to-click.
/// While running, App Nap is held off: a napping tap thread answers late, the tap times out and the
/// front app (often a game) stops getting moves until it is re-enabled. macrecord's own synthetic clicks pass through. Needs Accessibility. Callbacks arrive on the main thread.
public final class MouseButtonTrigger {
    public private(set) var button: Int?
    public var isRunning: Bool { runLoop != nil }

    private var onPress: () -> Void = {}
    private var onRelease: () -> Void = {}
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private let ready = DispatchSemaphore(value: 0)
    private var activity: NSObjectProtocol?
    /// Tap thread only: set between the trigger's consumed press and its release.
    private var held = false
    private var foreignDrags = 0
    private static let log = Logger(subsystem: "io.github.blex1nc.macrecord", category: "mouse-trigger")

    /// What the tap saw while the trigger was held; read with `takeStats()`.
    public struct Stats: Sendable {
        /// Age of each event when the callback ran (time the event spent before reaching this tap).
        public var callbackAge = LatencyHistogram()
        /// Drags rewritten to moves while the trigger was held.
        public var rewrites = 0
        /// Of those, drags that carried another button number (a synthetic click changed the global state).
        public var foreignDrags = 0
        public init() {}
    }
    private var stats = Stats()
    private let statsLock = NSLock()
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Returns the stats gathered since the last call and resets them.
    public func takeStats() -> Stats {
        statsLock.lock(); defer { statsLock.unlock() }
        let taken = stats
        stats = Stats()
        return taken
    }

    private func record(_ event: CGEvent, rewrite: Bool, foreign: Bool) {
        let info = Self.timebase
        let age = EventAge.ns(timestamp: event.timestamp, nowTicks: mach_absolute_time(),
                              nowUptimeNs: clock_gettime_nsec_np(CLOCK_UPTIME_RAW),
                              ticksToNs: { $0 * UInt64(info.numer) / UInt64(info.denom) })
        statsLock.lock()
        if let age { stats.callbackAge.add(age) }
        if rewrite { stats.rewrites += 1 }
        if foreign { stats.foreignDrags += 1 }
        statsLock.unlock()
    }

    public init() {}

    deinit { stop() }

    /// Returns false if `button` is not allowed or the tap could not be created (no Accessibility permission).
    @discardableResult
    public func start(button: Int, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> Bool {
        stop()
        guard MouseTrigger.isAllowed(button) else { return false }
        self.button = button
        self.onPress = onPress
        self.onRelease = onRelease
        let thread = Thread { [unowned self] in self.runTapThread() }
        thread.name = "macrecord.mouse-trigger"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard runLoop != nil else { self.button = nil; return false }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                         reason: "Mouse-button shortcut event tap")
        return true
    }

    public func stop() {
        guard let runLoop else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        CFRunLoopStop(runLoop)
        ready.wait() // thread signals after leaving the run loop
        self.runLoop = nil
        button = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func runTapThread() {
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: mouseTriggerTapCallback, userInfo: refcon) else {
            ready.signal()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let loop = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(loop, source, .commonModes)
        self.tap = tap
        self.runLoop = loop
        CGEvent.tapEnable(tap: tap, enable: true)
        // Signal from inside the run loop so a stop() right after start() can't be lost.
        let ready = self.ready
        let entered = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.entry.rawValue,
                                                         false, 0) { _, _ in ready.signal() }
        CFRunLoopAddObserver(loop, entered, .defaultMode)
        CFRunLoopRun()
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(tap)
        self.tap = nil
        ready.signal()
    }

    /// Runs on the tap thread; returns true to consume the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Self.log.error("event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            break
        default:
            return false
        }
        guard let button else { return false }
        let matches = MouseTrigger.matches(buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                                           userData: event.getIntegerValueField(.eventSourceUserData),
                                           trigger: button)
        if type == .otherMouseDragged {
            // Apps never saw the press, so a drag would be wrong; consuming it would freeze the cursor.
            // Drags can carry another button number (e.g. after a synthetic click), so go by the held state.
            guard held else { return false }
            if !matches { foreignDrags += 1 }
            record(event, rewrite: true, foreign: !matches)
            event.type = .mouseMoved
            return false
        }
        guard matches else { return false }
        record(event, rewrite: false, foreign: false)
        if type == .otherMouseDown {
            held = true
            foreignDrags = 0
            DispatchQueue.main.async { [weak self] in self?.onPress() }
        } else {
            held = false
            if foreignDrags > 0 { Self.log.error("rewrote \(self.foreignDrags, privacy: .public) drags with another button number") }
            DispatchQueue.main.async { [weak self] in self?.onRelease() }
        }
        return true
    }
}

private func mouseTriggerTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                     refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon, Unmanaged<MouseButtonTrigger>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}

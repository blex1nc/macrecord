import CoreGraphics
import CSupport
import Foundation
import MacroCore

/// Listen-only tap that measures the physical motion stream while the autoclicker runs: how evenly moves arrive,
/// how late they are, how many reach apps as drags, and whether the cursor jumps. It never blocks, changes or posts
/// events. Placed at the tail, so its timings include every active tap before it (e.g. the mouse-button trigger).
public final class MotionProbe {
    public struct Stats: Sendable {
        public var motions = 0
        /// Motion events typed as drags (a button, real or synthetic, was down globally).
        public var drags = 0
        /// Position changes much larger than the event's own delta: cursor warps.
        public var jumps = 0
        /// Gaps between consecutive motion events while moving (gaps over 100 ms count as pauses and are skipped).
        public var gaps = LatencyHistogram()
        /// Age of each motion event when it reached this tap.
        public var age = LatencyHistogram()
        public init() {}
    }

    private var stats = Stats()
    private let lock = NSLock()
    private var lastArrival: UInt64 = 0
    private var lastLocation: CGPoint?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private let ready = DispatchSemaphore(value: 0)
    private static let pause = mr_ns_to_ticks(100_000_000)

    public init() {}

    deinit { stop() }

    /// Returns false if the tap could not be created.
    @discardableResult
    public func start() -> Bool {
        stop()
        lock.lock(); stats = Stats(); lastArrival = 0; lastLocation = nil; lock.unlock()
        let thread = Thread { [unowned self] in self.runTapThread() }
        thread.name = "macrecord.motion-probe"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return runLoop != nil
    }

    /// Stops the tap and returns what it measured.
    @discardableResult
    public func stop() -> Stats {
        if let runLoop {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            CFRunLoopStop(runLoop)
            ready.wait()
            self.runLoop = nil
        }
        lock.lock(); defer { lock.unlock() }
        return stats
    }

    private func runTapThread() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: motionProbeCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            ready.signal()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let loop = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(loop, source, .commonModes)
        self.tap = tap
        runLoop = loop
        CGEvent.tapEnable(tap: tap, enable: true)
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

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let now = mr_now_ticks()
        let age = EventAge.ns(timestamp: event.timestamp, nowTicks: now,
                              nowUptimeNs: clock_gettime_nsec_np(CLOCK_UPTIME_RAW), ticksToNs: mr_ticks_to_ns)
        let location = event.location
        let delta = abs(event.getDoubleValueField(.mouseEventDeltaX)) + abs(event.getDoubleValueField(.mouseEventDeltaY))
        lock.lock()
        stats.motions += 1
        if type != .mouseMoved { stats.drags += 1 }
        if let age { stats.age.add(age) }
        if lastArrival != 0, now - lastArrival <= Self.pause { stats.gaps.add(mr_ticks_to_ns(now - lastArrival)) }
        if let last = lastLocation, abs(location.x - last.x) + abs(location.y - last.y) > 4 * delta + 50 {
            stats.jumps += 1
        }
        lastArrival = now
        lastLocation = location
        lock.unlock()
    }
}

private func motionProbeCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon { Unmanaged<MotionProbe>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event) }
    return Unmanaged.passUnretained(event)
}

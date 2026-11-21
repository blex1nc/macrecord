import CoreGraphics
import CSupport
import Foundation
import MacroCore

/// High-rate clicker on a real-time thread. Schedules on absolute deadlines so the rate never drifts.
public final class AutoClicker {
    public var spinNs: UInt64 = 200_000
    /// Called on the clicker thread when it stops (limit reached or `stop()`).
    public var onFinish: (() -> Void)?
    /// Event poster override; tests set it to observe clicks without touching real input.
    /// nil delivers according to the config's `Delivery`.
    public var post: ((CGEvent) -> Void)?

    public var isRunning: Bool { mr_flag_load(running) }
    public var clickCount: Int { Int(mr_counter_load(clicks)) }

    private let running = mr_flag_create(false)!
    private let clicks = mr_counter_create()!
    private let factory = EventFactory()

    public init() {}

    deinit {
        mr_flag_store(running, false)
        mr_flag_destroy(running)
        mr_counter_destroy(clicks)
    }

    /// `targetPID` is the app that receives clicks with `.app` delivery; without it clicks go through the system.
    /// `targetWindow` (a CGWindowID of that app) tells AppKit which window the click belongs to.
    public func start(_ config: AutoClickConfig, targetPID: pid_t? = nil, targetWindow: Int64? = nil) {
        guard !isRunning else { return }
        mr_flag_store(running, true)
        mr_counter_store(clicks, 0)
        let deliver = post ?? Self.poster(config.effectiveDelivery, targetPID: targetPID, targetWindow: targetWindow)
        RealtimeThread.start(name: "macrecord.autoclicker") { [self] in run(config, deliver: deliver) }
    }

    static func poster(_ delivery: AutoClickConfig.Delivery, targetPID: pid_t?,
                       targetWindow: Int64?) -> (CGEvent) -> Void {
        if delivery == .app, let targetPID {
            // Bypasses the HID stream: no cursor warp, no global button state, so physical moves stay moves.
            return { event in
                if let targetWindow { address(event, toWindow: targetWindow) }
                event.postToPid(targetPID)
            }
        }
        if delivery == .fast {
            // After all session taps: their latency (and their view of our clicks) is skipped.
            return { $0.post(tap: .cgAnnotatedSessionEventTap) }
        }
        return { $0.post(tap: .cghidEventTap) }
    }

    /// The WindowServer fills these for HID-routed clicks; a pid-posted click without them has no window
    /// and AppKit may drop it.
    static func address(_ event: CGEvent, toWindow window: Int64) {
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: window)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: window)
    }

    /// Front-most normal-layer on-screen window of `pid`, or nil. Owner/layer/number need no Screen Recording.
    public static func frontWindowID(of pid: pid_t) -> Int64? {
        frontWindow { $0 == pid }?.window
    }

    /// Owner of the front-most normal-layer on-screen window: an independent check of the frontmost app.
    public static func frontmostWindowOwner() -> pid_t? {
        frontWindow { _ in true }?.pid
    }

    private static func frontWindow(where matches: (pid_t) -> Bool) -> (pid: pid_t, window: Int64)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        // The list is ordered front to back.
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let owner = (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init), matches(owner),
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            return (owner, Int64(number))
        }
        return nil
    }

    public func stop() {
        mr_flag_store(running, false)
    }

    private func run(_ config: AutoClickConfig, deliver: (CGEvent) -> Void) {
        var rng = SystemRandomNumberGenerator()
        factory.warmUp()
        let startTicks = mr_now_ticks()
        var target = startTicks
        var pointIndex = 0
        let hold = mr_ns_to_ticks(config.effectiveHoldNs)
        let downType = EventFactory.downType(config.button)
        let upType = EventFactory.upType(config.button)
        let clicksPerAction: Int64 = config.clickType == .double ? 2 : 1

        while mr_flag_load(running) {
            switch config.limit {
            case let .clicks(limit) where clickCount >= limit:
                break
            case let .seconds(seconds) where mr_ticks_to_ns(mr_now_ticks() - startTicks) >= UInt64(seconds * 1e9):
                break
            default:
                guard RealtimeThread.wait(until: target, spinNs: spinNs, running: running) != nil else { break }
                var point = position(config, pointIndex: &pointIndex)
                if config.positionJitter > 0 {
                    let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
                    let radius = config.positionJitter * Double.random(in: 0...1, using: &rng).squareRoot()
                    point.x += radius * cos(angle)
                    point.y += radius * sin(angle)
                }
                for clickState in 1...clicksPerAction {
                    if let down = factory.mouse(downType, at: point, button: config.button, clickCount: clickState) {
                        deliver(down)
                    }
                    if hold > 0 { _ = mr_wait_until(mr_now_ticks() + hold, spinNs) }
                    if let up = factory.mouse(upType, at: point, button: config.button, clickCount: clickState) {
                        deliver(up)
                    }
                }
                mr_counter_add(clicks, 1)
                let random = config.timingJitter > 0 ? Double.random(in: -1...1, using: &rng) : 0
                target &+= mr_ns_to_ticks(config.jitteredIntervalNs(random: random))
                // If we fell far behind (system stall), resync instead of bursting to catch up.
                let now = mr_now_ticks()
                if now > target &+ mr_ns_to_ticks(50_000_000) { target = now }
                continue
            }
            break
        }
        mr_flag_store(running, false)
        onFinish?()
    }

    private func position(_ config: AutoClickConfig, pointIndex: inout Int) -> CGPoint {
        switch config.target {
        case .cursor:
            return CGEvent(source: nil)?.location ?? .zero
        case let .fixed(x, y):
            return CGPoint(x: x, y: y)
        case let .points(points):
            guard !points.isEmpty else { return CGEvent(source: nil)?.location ?? .zero }
            let p = points[pointIndex % points.count]
            pointIndex += 1
            return CGPoint(x: p.x, y: p.y)
        }
    }
}

import CoreGraphics
import CSupport
import Foundation
import MacroCore

/// High-rate clicker on a real-time thread. Schedules on absolute deadlines so the rate never drifts.
public final class AutoClicker {
    public var spinNs: UInt64 = 200_000
    /// Called on the clicker thread when it stops (limit reached or `stop()`).
    public var onFinish: (() -> Void)?

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

    public func start(_ config: AutoClickConfig) {
        guard !isRunning else { return }
        mr_flag_store(running, true)
        mr_counter_store(clicks, 0)
        RealtimeThread.start(name: "macrecord.autoclicker") { [self] in run(config) }
    }

    public func stop() {
        mr_flag_store(running, false)
    }

    private func run(_ config: AutoClickConfig) {
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
                    factory.mouse(downType, at: point, button: config.button, clickCount: clickState)?
                        .post(tap: .cghidEventTap)
                    if hold > 0 { _ = mr_wait_until(mr_now_ticks() + hold, spinNs) }
                    factory.mouse(upType, at: point, button: config.button, clickCount: clickState)?
                        .post(tap: .cghidEventTap)
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

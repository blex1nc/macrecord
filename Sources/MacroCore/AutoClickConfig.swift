import Foundation

public struct AutoClickConfig: Codable, Equatable, Sendable {
    public enum ClickType: String, Codable, Sendable, CaseIterable { case single, double }
    public enum Mode: String, Codable, Sendable, CaseIterable { case toggle, hold }

    public enum Target: Codable, Equatable, Sendable {
        case cursor
        case fixed(x: Double, y: Double)
        /// Cycles through the points in order.
        case points([Point])
    }

    public struct Point: Codable, Equatable, Sendable, Hashable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public enum Limit: Codable, Equatable, Sendable {
        case none
        case clicks(Int)
        case seconds(Double)
    }

    public var clicksPerSecond: Double
    public var button: MouseButton
    public var clickType: ClickType
    public var target: Target
    /// Random timing variation as a fraction of the interval (0...0.9).
    public var timingJitter: Double
    /// Random position variation radius in points.
    public var positionJitter: Double
    /// Time the button stays down per click.
    public var holdDurationMs: Double
    public var limit: Limit
    public var mode: Mode

    public init(clicksPerSecond: Double = 10, button: MouseButton = .left, clickType: ClickType = .single,
                target: Target = .cursor, timingJitter: Double = 0, positionJitter: Double = 0,
                holdDurationMs: Double = 0, limit: Limit = .none, mode: Mode = .toggle) {
        self.clicksPerSecond = clicksPerSecond
        self.button = button
        self.clickType = clickType
        self.target = target
        self.timingJitter = timingJitter
        self.positionJitter = positionJitter
        self.holdDurationMs = holdDurationMs
        self.limit = limit
        self.mode = mode
    }

    public static let cpsRange: ClosedRange<Double> = 0.1...2000

    public var intervalNs: UInt64 {
        let cps = min(max(clicksPerSecond, Self.cpsRange.lowerBound), Self.cpsRange.upperBound)
        return UInt64(1_000_000_000 / cps)
    }

    /// Interval for the n-th click, applying jitter from `random` in [-1, 1].
    public func jitteredIntervalNs(random: Double) -> UInt64 {
        let jitter = min(max(timingJitter, 0), 0.9)
        let factor = 1 + jitter * min(max(random, -1), 1)
        return UInt64(Double(intervalNs) * factor)
    }

    /// Hold time is capped so a click never overlaps the next one.
    public var effectiveHoldNs: UInt64 {
        let hold = UInt64(max(holdDurationMs, 0) * 1_000_000)
        let maxHold = intervalNs / UInt64(clickType == .double ? 4 : 2)
        return min(hold, maxHold)
    }
}

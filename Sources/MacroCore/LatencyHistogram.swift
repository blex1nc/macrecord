/// Fixed-size log2 histogram of durations, cheap enough to update from event-tap callbacks.
/// Bucket `i` holds values below 2^i µs, so percentiles are upper bounds (at most 2× the true value).
public struct LatencyHistogram: Sendable, Equatable {
    public private(set) var count = 0
    public private(set) var maxNs: UInt64 = 0
    private var buckets = [Int](repeating: 0, count: 32)

    public init() {}

    public mutating func add(_ ns: UInt64) {
        count += 1
        maxNs = max(maxNs, ns)
        let us = ns / 1000
        let index = us == 0 ? 0 : min(buckets.count - 1, UInt64.bitWidth - us.leadingZeroBitCount)
        buckets[index] += 1
    }

    /// Upper bound of the bucket holding the `p`-th percentile (0...1), capped at the observed maximum.
    public func percentileNs(_ p: Double) -> UInt64 {
        guard count > 0 else { return 0 }
        let rank = max(1, Int((Double(count) * min(max(p, 0), 1)).rounded(.up)))
        var seen = 0
        for (index, n) in buckets.enumerated() {
            seen += n
            if seen >= rank { return min(maxNs, (UInt64(1) << UInt64(index)) * 1000) }
        }
        return maxNs
    }
}

/// CGEvent timestamps are documented as nanoseconds but carry mach ticks on some systems.
/// Picks whichever reading gives a plausible age (0...10 s) and returns it in nanoseconds.
public enum EventAge {
    public static func ns(timestamp: UInt64, nowTicks: UInt64, nowUptimeNs: UInt64,
                          ticksToNs: (UInt64) -> UInt64) -> UInt64? {
        let limit: UInt64 = 10_000_000_000
        guard timestamp > 0 else { return nil }
        if timestamp <= nowTicks {
            let age = ticksToNs(nowTicks - timestamp)
            if age <= limit { return age }
        }
        if timestamp <= nowUptimeNs, nowUptimeNs - timestamp <= limit { return nowUptimeNs - timestamp }
        return nil
    }
}

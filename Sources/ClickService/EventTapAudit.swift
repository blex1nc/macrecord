import AppKit
import CoreGraphics

/// Lists other apps' active (filtering) event taps that see mouse clicks. Every system-delivered click waits for each
/// of them in turn, and the mouse motion queued behind the click waits too: a tap that does slow work per click
/// makes the camera in a game stutter. Read-only (CGGetEventTapList). The reported average latency is unreliable
/// (values of minutes occur), so callers decide from their own measurements and use this list only for names.
public enum EventTapAudit {
    public struct SlowTap: Sendable, Equatable {
        public let app: String
        public let pid: pid_t
        public let avgMs: Double
    }

    private static let mouseMask: CGEventMask = [CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown,
                                                 .rightMouseUp, .otherMouseDown, .otherMouseUp]
        .reduce(0) { $0 | CGEventMask(1) << $1.rawValue }

    /// One entry per app, highest reported average first; `excluding` is typically macrecord and the helper.
    public static func activeMouseTaps(excluding: Set<pid_t>) -> [SlowTap] {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return [] }
        count += 8 // taps can appear between the two calls
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &taps, &count) == .success else { return [] }
        var slowest: [pid_t: Double] = [:]
        for tap in taps.prefix(Int(count)) where tap.enabled && tap.options == .defaultTap
            && tap.processBeingTapped == 0 && tap.eventsOfInterest & mouseMask != 0
            && !excluding.contains(tap.tappingProcess) {
            let ms = Double(tap.avgUsecLatency) / 1000
            slowest[tap.tappingProcess] = max(slowest[tap.tappingProcess] ?? 0, ms)
        }
        return slowest.map { pid, ms in
            SlowTap(app: NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)", pid: pid, avgMs: ms)
        }
        .sorted { $0.avgMs > $1.avgMs }
    }
}

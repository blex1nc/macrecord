import Foundation

/// Pure transformations used by the editor. All keep the absolute timing of the remaining events.
public enum MacroEditing {
    /// Removes events at `offsets`; their delays are carried into the next kept event.
    public static func remove(_ events: [MacroEvent], at offsets: IndexSet) -> [MacroEvent] {
        RecordingSanitizer.carryDelays(events, droppingIndices: Set(offsets))
    }

    /// Removes all plain mouse moves (drags are kept so drag gestures still work).
    public static func removeMouseMoves(_ events: [MacroEvent]) -> [MacroEvent] {
        let offsets = events.indices.filter { if case .mouseMove = events[$0].kind { return true }; return false }
        return remove(events, at: IndexSet(offsets))
    }

    /// Multiplies every delay by `factor` (e.g. 0.5 = twice as fast).
    public static func scaleDelays(_ events: [MacroEvent], by factor: Double) -> [MacroEvent] {
        events.map { var e = $0; e.delayNs = UInt64(max(0, Double(e.delayNs) * factor)); return e }
    }

    /// Simplifies runs of consecutive mouse moves with Ramer–Douglas–Peucker.
    /// Removed moves pass their delay and relative delta to the next kept move.
    public static func simplifyMouseMoves(_ events: [MacroEvent], tolerance: Double) -> [MacroEvent] {
        var drop = Set<Int>()
        var runStart: Int?
        for i in 0...events.count {
            let isMove: Bool
            if i < events.count, case .mouseMove = events[i].kind { isMove = true } else { isMove = false }
            if isMove {
                if runStart == nil { runStart = i }
            } else if let start = runStart {
                let run = Array(start..<i)
                let points = run.map { events[$0].kind.position! }
                let keep = rdp(points, tolerance: tolerance)
                for (j, index) in run.enumerated() where !keep.contains(j) { drop.insert(index) }
                runStart = nil
            }
        }
        guard !drop.isEmpty else { return events }

        var result: [MacroEvent] = []
        var carriedDelay: UInt64 = 0
        var carriedDX: Int64 = 0, carriedDY: Int64 = 0
        for (i, event) in events.enumerated() {
            if drop.contains(i) {
                carriedDelay &+= event.delayNs
                if case let .mouseMove(_, _, dx, dy) = event.kind { carriedDX += dx; carriedDY += dy }
                continue
            }
            var kept = event
            kept.delayNs &+= carriedDelay
            if case let .mouseMove(x, y, dx, dy) = kept.kind {
                kept.kind = .mouseMove(x: x, y: y, dx: dx + carriedDX, dy: dy + carriedDY)
                carriedDX = 0; carriedDY = 0
            }
            carriedDelay = 0
            result.append(kept)
        }
        return result
    }

    /// Indices (into `points`) kept by Ramer–Douglas–Peucker. Endpoints are always kept.
    static func rdp(_ points: [(x: Double, y: Double)], tolerance: Double) -> Set<Int> {
        guard points.count > 2 else { return Set(points.indices) }
        var keep: Set<Int> = [0, points.count - 1]
        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var maxDistance = -1.0, index = a
            for i in (a + 1)..<b {
                let d = distance(points[i], toSegment: points[a], points[b])
                if d > maxDistance { maxDistance = d; index = i }
            }
            if maxDistance > tolerance {
                keep.insert(index)
                stack.append((a, index))
                stack.append((index, b))
            }
        }
        return keep
    }

    static func distance(_ p: (x: Double, y: Double), toSegment a: (x: Double, y: Double),
                         _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

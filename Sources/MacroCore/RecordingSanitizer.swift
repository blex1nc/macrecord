/// Cleans a raw recording: removes artifacts of the start/stop shortcuts and unmatched releases.
public enum RecordingSanitizer {
    public static func sanitize(_ events: [MacroEvent], stopKeyCode: UInt16? = nil) -> [MacroEvent] {
        var result = stripTrailingShortcut(events, stopKeyCode: stopKeyCode)
        // The start shortcut is released after the tap starts: key-up first, then modifiers.
        // Drop the unmatched key-up before stripping the now-leading modifier changes.
        result = dropUnmatchedReleases(result)
        result = stripLeadingModifierChanges(result)
        if !result.isEmpty { result[0].delayNs = 0 }
        return result
    }

    /// When recording is stopped from macrecord's own UI, the clicks on the Stop control were recorded too.
    /// Cuts from the earliest mouse-down of the trailing run of clicks that landed on our own UI
    /// (`isOwnUI` receives global display coordinates). Clicks elsewhere are always kept.
    public static func trimTrailingUIClicks(_ events: [MacroEvent], isOwnUI: (Double, Double) -> Bool) -> [MacroEvent] {
        var cut: Int?
        for i in events.indices.reversed() {
            guard case let .mouseDown(_, x, y, _) = events[i].kind else { continue }
            guard isOwnUI(x, y) else { break }
            cut = i
        }
        guard let cut else { return events }
        return Array(events[..<cut])
    }

    /// Removes the tail made of the stop key and modifier changes (the shortcut that ended recording).
    static func stripTrailingShortcut(_ events: [MacroEvent], stopKeyCode: UInt16?) -> [MacroEvent] {
        guard let stopKeyCode else { return events }
        var end = events.count
        while end > 0 {
            switch events[end - 1].kind {
            case .flagsChanged:
                end -= 1
            case let .keyDown(code, _) where code == stopKeyCode, let .keyUp(code, _) where code == stopKeyCode:
                end -= 1
            default:
                return Array(events[..<end])
            }
        }
        return []
    }

    /// Modifier releases from the start shortcut arrive right after recording begins.
    /// Key events carry their own flags, so leading modifier changes are safe to drop.
    static func stripLeadingModifierChanges(_ events: [MacroEvent]) -> [MacroEvent] {
        guard let first = events.firstIndex(where: { if case .flagsChanged = $0.kind { return false }; return true }) else {
            return []
        }
        return carryDelays(events, droppingIndices: Set(0..<first))
    }

    /// Drops key/mouse releases whose press happened before recording started.
    static func dropUnmatchedReleases(_ events: [MacroEvent]) -> [MacroEvent] {
        var keysDown = Set<UInt16>()
        var buttonsDown = Set<MouseButton>()
        var drop = Set<Int>()
        for (i, event) in events.enumerated() {
            switch event.kind {
            case let .keyDown(code, _): keysDown.insert(code)
            case let .keyUp(code, _): if keysDown.remove(code) == nil { drop.insert(i) }
            case let .mouseDown(button, _, _, _): buttonsDown.insert(button)
            case let .mouseUp(button, _, _, _): if buttonsDown.remove(button) == nil { drop.insert(i) }
            default: break
            }
        }
        return carryDelays(events, droppingIndices: drop)
    }

    /// Removes events while keeping absolute timing of the remaining ones.
    static func carryDelays(_ events: [MacroEvent], droppingIndices drop: Set<Int>) -> [MacroEvent] {
        guard !drop.isEmpty else { return events }
        var result: [MacroEvent] = []
        result.reserveCapacity(events.count - drop.count)
        var carried: UInt64 = 0
        for (i, event) in events.enumerated() {
            if drop.contains(i) {
                carried &+= event.delayNs
            } else {
                var kept = event
                kept.delayNs &+= carried
                carried = 0
                result.append(kept)
            }
        }
        return result
    }
}

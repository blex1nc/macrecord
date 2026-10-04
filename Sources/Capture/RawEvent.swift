import CoreGraphics
import CSupport
import Darwin
import MacroCore

/// Plain-old-data snapshot of a CGEvent, cheap to copy on the tap thread.
public struct RawEvent: Sendable {
    public var type: UInt32
    public var timestamp: UInt64
    public var receivedTicks: UInt64
    public var x: Double
    public var y: Double
    public var dx: Int64
    public var dy: Int64
    public var button: Int64
    public var clickCount: Int64
    public var keyCode: UInt16
    public var flags: UInt64
    public var scrollX: Int32
    public var scrollY: Int32
    public var continuous: Bool
    public var userData: Int64

    public init(type: CGEventType, event: CGEvent, receivedTicks: UInt64) {
        self.type = type.rawValue
        timestamp = event.timestamp
        self.receivedTicks = receivedTicks
        let location = event.location
        x = location.x
        y = location.y
        dx = event.getIntegerValueField(.mouseEventDeltaX)
        dy = event.getIntegerValueField(.mouseEventDeltaY)
        button = event.getIntegerValueField(.mouseEventButtonNumber)
        clickCount = event.getIntegerValueField(.mouseEventClickState)
        keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        flags = event.flags.rawValue
        scrollY = Int32(truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        scrollX = Int32(truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        userData = event.getIntegerValueField(.eventSourceUserData)
    }
}

public enum RawEventConverter {
    /// Converts raw events to macro events with nanosecond delays between them.
    public static func convert(_ raw: [RawEvent]) -> [MacroEvent] {
        let times = timestampsNs(raw)
        var result: [MacroEvent] = []
        result.reserveCapacity(raw.count)
        var previous: UInt64?
        for (i, event) in raw.enumerated() {
            guard let kind = kind(for: event) else { continue }
            let t = times[i]
            let delay = previous.map { t > $0 ? t - $0 : 0 } ?? 0
            previous = t
            result.append(MacroEvent(delayNs: delay, kind: kind))
        }
        return result
    }

    /// CGEvent timestamps are documented as nanoseconds but are mach ticks on some hardware.
    /// Detect the unit by comparing against the receive time; fall back to receive time if unusable.
    static func timestampsNs(_ raw: [RawEvent]) -> [UInt64] {
        guard let probe = raw.first(where: { $0.timestamp != 0 }) else {
            return raw.map { mr_ticks_to_ns($0.receivedTicks) }
        }
        let receivedNs = mr_ticks_to_ns(probe.receivedTicks)
        let diffAsTicks = probe.receivedTicks.distance(to: probe.timestamp).magnitude
        let diffAsNs = receivedNs.distance(to: probe.timestamp).magnitude
        let tolerance: UInt64 = 5_000_000_000
        let unit: ((UInt64) -> UInt64)?
        if diffAsNs <= diffAsTicks && UInt64(diffAsNs) < tolerance {
            unit = { $0 }
        } else if UInt64(mr_ticks_to_ns(UInt64(diffAsTicks))) < tolerance {
            unit = { mr_ticks_to_ns($0) }
        } else {
            unit = nil
        }
        return raw.map { event in
            if let unit, event.timestamp != 0 { return unit(event.timestamp) }
            return mr_ticks_to_ns(event.receivedTicks)
        }
    }

    static func kind(for e: RawEvent) -> MacroEvent.Kind? {
        guard let type = CGEventType(rawValue: e.type) else { return nil }
        let button = MouseButton(rawValue: Int(e.button)) ?? .center
        switch type {
        case .mouseMoved:
            return .mouseMove(x: e.x, y: e.y, dx: e.dx, dy: e.dy)
        case .leftMouseDragged:
            return .mouseDrag(button: .left, x: e.x, y: e.y, dx: e.dx, dy: e.dy)
        case .rightMouseDragged:
            return .mouseDrag(button: .right, x: e.x, y: e.y, dx: e.dx, dy: e.dy)
        case .otherMouseDragged:
            return .mouseDrag(button: button, x: e.x, y: e.y, dx: e.dx, dy: e.dy)
        case .leftMouseDown:
            return .mouseDown(button: .left, x: e.x, y: e.y, clickCount: e.clickCount)
        case .leftMouseUp:
            return .mouseUp(button: .left, x: e.x, y: e.y, clickCount: e.clickCount)
        case .rightMouseDown:
            return .mouseDown(button: .right, x: e.x, y: e.y, clickCount: e.clickCount)
        case .rightMouseUp:
            return .mouseUp(button: .right, x: e.x, y: e.y, clickCount: e.clickCount)
        case .otherMouseDown:
            return .mouseDown(button: button, x: e.x, y: e.y, clickCount: e.clickCount)
        case .otherMouseUp:
            return .mouseUp(button: button, x: e.x, y: e.y, clickCount: e.clickCount)
        case .scrollWheel:
            return .scroll(dx: e.scrollX, dy: e.scrollY, continuous: e.continuous)
        case .keyDown:
            return .keyDown(keyCode: e.keyCode, flags: e.flags)
        case .keyUp:
            return .keyUp(keyCode: e.keyCode, flags: e.flags)
        case .flagsChanged:
            return .flagsChanged(keyCode: e.keyCode, flags: e.flags)
        default:
            return nil
        }
    }
}

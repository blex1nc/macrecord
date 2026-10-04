import CoreGraphics
import MacroCore

/// Builds CGEvents for macro events. All events carry `macrecordEventTag` via the shared source.
public final class EventFactory {
    public let source: CGEventSource

    public init() {
        // Private state keeps the user's physically held modifiers out of synthesized events.
        source = CGEventSource(stateID: .privateState) ?? CGEventSource(stateID: .hidSystemState)!
        source.userData = macrecordEventTag
        // Default suppression blocks the user's own input briefly after every post ("laggy" feel).
        source.localEventsSuppressionInterval = 0
    }

    /// A no-op event: travels the same path to the WindowServer but has no effect.
    public func null() -> CGEvent? {
        CGEvent(source: source)
    }

    /// The first post sets up the WindowServer connection and can take ~20 ms.
    /// Doing it before the schedule starts keeps that cost out of the first event's timing.
    public func warmUp() {
        null()?.post(tap: .cghidEventTap)
    }

    public func mouse(_ type: CGEventType, at point: CGPoint, button: MouseButton, clickCount: Int64 = 1) -> CGEvent? {
        let cgButton = CGMouseButton(rawValue: UInt32(button.rawValue)) ?? .center
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                  mouseButton: cgButton) else { return nil }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        event.setIntegerValueField(.mouseEventClickState, value: max(clickCount, 1))
        return event
    }

    public func make(_ kind: MacroEvent.Kind) -> CGEvent? {
        switch kind {
        case let .mouseMove(x, y, dx, dy):
            let event = mouse(.mouseMoved, at: CGPoint(x: x, y: y), button: .left)
            event?.setIntegerValueField(.mouseEventDeltaX, value: dx)
            event?.setIntegerValueField(.mouseEventDeltaY, value: dy)
            return event
        case let .mouseDrag(button, x, y, dx, dy):
            let event = mouse(Self.dragType(button), at: CGPoint(x: x, y: y), button: button)
            event?.setIntegerValueField(.mouseEventDeltaX, value: dx)
            event?.setIntegerValueField(.mouseEventDeltaY, value: dy)
            return event
        case let .mouseDown(button, x, y, clickCount):
            return mouse(Self.downType(button), at: CGPoint(x: x, y: y), button: button, clickCount: clickCount)
        case let .mouseUp(button, x, y, clickCount):
            return mouse(Self.upType(button), at: CGPoint(x: x, y: y), button: button, clickCount: clickCount)
        case let .scroll(dx, dy, continuous):
            let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                wheel1: dy, wheel2: dx, wheel3: 0)
            event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
            return event
        case let .keyDown(keyCode, flags):
            return key(keyCode, down: true, flags: flags)
        case let .keyUp(keyCode, flags):
            return key(keyCode, down: false, flags: flags)
        case let .flagsChanged(keyCode, flags):
            let event = key(keyCode, down: true, flags: flags)
            event?.type = .flagsChanged
            return event
        case .waitForPixel, .activateApp, .delay:
            return nil
        }
    }

    public func key(_ keyCode: UInt16, down: Bool, flags: UInt64) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
        event?.flags = CGEventFlags(rawValue: flags)
        return event
    }

    static func downType(_ button: MouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseDown
        case .right: return .rightMouseDown
        default: return .otherMouseDown
        }
    }

    static func upType(_ button: MouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseUp
        case .right: return .rightMouseUp
        default: return .otherMouseUp
        }
    }

    static func dragType(_ button: MouseButton) -> CGEventType {
        switch button {
        case .left: return .leftMouseDragged
        case .right: return .rightMouseDragged
        default: return .otherMouseDragged
        }
    }
}

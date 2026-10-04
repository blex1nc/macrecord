import Foundation

public extension MacroEvent.Kind {
    /// Short, fixed label for list views (also the localization key).
    var title: String {
        switch self {
        case .mouseMove: return "Move"
        case .mouseDrag: return "Drag"
        case .mouseDown: return "Mouse down"
        case .mouseUp: return "Mouse up"
        case .scroll: return "Scroll"
        case .keyDown: return "Key down"
        case .keyUp: return "Key up"
        case .flagsChanged: return "Modifier"
        case .waitForPixel: return "Wait for pixel"
        case .activateApp: return "Activate app"
        case .delay: return "Delay"
        }
    }

    /// Parameters shown next to the title.
    var detail: String {
        switch self {
        case let .mouseMove(x, y, _, _):
            return Self.point(x, y)
        case let .mouseDrag(button, x, y, _, _), let .mouseUp(button, x, y, _):
            return "\(button.name) \(Self.point(x, y))"
        case let .mouseDown(button, x, y, count):
            return "\(button.name) \(Self.point(x, y))" + (count > 1 ? " ×\(count)" : "")
        case let .scroll(dx, dy, _):
            return "dx \(dx), dy \(dy)"
        case let .keyDown(code, flags), let .keyUp(code, flags):
            return Self.keyLabel(code, flags)
        case let .flagsChanged(code, _):
            return KeyNames.name(for: code)
        case .delay:
            return ""
        case let .waitForPixel(x, y, rgb, tolerance, timeoutMs):
            return String(format: "(%d, %d) #%06X ±%d", Int(x), Int(y), rgb, tolerance)
                + (timeoutMs == 0 ? "" : ", \(timeoutMs) ms")
        case let .activateApp(bundleID):
            return bundleID
        }
    }

    static func point(_ x: Double, _ y: Double) -> String { "(\(Int(x.rounded())), \(Int(y.rounded())))" }

    static func keyLabel(_ code: UInt16, _ flags: UInt64) -> String {
        ModifierFlags(rawValue: flags).intersection(.shortcutMask).symbols + KeyNames.name(for: code)
    }
}

public extension MouseButton {
    var name: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .center: return "Middle"
        case .back: return "Back"
        case .forward: return "Forward"
        }
    }
}

import Foundation

public enum MouseButton: Int, Codable, Sendable, CaseIterable {
    case left = 0, right = 1, center = 2, back = 3, forward = 4
}

/// A single recorded or authored action. `delayNs` is relative to the previous event.
/// `id` is in-memory identity for editing; it is not persisted (recordings hold ~1000 events per second).
public struct MacroEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var delayNs: UInt64
    public var kind: Kind

    public init(id: UUID = UUID(), delayNs: UInt64, kind: Kind) {
        self.id = id
        self.delayNs = delayNs
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case delayNs, kind }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(delayNs: try container.decode(UInt64.self, forKey: .delayNs),
                  kind: try container.decode(Kind.self, forKey: .kind))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(delayNs, forKey: .delayNs)
        try container.encode(kind, forKey: .kind)
    }

    /// Equality ignores `id` so a saved and reloaded macro compares equal.
    public static func == (lhs: MacroEvent, rhs: MacroEvent) -> Bool {
        lhs.delayNs == rhs.delayNs && lhs.kind == rhs.kind
    }

    public enum Kind: Codable, Equatable, Sendable {
        /// Absolute position (global display points, top-left origin) plus raw relative delta for games.
        case mouseMove(x: Double, y: Double, dx: Int64, dy: Int64)
        case mouseDrag(button: MouseButton, x: Double, y: Double, dx: Int64, dy: Int64)
        case mouseDown(button: MouseButton, x: Double, y: Double, clickCount: Int64)
        case mouseUp(button: MouseButton, x: Double, y: Double, clickCount: Int64)
        /// Pixel deltas; `continuous` is true for trackpads / Magic Mouse.
        case scroll(dx: Int32, dy: Int32, continuous: Bool)
        /// Virtual key code + modifier flags; layout independent.
        case keyDown(keyCode: UInt16, flags: UInt64)
        case keyUp(keyCode: UInt16, flags: UInt64)
        case flagsChanged(keyCode: UInt16, flags: UInt64)
        /// Blocks until the pixel at (x, y) matches `rgb` within `tolerance` (0–255 per channel) or times out.
        case waitForPixel(x: Double, y: Double, rgb: UInt32, tolerance: UInt8, timeoutMs: UInt32)
        /// Brings the app with this bundle identifier to the front.
        case activateApp(bundleID: String)
        /// Does nothing; its `delayNs` is a pause.
        case delay
    }
}

public extension MacroEvent.Kind {
    var isMouseMotion: Bool {
        switch self {
        case .mouseMove, .mouseDrag: return true
        default: return false
        }
    }

    var position: (x: Double, y: Double)? {
        switch self {
        case let .mouseMove(x, y, _, _), let .mouseDrag(_, x, y, _, _),
             let .mouseDown(_, x, y, _), let .mouseUp(_, x, y, _), let .waitForPixel(x, y, _, _, _):
            return (x, y)
        default:
            return nil
        }
    }
}

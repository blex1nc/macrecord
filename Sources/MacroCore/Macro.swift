import Foundation

/// Tag stamped on every event macrecord posts, so recorders/hotkey taps can ignore our own output.
public let macrecordEventTag: Int64 = 0x6D61_6372_6563 // "macrec"

public struct Macro: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var events: [MacroEvent]
    public var options: PlaybackOptions
    public var hotkey: KeyCombo?
    /// When set, this is a JavaScript macro and `events` is unused.
    public var script: String?

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), events: [MacroEvent] = [],
                options: PlaybackOptions = PlaybackOptions(), hotkey: KeyCombo? = nil, script: String? = nil) {
        self.schemaVersion = Macro.currentSchemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.events = events
        self.options = options
        self.hotkey = hotkey
        self.script = script
    }

    public var isScript: Bool { script != nil }

    public var durationNs: UInt64 { events.reduce(0) { $0 &+ $1.delayNs } }
}

public struct PlaybackOptions: Codable, Equatable, Sendable {
    /// 0 means loop forever.
    public var loopCount: Int
    /// 1.0 = recorded speed. Clamped to 0.1...10.
    public var speed: Double
    /// Pause inserted between loops.
    public var loopDelayMs: UInt32
    /// Post mouse moves as raw deltas only (for games that read relative motion).
    public var relativeMouse: Bool

    public init(loopCount: Int = 1, speed: Double = 1.0, loopDelayMs: UInt32 = 0, relativeMouse: Bool = false) {
        self.loopCount = loopCount
        self.speed = speed
        self.loopDelayMs = loopDelayMs
        self.relativeMouse = relativeMouse
    }

    public static let speedRange: ClosedRange<Double> = 0.1...10

    public var clampedSpeed: Double { min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound) }
}

/// A global shortcut: virtual key code + modifier flags (CGEventFlags raw bits, device-independent part).
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

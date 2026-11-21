import Foundation
import MacroCore

/// Everything the click engine needs from the app.
public struct ClickServiceSettings: Codable, Equatable, Sendable {
    public var autoclick: AutoClickConfig
    /// CGEvent button number of the mouse trigger, or nil.
    public var triggerButton: Int?
    /// False while the app is recording/playing or the button field is listening: the trigger tap is removed.
    public var triggerArmed: Bool
    /// Apps that never receive `.app` delivery (macrecord itself); clicks fall back to system delivery.
    public var excludedPIDs: [Int32]

    public init(autoclick: AutoClickConfig, triggerButton: Int?, triggerArmed: Bool, excludedPIDs: [Int32]) {
        self.autoclick = autoclick
        self.triggerButton = triggerButton
        self.triggerArmed = triggerArmed
        self.excludedPIDs = excludedPIDs
    }
}

public enum ClickTrigger: String, Codable, Sendable {
    case hotkey, mouseButton, app
}

/// App → engine, one JSON object per line on the helper's stdin.
public enum AgentCommand: Codable, Equatable, Sendable {
    case apply(ClickServiceSettings)
    case start(ClickTrigger)
    case stop
}

/// Engine → app, one JSON object per line on the helper's stdout.
public enum ClickServiceEvent: Codable, Equatable, Sendable {
    /// First line from the helper: whether it may tap and post events.
    case ready(accessibility: Bool, postEvents: Bool)
    case started(delivery: AutoClickConfig.Delivery, pid: Int32?)
    case progress(clicks: Int)
    case stopped(clicks: Int)
    /// The mouse trigger's tap could not be created (no Accessibility permission).
    case triggerUnavailable
    /// Mouse motion stalled behind system-delivered clicks; these apps' active mouse taps are the suspects.
    case slowTaps([String])
}

/// Newline-delimited JSON framing shared by both ends.
public enum AgentWire {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        var data = (try? JSONEncoder().encode(value)) ?? Data()
        data.append(0x0A)
        return data
    }

    /// Splits complete lines off `buffer` and decodes them; a trailing partial line stays in `buffer`.
    /// Undecodable lines are skipped.
    public static func decodeLines<T: Decodable>(_ type: T.Type, from buffer: inout Data) -> [T] {
        var values: [T] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let value = try? JSONDecoder().decode(T.self, from: line) { values.append(value) }
        }
        return values
    }
}

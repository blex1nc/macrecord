/// Device-independent modifier bits, matching `CGEventFlags` raw values.
public struct ModifierFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let capsLock = ModifierFlags(rawValue: 0x0001_0000)
    public static let shift = ModifierFlags(rawValue: 0x0002_0000)
    public static let control = ModifierFlags(rawValue: 0x0004_0000)
    public static let option = ModifierFlags(rawValue: 0x0008_0000)
    public static let command = ModifierFlags(rawValue: 0x0010_0000)
    public static let function = ModifierFlags(rawValue: 0x0080_0000)

    /// Modifiers that matter for shortcut matching.
    public static let shortcutMask: ModifierFlags = [.shift, .control, .option, .command]

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

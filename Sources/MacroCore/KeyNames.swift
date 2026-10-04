/// Human-readable names for macOS virtual key codes (ANSI layout).
public enum KeyNames {
    public static func name(for keyCode: UInt16) -> String {
        table[keyCode] ?? "key \(keyCode)"
    }

    /// Reverse lookup used by scripts: "a", "R", "space", "return", "esc", "f5", "left"…
    public static func code(for name: String) -> UInt16? {
        let lowered = name.lowercased()
        if let alias = aliases[lowered] { return alias }
        return table.first { $0.value.lowercased() == lowered }?.key
    }

    static let aliases: [String: UInt16] = [
        "space": 49, "return": 36, "enter": 36, "tab": 48, "delete": 51, "backspace": 51, "esc": 53,
        "escape": 53, "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "forwarddelete": 117, "cmd": 55, "shift": 56, "capslock": 57,
        "option": 58, "alt": 58, "ctrl": 59, "control": 59,
    ]

    public static func describe(_ combo: KeyCombo) -> String {
        ModifierFlags(rawValue: combo.modifiers).intersection(.shortcutMask).symbols + name(for: combo.keyCode)
    }

    static let table: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 54: "Right ⌘", 55: "⌘",
        56: "⇧", 57: "⇪", 58: "⌥", 59: "⌃", 60: "Right ⇧", 61: "Right ⌥", 62: "Right ⌃", 63: "fn",
        64: "F17", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Clear", 75: "Keypad /",
        76: "Keypad ↩", 78: "Keypad -", 79: "F18", 80: "F19", 81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1",
        84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7",
        90: "F20", 91: "Keypad 8", 92: "Keypad 9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

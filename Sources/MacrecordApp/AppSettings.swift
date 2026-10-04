import Foundation
import MacroCore

struct AppSettings: Codable, Equatable {
    var recordHotkey = KeyCombo(keyCode: 15, modifiers: ModifierFlags([.option, .command]).rawValue)    // ⌥⌘R
    var playHotkey = KeyCombo(keyCode: 35, modifiers: ModifierFlags([.option, .command]).rawValue)      // ⌥⌘P
    var stopHotkey = KeyCombo(keyCode: 53, modifiers: ModifierFlags([.command]).rawValue)               // ⌘⎋
    var autoclickHotkey = KeyCombo(keyCode: 0, modifiers: ModifierFlags([.option, .command]).rawValue)  // ⌥⌘A
    var captureMouseMoves = true
    var stopOnUserInput = true
    var autoclick = AutoClickConfig()

    var hotkeys: [KeyCombo] { [recordHotkey, playHotkey, stopHotkey, autoclickHotkey] }

    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

import AppKit
import MacroCore
import SwiftUI

/// Click, then press a shortcut. Esc cancels, Delete clears (when clearing is allowed).
struct HotkeyField: View {
    @Binding var combo: KeyCombo?
    var allowsClear = true
    @State private var listening = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                listening ? stopListening() : startListening()
            } label: {
                Text(listening ? "Press shortcut…" : (combo.map { LocalizedStringKey(KeyNames.describe($0)) } ?? "None"))
                    .frame(minWidth: 110)
            }
            if allowsClear, combo != nil, !listening {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
        }
        .onDisappear(perform: stopListening)
    }

    private static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    private func startListening() {
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = ModifierFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(.shortcutMask)
            if event.keyCode == 53 && modifiers.isEmpty {
                stopListening()
            } else if (event.keyCode == 51 || event.keyCode == 117) && modifiers.isEmpty && allowsClear {
                combo = nil
                stopListening()
            } else if !modifiers.isEmpty || Self.functionKeys.contains(event.keyCode) {
                // Plain letters would be swallowed system-wide, so a modifier (or F-key) is required.
                combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers.rawValue)
                stopListening()
            }
            return nil
        }
    }

    private func stopListening() {
        listening = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Non-optional variant for required shortcuts.
struct RequiredHotkeyField: View {
    @Binding var combo: KeyCombo

    var body: some View {
        HotkeyField(combo: Binding(get: { combo }, set: { if let value = $0 { combo = value } }), allowsClear: false)
    }
}

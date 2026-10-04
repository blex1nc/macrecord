import MacroCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.activity.label)
        Divider()
        if state.activity == .recording {
            Button("Stop Recording") { state.stopRecording() }
        } else {
            Button("Start Recording") { state.startRecording() }
                .disabled(!state.activity.isIdle)
        }
        Button("Play Selected") { state.playSelected() }
            .disabled(!state.activity.isIdle || state.macros.isEmpty)
        Button(state.activity == .clicking ? "Stop Autoclicker" : "Start Autoclicker") { state.toggleAutoclick() }
            .disabled(!(state.activity.isIdle || state.activity == .clicking))
        if !state.activity.isIdle {
            Button("Stop All") { state.stopAll() }
        }
        Divider()
        Text("Shortcuts: record \(KeyNames.describe(state.settings.recordHotkey)) · stop \(KeyNames.describe(state.settings.stopHotkey))")
        Divider()
        Button("Open macrecord") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings…") }
        Button("Quit macrecord") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

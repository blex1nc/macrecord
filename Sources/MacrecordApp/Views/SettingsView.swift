import MacroCore
import Permissions
import Playback
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Global shortcuts") {
                LabeledContent("Start / stop recording") { RequiredHotkeyField(combo: $state.settings.recordHotkey) }
                LabeledContent("Play selected macro") { RequiredHotkeyField(combo: $state.settings.playHotkey) }
                LabeledContent("Stop everything") { RequiredHotkeyField(combo: $state.settings.stopHotkey) }
                LabeledContent("Autoclicker") { RequiredHotkeyField(combo: $state.settings.autoclickHotkey) }
                Button("Restore defaults") {
                    let defaults = AppSettings()
                    state.settings.recordHotkey = defaults.recordHotkey
                    state.settings.playHotkey = defaults.playHotkey
                    state.settings.stopHotkey = defaults.stopHotkey
                    state.settings.autoclickHotkey = defaults.autoclickHotkey
                }
            }
            Section("Recording & playback") {
                Toggle("Record mouse movement", isOn: $state.settings.captureMouseMoves)
                Toggle("Stop playback when I move the mouse or press a key", isOn: $state.settings.stopOnUserInput)
            }
            Section("Permissions") {
                PermissionRow(title: "Accessibility", detail: "Replay clicks and keystrokes.",
                              granted: Permissions.accessibilityGranted) { Permissions.openSettings(.accessibility) }
                PermissionRow(title: "Input Monitoring", detail: "Record your mouse and keyboard.",
                              granted: Permissions.inputMonitoringGranted) { Permissions.openSettings(.inputMonitoring) }
                PermissionRow(title: "Screen Recording (optional)", detail: "Only for “wait for pixel color” steps.",
                              granted: ScreenPixelSampler.permissionGranted) {
                    ScreenPixelSampler.requestPermission()
                    Permissions.openSettings(.screenRecording)
                }
            }
            Section("Privacy") {
                Text("macrecord has no networking code. Macros are stored only in:")
                HStack {
                    Text(MacroStore.defaultDirectory.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: MacroStore.defaultDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(MacroStore.defaultDirectory)
                    }
                }
                Text("Recordings may contain anything you typed, including passwords. Share macro files with care.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

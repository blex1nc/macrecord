import SwiftUI

@main
struct MacrecordApp: App {
    @State private var state = AppState()

    var body: some Scene {
        Window("macrecord", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Script") { state.newScript() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Import…") { state.importMacros() }
                    .keyboardShortcut("o")
            }
        }

        MenuBarExtra {
            MenuBarView().environment(state)
        } label: {
            Image(systemName: state.activity.symbol)
        }

        Settings {
            SettingsView()
                .environment(state)
                .frame(width: 520)
        }
    }
}

extension Activity {
    var symbol: String {
        switch self {
        case .idle: return "record.circle"
        case .recording: return "record.circle.fill"
        case .playing: return "play.circle.fill"
        case .clicking: return "cursorarrow.click.2"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case let .playing(_, name): return "Playing \(name)"
        case .clicking: return "Autoclicker running"
        }
    }
}

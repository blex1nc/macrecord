import MacroCore
import SwiftUI

struct MacroDetailView: View {
    @Environment(AppState.self) private var state
    @State var macro: Macro
    @State private var editingName = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()
            Divider()
            if macro.isScript {
                ScriptEditorView(macro: $macro)
            } else {
                EventEditorView(macroID: macro.id)
            }
        }
        .onChange(of: macro) { _, new in
            // Event edits go through AppState (undo); everything else is saved from here.
            guard let current = state.macros.first(where: { $0.id == new.id }) else { return }
            var merged = new
            merged.events = current.events
            if merged != current { state.update(merged) }
        }
    }

    private var isPlayingThis: Bool {
        if case let .playing(id, _) = state.activity { return id == macro.id }
        return false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Plain text until explicitly edited, so stray typing can never rename the macro.
                if editingName {
                    TextField("Name", text: $macro.name)
                        .textFieldStyle(.plain)
                        .font(.title2.bold())
                        .focused($nameFocused)
                        .onSubmit { editingName = false }
                        .onChange(of: nameFocused) { _, focused in if !focused { editingName = false } }
                        .onAppear { nameFocused = true }
                } else {
                    Text(macro.name)
                        .font(.title2.bold())
                        .onTapGesture(count: 2) { editingName = true }
                    Button { editingName = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("Rename")
                }
                Spacer()
                Button {
                    isPlayingThis ? state.stopAll() : state.play(macro.id)
                } label: {
                    Label(isPlayingThis ? "Stop" : "Play", systemImage: isPlayingThis ? "stop.fill" : "play.fill")
                        .frame(minWidth: 70)
                }
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!state.activity.isIdle && !isPlayingThis)
            }
            HStack(spacing: 20) {
                LabeledContent {
                    HStack(spacing: 4) {
                        TextField("", value: $macro.options.loopCount, format: .number)
                            .frame(width: 50)
                        Stepper("", value: $macro.options.loopCount, in: 0...1_000_000).labelsHidden()
                        Text(macro.options.loopCount == 0 ? "∞" : "×").foregroundStyle(.secondary)
                    }
                } label: { Text("Repeat").fixedSize() }
                LabeledContent {
                    HStack(spacing: 4) {
                        Slider(value: speedLog, in: log10(0.1)...log10(10)).frame(width: 120)
                        Text(String(format: "%.2g×", macro.options.clampedSpeed)).monospacedDigit().frame(width: 40)
                    }
                } label: { Text("Speed").fixedSize() }
                if !macro.isScript {
                    LabeledContent {
                        TextField("", value: $macro.options.loopDelayMs, format: .number).frame(width: 60)
                    } label: { Text("Pause between loops (ms)").fixedSize() }
                }
            }
            HStack(spacing: 20) {
                LabeledContent { HotkeyField(combo: $macro.hotkey) } label: { Text("Shortcut").fixedSize() }
                if !macro.isScript {
                    Toggle("Relative mouse (games)", isOn: $macro.options.relativeMouse)
                        .help("Replays raw mouse deltas from the current cursor position instead of absolute positions.")
                }
                Spacer()
                if !macro.isScript {
                    // Events are edited through AppState, so read the live copy.
                    Text((state.macros.first { $0.id == macro.id } ?? macro).summary)
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.callout)
        }
    }

    private var speedLog: Binding<Double> {
        Binding(get: { log10(macro.options.clampedSpeed) },
                set: { macro.options.speed = (pow(10, $0) * 100).rounded() / 100 })
    }
}

struct ScriptEditorView: View {
    @Environment(AppState.self) private var state
    @Binding var macro: Macro

    var body: some View {
        VSplitView {
            TextEditor(text: Binding(get: { macro.script ?? "" }, set: { macro.script = $0 }))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .frame(minHeight: 120)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Log").font(.caption.bold())
                    Spacer()
                    Button("Clear") { state.scriptLog = [] }.buttonStyle(.borderless).font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                ScrollView {
                    Text(state.scriptLog.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
            }
            .frame(minHeight: 60)
        }
    }
}

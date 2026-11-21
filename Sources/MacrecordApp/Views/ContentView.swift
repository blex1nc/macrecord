import MacroCore
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selection) {
                Label("Autoclicker", systemImage: "cursorarrow.click.2")
                    .tag(SidebarItem.autoclicker)
                Section("Macros") {
                    ForEach(state.macros) { macro in
                        MacroRow(macro: macro)
                            .tag(SidebarItem.macro(macro.id))
                            .contextMenu {
                                Button("Play") { state.play(macro.id) }
                                Button("Duplicate") { state.duplicate(macro.id) }
                                Button("Export…") { state.export(macro.id) }
                                Divider()
                                Button("Delete", role: .destructive) { state.delete(macro.id) }
                            }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { ShortcutsFooter() }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            VStack(spacing: 0) {
                if !state.permissionsGranted {
                    OnboardingView()
                }
                switch state.selection {
                case let .macro(id):
                    if let macro = state.macros.first(where: { $0.id == id }) {
                        MacroDetailView(macro: macro).id(id)
                    } else {
                        placeholder
                    }
                case .autoclicker, .none:
                    AutoClickerView()
                }
                StatusBar()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if state.activity == .recording {
                    Button { state.stopRecording() } label: { Label("Stop Recording", systemImage: "stop.circle.fill") }
                        .foregroundStyle(.red)
                } else {
                    Button { state.startRecording() } label: { Label("Record", systemImage: "record.circle") }
                        .disabled(!state.activity.isIdle)
                        .help("Record (\(KeyNames.describe(state.settings.recordHotkey)))")
                }
                Button { state.stopAll() } label: { Label("Stop", systemImage: "stop.fill") }
                    .disabled(state.activity.isIdle)
                    .help("Stop everything (\(KeyNames.describe(state.settings.stopHotkey)))")
                Button { state.newScript() } label: { Label("New Script", systemImage: "curlybraces") }
                Button { state.importMacros() } label: { Label("Import", systemImage: "square.and.arrow.down") }
            }
        }
        .alert("macrecord", isPresented: Binding(get: { state.message != nil }, set: { if !$0 { state.message = nil } })) {
            Button("OK") { state.message = nil }
        } message: {
            Text(state.message ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
        // AppKit focuses the first text field when a window or view appears; stray typing would then
        // silently edit a macro. Start every view unfocused instead.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Only the first time: returning to the app later must not drop the user's editing focus.
            guard let window = note.object as? NSWindow,
                  Self.seenWindows.insert(ObjectIdentifier(window)).inserted else { return }
            Self.clearFocus(window)
        }
        .onChange(of: state.selection) { _, _ in
            DispatchQueue.main.async { Self.clearFocus(NSApp.keyWindow) }
        }
    }

    private static var seenWindows = Set<ObjectIdentifier>()

    static func clearFocus(_ window: NSWindow?) {
        guard let window, window.firstResponder is NSTextView else { return }
        window.makeFirstResponder(nil)
    }

    private var placeholder: some View {
        ContentUnavailableView("No macro selected", systemImage: "record.circle",
                               description: Text("Press \(KeyNames.describe(state.settings.recordHotkey)) to record."))
    }
}

/// Always-visible global shortcuts for recording and playback (also editable in Settings).
struct ShortcutsFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 6) {
            Text("Shortcuts").font(.caption.bold()).foregroundStyle(.secondary)
            row("Record / stop") { RequiredHotkeyField(combo: $state.settings.recordHotkey, minWidth: 64) }
            row("Play / stop") { RequiredHotkeyField(combo: $state.settings.playHotkey, minWidth: 64) }
        }
        .controlSize(.small)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder field: () -> some View) -> some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            field()
        }
    }
}

struct MacroRow: View {
    let macro: Macro

    var body: some View {
        HStack {
            Image(systemName: macro.isScript ? "curlybraces" : "record.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(macro.name).lineLimit(1)
                Text(macro.isScript ? String(localized: "Script") : macro.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let hotkey = macro.hotkey {
                Text(KeyNames.describe(hotkey))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack {
            Circle()
                .fill(state.activity.isIdle ? Color.secondary : (state.activity == .recording ? .red : .green))
                .frame(width: 8, height: 8)
            Text(state.activity.label)
            switch state.activity {
            case .recording: Text("· \(state.liveCount) events")
            case .clicking: Text("· \(state.liveCount) clicks")
            case .playing: Text("· loop \(state.liveCount)")
            case .idle: EmptyView()
            }
            Spacer()
            Text("Offline · nothing leaves this Mac")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

extension Macro {
    var summary: String {
        String(format: "%d · %.1f s", events.count, Double(durationNs) / 1e9)
    }
}

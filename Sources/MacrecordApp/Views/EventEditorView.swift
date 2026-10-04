import MacroCore
import Playback
import SwiftUI

struct EventEditorView: View {
    @Environment(AppState.self) private var state
    let macroID: UUID
    @State private var selection = Set<MacroEvent.ID>()
    @State private var tolerance = 2.0
    @State private var insertSheet: InsertKind?

    enum InsertKind: Identifiable {
        case delay, pixel, app
        var id: Self { self }
    }

    private var events: [MacroEvent] { state.macros.first { $0.id == macroID }?.events ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal)
                .padding(.vertical, 8)
            Table(of: Row.self, selection: $selection) {
                TableColumn("#") { row in Text("\(row.index + 1)").monospacedDigit().foregroundStyle(.secondary) }
                    .width(50)
                TableColumn("Delay (ms)") { row in
                    DelayField(delayNs: row.event.delayNs) { newValue in
                        state.edit(macroID) { events in
                            var events = events
                            if row.index < events.count { events[row.index].delayNs = newValue }
                            return events
                        }
                    }
                }
                .width(90)
                TableColumn("Action") { row in Text(LocalizedStringKey(row.event.kind.title)) }
                    .width(min: 120, ideal: 160)
                TableColumn("Details") { row in
                    Text(row.event.kind.detail).foregroundStyle(.secondary).monospacedDigit()
                }
            } rows: {
                ForEach(rows) { TableRow($0) }
            }
            .onDeleteCommand(perform: deleteSelected)
        }
        .sheet(item: $insertSheet) { kind in
            InsertStepSheet(kind: kind) { event in insert(event) }
        }
    }

    struct Row: Identifiable {
        let index: Int
        let event: MacroEvent
        var id: UUID { event.id }
    }

    private var rows: [Row] { events.enumerated().map { Row(index: $0.offset, event: $0.element) } }

    private var toolbar: some View {
        HStack {
            Button { state.undo(macroID) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!state.canUndo(macroID))
                .keyboardShortcut("z")
            Button(role: .destructive, action: deleteSelected) { Label("Delete", systemImage: "trash") }
                .disabled(selection.isEmpty)
            Menu {
                Button("Delay…") { insertSheet = .delay }
                Button("Wait for pixel color…") { insertSheet = .pixel }
                Button("Activate app…") { insertSheet = .app }
            } label: {
                Label("Insert", systemImage: "plus")
            }
            .fixedSize()
            Divider().frame(height: 16)
            Button("Simplify path") {
                state.edit(macroID) { MacroEditing.simplifyMouseMoves($0, tolerance: tolerance) }
            }
            .help("Removes redundant mouse-move points (Ramer–Douglas–Peucker) while keeping timing.")
            Stepper(value: $tolerance, in: 0.5...50, step: 0.5) {
                Text("±\(tolerance, specifier: "%.1f") pt").monospacedDigit()
            }
            .fixedSize()
            Button("Remove moves") { state.edit(macroID) { MacroEditing.removeMouseMoves($0) } }
            Spacer()
            Text("\(events.count) events").foregroundStyle(.secondary).monospacedDigit().fixedSize()
        }
        .controlSize(.small)
    }

    private func deleteSelected() {
        let ids = selection
        state.edit(macroID) { events in
            MacroEditing.remove(events, at: IndexSet(events.indices.filter { ids.contains(events[$0].id) }))
        }
        selection = []
    }

    /// Inserts after the last selected event, or at the end.
    private func insert(_ event: MacroEvent) {
        let ids = selection
        state.edit(macroID) { events in
            var events = events
            let index = events.lastIndex { ids.contains($0.id) }.map { $0 + 1 } ?? events.count
            events.insert(event, at: index)
            return events
        }
        selection = [event.id]
    }
}

struct DelayField: View {
    let delayNs: UInt64
    let commit: (UInt64) -> Void
    @State private var text = ""

    var body: some View {
        TextField("", text: $text)
            .monospacedDigit()
            .onAppear { text = Self.format(delayNs) }
            .onChange(of: delayNs) { _, new in text = Self.format(new) }
            .onSubmit {
                let normalized = text.replacingOccurrences(of: ",", with: ".")
                if let ms = Double(normalized), ms >= 0 { commit(UInt64(ms * 1_000_000)) } else { text = Self.format(delayNs) }
            }
    }

    static func format(_ ns: UInt64) -> String { String(format: "%.3f", Double(ns) / 1e6) }
}

struct InsertStepSheet: View {
    let kind: EventEditorView.InsertKind
    let insert: (MacroEvent) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var delayMs = 500.0
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var hex = "FFFFFF"
    @State private var tolerance = 10
    @State private var timeoutMs = 10_000
    @State private var bundleID = ""
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                switch kind {
                case .delay:
                    TextField("Delay (ms)", value: $delayMs, format: .number)
                case .pixel:
                    TextField("X", value: $x, format: .number)
                    TextField("Y", value: $y, format: .number)
                    TextField("Color (hex RRGGBB)", text: $hex)
                    Stepper("Tolerance: \(tolerance)", value: $tolerance, in: 0...255)
                    TextField("Timeout (ms, 0 = forever)", value: $timeoutMs, format: .number)
                    Button(picking ? "Hover the target… (3 s)" : "Pick from screen under cursor in 3 s") { pick() }
                        .disabled(picking)
                    Text("Needs Screen Recording permission. Sampling happens locally.")
                        .font(.caption).foregroundStyle(.secondary)
                case .app:
                    Picker("App", selection: $bundleID) {
                        Text("Choose…").tag("")
                        ForEach(runningApps, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Insert") {
                    if let event = makeEvent() { insert(event) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(kind == .app && bundleID.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private var runningApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .sorted()
    }

    private func makeEvent() -> MacroEvent? {
        switch kind {
        case .delay:
            return MacroEvent(delayNs: UInt64(max(delayMs, 0) * 1_000_000), kind: .delay)
        case .pixel:
            let rgb = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0xFFFFFF
            return MacroEvent(delayNs: 0, kind: .waitForPixel(x: x, y: y, rgb: rgb, tolerance: UInt8(tolerance),
                                                               timeoutMs: UInt32(max(timeoutMs, 0))))
        case .app:
            return MacroEvent(delayNs: 0, kind: .activateApp(bundleID: bundleID))
        }
    }

    private func pick() {
        picking = true
        if !ScreenPixelSampler.permissionGranted { ScreenPixelSampler.requestPermission() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let point = CGEvent(source: nil)?.location ?? .zero
            x = point.x.rounded()
            y = point.y.rounded()
            DispatchQueue.global(qos: .userInitiated).async {
                let rgb = ScreenPixelSampler().rgb(atX: point.x, y: point.y)
                DispatchQueue.main.async {
                    if let rgb { hex = String(format: "%06X", rgb) }
                    picking = false
                }
            }
        }
    }
}

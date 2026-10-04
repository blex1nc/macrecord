import MacroCore
import SwiftUI

struct AutoClickerView: View {
    @Environment(AppState.self) private var state
    @State private var picking = false

    var body: some View {
        @Bindable var state = state
        let running = state.activity == .clicking
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Autoclicker").font(.title2.bold())
                        Text("Toggle with \(KeyNames.describe(state.settings.autoclickHotkey))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if running {
                        Text("\(state.liveCount) clicks").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Button {
                        state.toggleAutoclick()
                    } label: {
                        Label(running ? "Stop" : "Start", systemImage: running ? "stop.fill" : "play.fill")
                            .frame(minWidth: 70)
                    }
                    .controlSize(.large)
                    .disabled(!(state.activity.isIdle || running))
                }
            }
            Section("Shortcut") {
                LabeledContent("Start / stop autoclicker") {
                    RequiredHotkeyField(combo: $state.settings.autoclickHotkey)
                }
                Picker("Shortcut mode", selection: $state.settings.autoclick.mode) {
                    Text("Toggle").tag(AutoClickConfig.Mode.toggle)
                    Text("Hold to click").tag(AutoClickConfig.Mode.hold)
                }
                .pickerStyle(.segmented)
                LabeledContent("Stop everything") { RequiredHotkeyField(combo: $state.settings.stopHotkey) }
            }
            Section("Rate") {
                LabeledContent("Clicks per second") {
                    HStack {
                        TextField("", value: $state.settings.autoclick.clicksPerSecond, format: .number)
                            .frame(width: 70)
                        Text("every \(Double(state.settings.autoclick.intervalNs) / 1e6, specifier: "%.2f") ms")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Slider(value: $state.settings.autoclick.timingJitter, in: 0...0.5) {
                    Text("Timing randomness")
                } minimumValueLabel: { Text("0%") } maximumValueLabel: { Text("50%") }
                LabeledContent("Hold each click (ms)") {
                    TextField("", value: $state.settings.autoclick.holdDurationMs, format: .number).frame(width: 70)
                }
            }
            Section("Click") {
                Picker("Button", selection: $state.settings.autoclick.button) {
                    ForEach(MouseButton.allCases, id: \.self) { Text(LocalizedStringKey($0.name)).tag($0) }
                }
                Picker("Type", selection: $state.settings.autoclick.clickType) {
                    Text("Single").tag(AutoClickConfig.ClickType.single)
                    Text("Double").tag(AutoClickConfig.ClickType.double)
                }
                .pickerStyle(.segmented)
            }
            Section("Position") {
                Picker("Click at", selection: targetKind) {
                    Text("Cursor").tag(0)
                    Text("Fixed point").tag(1)
                    Text("Point sequence").tag(2)
                }
                .pickerStyle(.segmented)
                targetEditor
                Slider(value: $state.settings.autoclick.positionJitter, in: 0...30) {
                    Text("Position randomness")
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("30 pt") }
            }
            Section("Stop after") {
                Picker("Limit", selection: limitKind) {
                    Text("Never").tag(0)
                    Text("Clicks").tag(1)
                    Text("Seconds").tag(2)
                }
                .pickerStyle(.segmented)
                switch state.settings.autoclick.limit {
                case let .clicks(n):
                    TextField("Clicks", value: Binding(get: { n }, set: { state.settings.autoclick.limit = .clicks(max($0, 1)) }),
                              format: .number)
                case let .seconds(s):
                    TextField("Seconds", value: Binding(get: { s }, set: { state.settings.autoclick.limit = .seconds(max($0, 0.1)) }),
                              format: .number)
                case .none:
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .disabled(running)
    }

    private var targetKind: Binding<Int> {
        Binding(get: {
            switch state.settings.autoclick.target {
            case .cursor: return 0
            case .fixed: return 1
            case .points: return 2
            }
        }, set: { kind in
            let here = CGEvent(source: nil)?.location ?? .zero
            switch kind {
            case 1: state.settings.autoclick.target = .fixed(x: here.x.rounded(), y: here.y.rounded())
            case 2: state.settings.autoclick.target = .points([])
            default: state.settings.autoclick.target = .cursor
            }
        })
    }

    private var limitKind: Binding<Int> {
        Binding(get: {
            switch state.settings.autoclick.limit {
            case .none: return 0
            case .clicks: return 1
            case .seconds: return 2
            }
        }, set: { kind in
            switch kind {
            case 1: state.settings.autoclick.limit = .clicks(100)
            case 2: state.settings.autoclick.limit = .seconds(10)
            default: state.settings.autoclick.limit = .none
            }
        })
    }

    @ViewBuilder private var targetEditor: some View {
        switch state.settings.autoclick.target {
        case .cursor:
            Text("Clicks wherever the cursor is.").foregroundStyle(.secondary)
        case let .fixed(x, y):
            HStack {
                Text("x \(Int(x)), y \(Int(y))").monospacedDigit()
                Spacer()
                pickButton { p in state.settings.autoclick.target = .fixed(x: p.x, y: p.y) }
            }
        case let .points(points):
            ForEach(Array(points.enumerated()), id: \.offset) { index, p in
                HStack {
                    Text("\(index + 1). x \(Int(p.x)), y \(Int(p.y))").monospacedDigit()
                    Spacer()
                    Button { state.settings.autoclick.target = .points(points.enumerated().filter { $0.offset != index }.map(\.element)) }
                        label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            pickButton { p in state.settings.autoclick.target = .points(points + [AutoClickConfig.Point(x: p.x, y: p.y)]) }
        }
    }

    /// Captures the cursor position after a 3-second countdown so the user can hover the target.
    private func pickButton(_ apply: @escaping (CGPoint) -> Void) -> some View {
        Button(picking ? "Hover the target… (3 s)" : "Pick position in 3 s") {
            picking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let p = CGEvent(source: nil)?.location ?? .zero
                apply(CGPoint(x: p.x.rounded(), y: p.y.rounded()))
                picking = false
            }
        }
        .disabled(picking)
    }
}

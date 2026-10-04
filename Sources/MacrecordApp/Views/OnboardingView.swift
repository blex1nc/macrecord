import Permissions
import Playback
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var accessibility = Permissions.accessibilityGranted
    @State private var inputMonitoring = Permissions.inputMonitoringGranted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("macrecord needs two permissions").font(.headline)
            Text("Both stay on this Mac. After granting, you may need to restart macrecord.")
                .font(.callout)
                .foregroundStyle(.secondary)
            PermissionRow(title: "Accessibility", detail: "Replay clicks and keystrokes.", granted: accessibility) {
                Permissions.requestAccessibility()
                Permissions.openSettings(.accessibility)
            }
            PermissionRow(title: "Input Monitoring", detail: "Record your mouse and keyboard.", granted: inputMonitoring) {
                Permissions.requestInputMonitoring()
                Permissions.openSettings(.inputMonitoring)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Already on in System Settings but not detected? Remove macrecord from the list with (−), add it again, then restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restart macrecord") { Self.relaunch() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.12))
        .onReceive(timer) { _ in
            accessibility = Permissions.accessibilityGranted
            inputMonitoring = Permissions.inputMonitoringGranted
            state.refreshPermissions()
        }
    }
}

extension OnboardingView {
    /// Input Monitoring is only picked up by a fresh process.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: action)
            }
        }
    }
}

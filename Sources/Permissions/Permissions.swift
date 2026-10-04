import ApplicationServices
import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// TCC permission checks. macrecord needs Accessibility (to post events) and Input Monitoring (to record keys).
public enum Permissions {
    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    public static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
    public static var postEventsGranted: Bool { CGPreflightPostEventAccess() }
    public static var allGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    /// Shows the system prompt that adds the app to the Accessibility list.
    public static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    public enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
        case screenRecording = "Privacy_ScreenCapture"
    }

    public static func openSettings(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True while a password field (or similar) has enabled secure keyboard input system-wide.
    public static var secureInputActive: Bool { IsSecureEventInputEnabled() }
}

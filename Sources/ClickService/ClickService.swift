import AppKit
import CSupport
import Foundation
import Hotkeys
import MacroCore
import os
import Playback

/// The autoclicker as the app sees it: implemented in-process by `ClickService`, or by the `macrecord-clickd`
/// helper through `AgentClient`. Main thread only; `onEvent` is called on the main thread.
public protocol ClickBackend: AnyObject {
    var onEvent: ((ClickServiceEvent) -> Void)? { get set }
    func apply(_ settings: ClickServiceSettings)
    func start(_ trigger: ClickTrigger)
    func stop()
    /// Stops clicking and releases taps; the backend is unusable afterwards.
    func shutdown()
}

/// Click engine: the real-time clicker, the mouse-button trigger, target resolution and per-session diagnostics.
/// The trigger and the clicker live in the same process, so hold-to-click release never waits on IPC or the UI.
/// Main thread only.
public final class ClickService: ClickBackend {
    public var onEvent: ((ClickServiceEvent) -> Void)?

    private let clicker = AutoClicker()
    private let trigger = MouseButtonTrigger()
    private let probe = MotionProbe()
    private var settings: ClickServiceSettings?
    private var session: Session?
    private var sessionID = 0
    private var focusObserver: NSObjectProtocol?
    private var progressTimer: Timer?
    private static let log = Logger(subsystem: "io.github.blex1nc.macrecord", category: "clicker")

    private struct Session {
        let id: Int
        let trigger: ClickTrigger
        let delivery: AutoClickConfig.Delivery
        let pid: pid_t?
        let window: Int64?
        let activePID: pid_t?
        let windowPID: pid_t?
        let probing: Bool
        let startTicks: UInt64
    }

    public init() {}

    deinit { shutdown() }

    public func apply(_ settings: ClickServiceSettings) {
        let old = self.settings
        self.settings = settings
        let wanted = settings.triggerArmed ? settings.triggerButton : nil
        let had = old?.triggerArmed == true ? old?.triggerButton : nil
        guard wanted != had || (wanted != nil && !trigger.isRunning) else { return }
        trigger.stop()
        guard let wanted else { return }
        let started = trigger.start(button: wanted,
                                    onPress: { [weak self] in self?.triggerPressed() },
                                    onRelease: { [weak self] in self?.triggerReleased() })
        if !started { onEvent?(.triggerUnavailable) }
    }

    public func start(_ trigger: ClickTrigger) {
        guard let settings, session == nil, !clicker.isRunning else { return }
        let config = settings.autoclick
        // Two independent readings of the frontmost app; clicks are only aimed at an app when they agree,
        // otherwise they could land in a background app (or the reading is stale) and system delivery is used.
        let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let windowPID = AutoClicker.frontmostWindowOwner()
        var pid: pid_t?
        if config.effectiveDelivery == .app, let activePID, activePID == windowPID {
            let excluded = Set(settings.excludedPIDs + [ProcessInfo.processInfo.processIdentifier])
            if !excluded.contains(activePID) { pid = activePID }
        }
        let window = pid.flatMap(AutoClicker.frontWindowID(of:))
        // `.app` without an agreed target falls back to system delivery.
        let delivery: AutoClickConfig.Delivery = pid != nil ? .app : (config.effectiveDelivery == .fast ? .fast : .system)
        sessionID += 1
        let id = sessionID
        _ = self.trigger.takeStats()
        let probing = probe.start()
        session = Session(id: id, trigger: trigger, delivery: delivery, pid: pid, window: window,
                          activePID: activePID, windowPID: windowPID, probing: probing, startTicks: mr_now_ticks())
        clicker.onFinish = { [weak self] in DispatchQueue.main.async { self?.finished(id) } }
        clicker.start(config, targetPID: pid, targetWindow: window)
        if let pid { stopWhenFocusLeaves(pid) }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            onEvent?(.progress(clicks: clicker.clickCount))
        }
        onEvent?(.started(delivery: delivery, pid: pid))
    }

    public func stop() {
        clicker.stop()
    }

    public func shutdown() {
        clicker.stop()
        trigger.stop()
        if let session { finished(session.id) }
    }

    // MARK: - Private

    private func triggerPressed() {
        guard let settings else { return }
        if settings.autoclick.mode == .hold || session == nil { start(.mouseButton) } else { stop() }
    }

    private func triggerReleased() {
        guard settings?.autoclick.mode == .hold else { return }
        stop()
    }

    private func stopWhenFocusLeaves(_ pid: pid_t) {
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != pid { self?.clicker.stop() }
        }
    }

    private func finished(_ id: Int) {
        guard let session, session.id == id else { return }
        self.session = nil
        clicker.stop()
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
        focusObserver = nil
        progressTimer?.invalidate()
        progressTimer = nil
        let motion = probe.stop()
        let tap = trigger.takeStats()
        let clicks = clicker.clickCount
        let ours = Set(settings?.excludedPIDs ?? []).union([ProcessInfo.processInfo.processIdentifier])
        let suspects = EventTapAudit.activeMouseTaps(excluding: ours)
        let stalled = Self.motionStalledDownstream(motion: motion, tap: tap)
        Self.log.notice("\(Self.summary(session: session, clicks: clicks, motion: motion, tap: tap), privacy: .public) stalled=\(stalled, privacy: .public) mouseTaps=\(suspects.isEmpty ? "-" : suspects.map { "\($0.app)[\($0.pid)]" }.joined(separator: ","), privacy: .public)")
        onEvent?(.stopped(clicks: clicks))
        if stalled, session.delivery == .system, !suspects.isEmpty { onEvent?(.slowTaps(suspects.map(\.app))) }
    }

    /// Motion reached the tail of the session taps late while our head-of-chain trigger tap saw it on time:
    /// something between them (another app's active tap) held the stream.
    static func motionStalledDownstream(motion: MotionProbe.Stats, tap: MouseButtonTrigger.Stats) -> Bool {
        motion.motions >= 50 && motion.age.percentileNs(0.99) >= 15_000_000
            && (tap.callbackAge.count == 0 || tap.callbackAge.maxNs < 5_000_000)
    }

    private static func summary(session: Session, clicks: Int, motion: MotionProbe.Stats,
                                tap: MouseButtonTrigger.Stats) -> String {
        func ms(_ ns: UInt64) -> String { String(format: "%.2f", Double(ns) / 1e6) }
        let seconds = Double(mr_ticks_to_ns(mr_now_ticks() - session.startTicks)) / 1e9
        return "session process=\(ProcessInfo.processInfo.processName) trigger=\(session.trigger.rawValue) "
            + "delivery=\(session.delivery.rawValue) pid=\(session.pid.map(String.init) ?? "-") "
            + "window=\(session.window.map(String.init) ?? "-") activePID=\(session.activePID.map(String.init) ?? "-") "
            + "windowPID=\(session.windowPID.map(String.init) ?? "-") probe=\(session.probing ? "on" : "off") clicks=\(clicks) secs=\(String(format: "%.1f", seconds)) "
            + "motion=\(motion.motions) drags=\(motion.drags) jumps=\(motion.jumps) "
            + "gapP99=\(ms(motion.gaps.percentileNs(0.99)))ms gapMax=\(ms(motion.gaps.maxNs))ms "
            + "ageP99=\(ms(motion.age.percentileNs(0.99)))ms ageMax=\(ms(motion.age.maxNs))ms "
            + "trigAgeP99=\(ms(tap.callbackAge.percentileNs(0.99)))ms trigAgeMax=\(ms(tap.callbackAge.maxNs))ms "
            + "rewrites=\(tap.rewrites) foreignDrags=\(tap.foreignDrags)"
    }
}

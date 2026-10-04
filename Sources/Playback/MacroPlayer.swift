import AppKit
import CoreGraphics
import CSupport
import Foundation
import MacroCore

/// Samples screen pixels for `waitForPixel` steps. Returns 0xRRGGBB or nil if unavailable.
public protocol PixelSampling: AnyObject {
    func rgb(atX x: Double, y: Double) -> UInt32?
}

/// Plays macros on a real-time thread with absolute (drift-free) scheduling.
public final class MacroPlayer {
    public struct Configuration {
        /// Busy-wait window before each deadline; trades a little CPU for sub-100 µs precision.
        public var spinNs: UInt64 = 200_000
        /// Collect per-event lateness (benchmarks / diagnostics).
        public var recordTiming = false
        /// Post no-op events instead of the real ones (benchmarks: same path, no effect on the user's input).
        public var dryRun = false
        public init() {}
    }

    public var configuration = Configuration()
    public var pixelSampler: PixelSampling?
    /// Called on the playback thread when playback ends; `true` if it ran to completion.
    public var onFinish: ((Bool) -> Void)?

    public var isPlaying: Bool { mr_flag_load(running) }
    public var currentLoop: Int { Int(mr_counter_load(loopCounter)) }
    public var currentIndex: Int { Int(mr_counter_load(indexCounter)) }
    /// Lateness (post completion − scheduled time) in ns of the last run, if `recordTiming` was on.
    public private(set) var latenessNs: [Int64] = []

    private let running = mr_flag_create(false)!
    private let loopCounter = mr_counter_create()!
    private let indexCounter = mr_counter_create()!
    private let factory = EventFactory()

    public init() {}

    deinit {
        mr_flag_store(running, false)
        mr_flag_destroy(running)
        mr_counter_destroy(loopCounter)
        mr_counter_destroy(indexCounter)
    }

    public func play(_ macro: Macro, options: PlaybackOptions? = nil) {
        guard !isPlaying, !macro.events.isEmpty else { return }
        let options = options ?? macro.options
        let steps = macro.events.map { prepare($0, speed: options.clampedSpeed) }
        mr_flag_store(running, true)
        mr_counter_store(loopCounter, 0)
        mr_counter_store(indexCounter, 0)
        let configuration = configuration
        RealtimeThread.start(name: "macrecord.playback") { [self] in
            run(steps, options: options, configuration: configuration)
        }
    }

    public func stop() {
        mr_flag_store(running, false)
    }

    // MARK: - Preparation

    enum Action {
        case post(CGEvent)
        case waitPixel(x: Double, y: Double, rgb: UInt32, tolerance: UInt8, timeoutMs: UInt32)
        case activate(String)
        case none
    }

    struct Step {
        var delayTicks: UInt64
        var action: Action
        var press: Press
        var relativeDelta: (dx: Int64, dy: Int64)?
    }

    enum Press { case none, keyDown(UInt16), keyUp(UInt16), buttonDown(MouseButton), buttonUp(MouseButton) }

    func prepare(_ event: MacroEvent, speed: Double) -> Step {
        let delay = mr_ns_to_ticks(UInt64(Double(event.delayNs) / speed))
        var press = Press.none
        var delta: (Int64, Int64)?
        let action: Action
        switch event.kind {
        case let .waitForPixel(x, y, rgb, tolerance, timeoutMs):
            action = .waitPixel(x: x, y: y, rgb: rgb, tolerance: tolerance, timeoutMs: timeoutMs)
        case let .activateApp(bundleID):
            action = .activate(bundleID)
        default:
            action = factory.make(event.kind).map(Action.post) ?? .none
        }
        switch event.kind {
        case let .keyDown(code, _): press = .keyDown(code)
        case let .keyUp(code, _): press = .keyUp(code)
        case let .mouseDown(button, _, _, _): press = .buttonDown(button)
        case let .mouseUp(button, _, _, _): press = .buttonUp(button)
        case let .mouseMove(_, _, dx, dy), let .mouseDrag(_, _, _, dx, dy): delta = (dx, dy)
        default: break
        }
        return Step(delayTicks: delay, action: action, press: press, relativeDelta: delta)
    }

    // MARK: - Playback thread

    private func run(_ steps: [Step], options: PlaybackOptions, configuration: Configuration) {
        var lateness: [Int64] = []
        if configuration.recordTiming {
            lateness.reserveCapacity(min(steps.count * max(options.loopCount, 1), 1 << 20))
        }
        var heldKeys = Set<UInt16>()
        var heldButtons = Set<MouseButton>()
        heldKeys.reserveCapacity(16)
        var cursor = CGEvent(source: nil)?.location ?? .zero
        let loopDelay = mr_ns_to_ticks(UInt64(options.loopDelayMs) * 1_000_000)
        let dryEvent = configuration.dryRun ? factory.null() : nil
        var completed = true
        factory.warmUp()
        var target = mr_now_ticks()
        var loop = 0

        playback: while options.loopCount == 0 || loop < options.loopCount {
            mr_counter_store(loopCounter, Int64(loop))
            for (index, step) in steps.enumerated() {
                target &+= step.delayTicks
                guard RealtimeThread.wait(until: target, spinNs: configuration.spinNs, running: running) != nil else {
                    completed = false
                    break playback
                }
                switch step.action {
                case let .post(event):
                    if options.relativeMouse {
                        if let delta = step.relativeDelta {
                            cursor.x += CGFloat(delta.dx)
                            cursor.y += CGFloat(delta.dy)
                        }
                        if event.type != .keyDown && event.type != .keyUp && event.type != .flagsChanged
                            && event.type != .scrollWheel {
                            event.location = cursor
                        }
                    }
                    (dryEvent ?? event).post(tap: .cghidEventTap)
                    if configuration.recordTiming && lateness.count < lateness.capacity {
                        lateness.append(Int64(bitPattern: mr_ticks_to_ns(mr_now_ticks() &- target)))
                    }
                case let .waitPixel(x, y, rgb, tolerance, timeoutMs):
                    _ = waitForPixel(x: x, y: y, rgb: rgb, tolerance: tolerance, timeoutMs: timeoutMs)
                    target = mr_now_ticks() // later steps are relative to when the condition resolved
                case let .activate(bundleID):
                    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
                    target = mr_now_ticks()
                case .none:
                    break
                }
                switch step.press {
                case let .keyDown(code): heldKeys.insert(code)
                case let .keyUp(code): heldKeys.remove(code)
                case let .buttonDown(button): heldButtons.insert(button)
                case let .buttonUp(button): heldButtons.remove(button)
                case .none: break
                }
                mr_counter_store(indexCounter, Int64(index))
            }
            loop += 1
            target &+= loopDelay
        }

        if !configuration.dryRun { releaseAll(keys: heldKeys, buttons: heldButtons) }
        latenessNs = lateness
        mr_flag_store(running, false)
        onFinish?(completed)
    }

    /// Never leave keys or buttons stuck down when playback stops mid-macro.
    private func releaseAll(keys: Set<UInt16>, buttons: Set<MouseButton>) {
        for code in keys {
            factory.key(code, down: false, flags: 0)?.post(tap: .cghidEventTap)
        }
        let location = CGEvent(source: nil)?.location ?? .zero
        for button in buttons {
            factory.mouse(EventFactory.upType(button), at: location, button: button)?.post(tap: .cghidEventTap)
        }
    }

    private func waitForPixel(x: Double, y: Double, rgb: UInt32, tolerance: UInt8, timeoutMs: UInt32) -> Bool {
        guard let sampler = pixelSampler else { return false }
        let deadline = mr_now_ticks() + mr_ns_to_ticks(UInt64(timeoutMs) * 1_000_000)
        while mr_flag_load(running) {
            if let sample = sampler.rgb(atX: x, y: y), PixelMath.matches(sample, rgb, tolerance: tolerance) {
                return true
            }
            if timeoutMs > 0 && mr_now_ticks() >= deadline { return false }
            usleep(15_000)
        }
        return false
    }
}

public enum PixelMath {
    public static func matches(_ a: UInt32, _ b: UInt32, tolerance: UInt8) -> Bool {
        for shift in [16, 8, 0] as [UInt32] {
            let ca = Int((a >> shift) & 0xFF), cb = Int((b >> shift) & 0xFF)
            if abs(ca - cb) > Int(tolerance) { return false }
        }
        return true
    }
}

import CoreGraphics
import CSupport
import Foundation
import JavaScriptCore
import MacroCore
import Playback

/// Runs JavaScript macros locally with JavaScriptCore. Loops, variables and conditions come from JS itself;
/// the injected API posts input events. Every API call honors `stop()`.
///
/// API: move(x,y) · click(x,y[,button[,count]]) · mouseDown([button]) · mouseUp([button]) · scroll(dx,dy)
///      key(name[,mods]) · keyDown(name[,mods]) · keyUp(name[,mods]) · type(text) · sleep(ms)
///      cursor() → {x,y} · pixel(x,y) → 0xRRGGBB · waitForPixel(x,y,rgb[,tol[,timeoutMs]]) → bool
///      activate(bundleID) · play(macroName) · log(msg) · running() → bool
public final class ScriptRunner {
    public var pixelSampler: PixelSampling?
    public var macroResolver: ((String) -> Macro?)?
    /// Called on the script thread.
    public var onLog: ((String) -> Void)?
    /// Called on the script thread with an error message, or nil on success / stop.
    public var onFinish: ((String?) -> Void)?

    /// Event poster; tests replace it to observe events without touching real input.
    public var post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }

    public var isRunning: Bool { mr_flag_load(running) }

    private let running = mr_flag_create(false)!
    private let factory = EventFactory()
    private var nestedPlayer: MacroPlayer?
    private let nestedLock = NSLock()

    public init() {}

    deinit {
        mr_flag_store(running, false)
        mr_flag_destroy(running)
    }

    public func run(_ source: String) {
        guard !isRunning else { return }
        mr_flag_store(running, true)
        let thread = Thread { [self] in
            let error = execute(source)
            mr_flag_store(running, false)
            onFinish?(error)
        }
        thread.name = "macrecord.script"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Runs synchronously on the calling thread (tests, CLI). Returns an error message or nil.
    public func runSync(_ source: String) -> String? {
        mr_flag_store(running, true)
        defer { mr_flag_store(running, false) }
        return execute(source)
    }

    public func stop() {
        mr_flag_store(running, false)
        nestedLock.lock(); nestedPlayer?.stop(); nestedLock.unlock()
    }

    private static let stopMessage = "__macrecord_stopped__"

    private func execute(_ source: String) -> String? {
        guard let context = JSContext() else { return "JavaScriptCore unavailable" }
        install(into: context)
        factory.warmUp()
        context.evaluateScript(source)
        guard let exception = context.exception else { return nil }
        let message = exception.toString() ?? "error"
        if message.contains(Self.stopMessage) { return nil }
        let line = exception.objectForKeyedSubscript("line")?.toInt32() ?? 0
        return line > 0 ? "line \(line): \(message)" : message
    }

    /// Throws into JS when stopped so loops in the script unwind.
    private func checkRunning() -> Bool {
        if mr_flag_load(running) { return true }
        if let context = JSContext.current() {
            context.exception = JSValue(newErrorFromMessage: Self.stopMessage, in: context)
        }
        return false
    }

    // MARK: - API

    private func install(into context: JSContext) {
        func define(_ name: String, _ block: Any) {
            context.setObject(block, forKeyedSubscript: name as NSString)
        }

        let move: @convention(block) (Double, Double) -> Void = { [unowned self] x, y in
            guard checkRunning() else { return }
            send(.mouseMove(x: x, y: y, dx: 0, dy: 0))
        }
        let click: @convention(block) (Double, Double, JSValue, JSValue) -> Void = { [unowned self] x, y, b, c in
            guard checkRunning() else { return }
            let button = Self.button(b)
            let count = c.isUndefined ? 1 : max(1, Int64(c.toInt32()))
            for state in 1...count {
                send(.mouseDown(button: button, x: x, y: y, clickCount: state))
                send(.mouseUp(button: button, x: x, y: y, clickCount: state))
            }
        }
        let mouseDown: @convention(block) (JSValue) -> Void = { [unowned self] b in
            guard checkRunning() else { return }
            let p = Self.cursor()
            send(.mouseDown(button: Self.button(b), x: p.x, y: p.y, clickCount: 1))
        }
        let mouseUp: @convention(block) (JSValue) -> Void = { [unowned self] b in
            guard checkRunning() else { return }
            let p = Self.cursor()
            send(.mouseUp(button: Self.button(b), x: p.x, y: p.y, clickCount: 1))
        }
        let scroll: @convention(block) (Int32, Int32) -> Void = { [unowned self] dx, dy in
            guard checkRunning() else { return }
            send(.scroll(dx: dx, dy: dy, continuous: false))
        }
        let keyDown: @convention(block) (JSValue, JSValue) -> Void = { [unowned self] k, m in
            guard checkRunning(), let code = keyCode(k) else { return }
            send(.keyDown(keyCode: code, flags: Self.modifiers(m)))
        }
        let keyUp: @convention(block) (JSValue, JSValue) -> Void = { [unowned self] k, m in
            guard checkRunning(), let code = keyCode(k) else { return }
            send(.keyUp(keyCode: code, flags: Self.modifiers(m)))
        }
        let key: @convention(block) (JSValue, JSValue) -> Void = { [unowned self] k, m in
            guard checkRunning(), let code = keyCode(k) else { return }
            let flags = Self.modifiers(m)
            send(.keyDown(keyCode: code, flags: flags))
            send(.keyUp(keyCode: code, flags: flags))
        }
        let type: @convention(block) (String) -> Void = { [unowned self] text in
            for character in text {
                guard checkRunning() else { return }
                let utf16 = Array(String(character).utf16)
                for down in [true, false] {
                    guard let event = factory.key(0, down: down, flags: 0) else { continue }
                    event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    post(event)
                }
            }
        }
        let sleep: @convention(block) (Double) -> Void = { [unowned self] ms in
            guard checkRunning() else { return }
            let deadline = mr_now_ticks() + mr_ns_to_ticks(UInt64(max(ms, 0) * 1_000_000))
            _ = RealtimeThread.wait(until: deadline, spinNs: 200_000, running: running)
            _ = checkRunning()
        }
        let cursor: @convention(block) () -> [String: Double] = {
            let p = Self.cursor()
            return ["x": p.x, "y": p.y]
        }
        let pixel: @convention(block) (Double, Double) -> JSValue = { [unowned self] x, y in
            let context = JSContext.current()!
            guard let value = pixelSampler?.rgb(atX: x, y: y) else { return JSValue(nullIn: context) }
            return JSValue(uInt32: value, in: context)
        }
        let waitForPixel: @convention(block) (Double, Double, UInt32, JSValue, JSValue) -> Bool = {
            [unowned self] x, y, rgb, tol, timeout in
            let tolerance = tol.isUndefined ? 0 : UInt8(clamping: tol.toInt32())
            let timeoutMs = timeout.isUndefined ? 0 : Double(timeout.toInt32())
            let start = mr_now_ticks()
            while checkRunning() {
                if let value = pixelSampler?.rgb(atX: x, y: y), PixelMath.matches(value, rgb, tolerance: tolerance) {
                    return true
                }
                if timeoutMs > 0 && Double(mr_ticks_to_ns(mr_now_ticks() - start)) / 1e6 >= timeoutMs { return false }
                usleep(15_000)
            }
            return false
        }
        let activate: @convention(block) (String) -> Void = { bundleID in
            NSRunningApplicationProxy.activate(bundleID)
        }
        let play: @convention(block) (String) -> Bool = { [unowned self] name in
            guard checkRunning(), let macro = macroResolver?(name) else { return false }
            let player = MacroPlayer()
            player.pixelSampler = pixelSampler
            let done = DispatchSemaphore(value: 0)
            player.onFinish = { _ in done.signal() }
            nestedLock.lock(); nestedPlayer = player; nestedLock.unlock()
            player.play(macro, options: PlaybackOptions(loopCount: 1, speed: macro.options.speed,
                                                        relativeMouse: macro.options.relativeMouse))
            done.wait()
            nestedLock.lock(); nestedPlayer = nil; nestedLock.unlock()
            return checkRunning()
        }
        let log: @convention(block) (JSValue) -> Void = { [unowned self] value in
            onLog?(value.toString() ?? "")
        }
        let isRunning: @convention(block) () -> Bool = { [unowned self] in mr_flag_load(running) }

        define("move", move); define("click", click); define("mouseDown", mouseDown); define("mouseUp", mouseUp)
        define("scroll", scroll); define("key", key); define("keyDown", keyDown); define("keyUp", keyUp)
        define("type", type); define("sleep", sleep); define("cursor", cursor); define("pixel", pixel)
        define("waitForPixel", waitForPixel); define("activate", activate); define("play", play)
        define("log", log); define("running", isRunning)
    }

    private func send(_ kind: MacroEvent.Kind) {
        if let event = factory.make(kind) { post(event) }
    }

    private func keyCode(_ value: JSValue) -> UInt16? {
        if value.isNumber { return UInt16(clamping: value.toInt32()) }
        guard let name = value.toString(), let code = KeyNames.code(for: name) else {
            if let context = JSContext.current() {
                context.exception = JSValue(newErrorFromMessage: "unknown key '\(value.toString() ?? "")'", in: context)
            }
            return nil
        }
        return code
    }

    static func button(_ value: JSValue) -> MouseButton {
        switch value.isUndefined ? "left" : (value.toString() ?? "left").lowercased() {
        case "right": return .right
        case "middle", "center": return .center
        case "back": return .back
        case "forward": return .forward
        default: return .left
        }
    }

    /// "cmd+shift" style modifier strings.
    static func modifiers(_ value: JSValue) -> UInt64 {
        guard !value.isUndefined, let text = value.toString()?.lowercased() else { return 0 }
        var flags = ModifierFlags()
        for part in text.split(whereSeparator: { "+ ,".contains($0) }) {
            switch part {
            case "cmd", "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt", "option", "alt": flags.insert(.option)
            case "ctrl", "control": flags.insert(.control)
            default: break
            }
        }
        return flags.rawValue
    }

    static func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
}

import AppKit

enum NSRunningApplicationProxy {
    static func activate(_ bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }
}

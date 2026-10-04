import CoreGraphics
import Foundation

/// Fires once when the user physically moves the mouse beyond a threshold or presses a key/button,
/// ignoring macrecord's own synthetic events. Used to give control back to the user mid-playback.
public final class InputWatcher {
    private let recorder = EventRecorder(options: .init(captureMouseMoves: true, captureKeyboard: true,
                                                        ignoreOwnEvents: true, storeEvents: false))
    private var fired = false
    private var travelled: Double = 0
    private let lock = NSLock()

    public init() {}

    /// `handler` runs on the main queue.
    public func start(mouseThreshold: Double = 40, handler: @escaping () -> Void) {
        lock.lock(); fired = false; travelled = 0; lock.unlock()
        recorder.onRawEvent = { [weak self] raw in
            guard let self else { return }
            let type = CGEventType(rawValue: raw.type)
            let isMotion = type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
            // Releases are ignored: the shortcut that started playback is released after the watcher starts.
            let isPress = type == .keyDown || type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
            self.lock.lock()
            if isMotion { self.travelled += Double(abs(raw.dx) + abs(raw.dy)) }
            let trigger = !self.fired && (isPress || (isMotion && self.travelled >= mouseThreshold))
            if trigger { self.fired = true }
            self.lock.unlock()
            if trigger { DispatchQueue.main.async(execute: handler) }
        }
        recorder.options.captureKeyboard = true
        if (try? recorder.start()) == nil {
            // Without Input Monitoring a keyboard tap can't be created; mouse-only still works.
            recorder.options.captureKeyboard = false
            try? recorder.start()
        }
    }

    public func stop() {
        recorder.stop()
        recorder.onRawEvent = nil
    }
}

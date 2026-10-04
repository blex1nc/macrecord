import CoreGraphics
import CSupport
import Foundation
import MacroCore
import os

/// Records global input with a passive (listen-only) event tap on a dedicated run-loop thread.
/// The tap callback only appends a fixed-size struct to a pre-reserved buffer, so it never blocks system input.
public final class EventRecorder {
    public enum RecorderError: Error {
        case tapCreationFailed
        case alreadyRunning
    }

    public private(set) var isRecording = false
    /// Events captured so far (safe to read from any thread).
    public var capturedCount: Int { Int(mr_counter_load(counter)) }

    private let buffer: RawEventBuffer
    private let counter = mr_counter_create()!
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private let ready = DispatchSemaphore(value: 0)
    private var startError: RecorderError?
    /// Applied on the next `start()`.
    public var options: Options

    public struct Options: Sendable {
        public var captureMouseMoves: Bool
        public var captureKeyboard: Bool
        public var ignoreOwnEvents: Bool
        /// False for watchers that only need `onRawEvent` and must not accumulate memory.
        public var storeEvents: Bool
        public init(captureMouseMoves: Bool = true, captureKeyboard: Bool = true, ignoreOwnEvents: Bool = true,
                    storeEvents: Bool = true) {
            self.captureMouseMoves = captureMouseMoves
            self.captureKeyboard = captureKeyboard
            self.ignoreOwnEvents = ignoreOwnEvents
            self.storeEvents = storeEvents
        }
    }

    /// Optional hook invoked on the tap thread for every accepted event (benchmarks). Must be cheap.
    public var onRawEvent: ((RawEvent) -> Void)?

    public init(options: Options = Options(), reserveCapacity: Int = 1 << 18) {
        self.options = options
        self.buffer = RawEventBuffer(reserve: options.storeEvents ? reserveCapacity : 0)
    }

    deinit {
        stop()
        mr_counter_destroy(counter)
    }

    public func start() throws {
        guard !isRecording else { throw RecorderError.alreadyRunning }
        buffer.removeAll()
        mr_counter_store(counter, 0)
        startError = nil
        let thread = Thread { [unowned self] in self.runTapThread() }
        thread.name = "macrecord.capture"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()
        if let startError { throw startError }
        isRecording = true
    }

    /// Stops the tap and returns the recording converted to macro events.
    @discardableResult
    public func stop() -> [MacroEvent] {
        guard isRecording, let runLoop else { return [] }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        CFRunLoopStop(runLoop)
        ready.wait() // thread signals after leaving the run loop
        isRecording = false
        self.runLoop = nil
        self.thread = nil
        return RawEventConverter.convert(buffer.snapshot())
    }

    private func runTapThread() {
        var mask: CGEventMask = 0
        var types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .otherMouseDown, .otherMouseUp, .scrollWheel]
        if options.captureMouseMoves { types += [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged] }
        if options.captureKeyboard { types += [.keyDown, .keyUp, .flagsChanged] }
        for type in types { mask |= CGEventMask(1) << type.rawValue }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: recorderTapCallback, userInfo: refcon) else {
            startError = .tapCreationFailed
            ready.signal()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let loop = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(loop, source, .commonModes)
        self.tap = tap
        self.runLoop = loop
        CGEvent.tapEnable(tap: tap, enable: true)
        // Signal from inside the run loop so a stop() right after start() can't be lost.
        let ready = self.ready
        let entered = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.entry.rawValue,
                                                         false, 0) { _, _ in ready.signal() }
        CFRunLoopAddObserver(loop, entered, .defaultMode)
        CFRunLoopRun()
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(tap)
        self.tap = nil
        ready.signal()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        default:
            break
        }
        if options.ignoreOwnEvents && event.getIntegerValueField(.eventSourceUserData) == macrecordEventTag { return }
        let raw = RawEvent(type: type, event: event, receivedTicks: mr_now_ticks())
        if options.storeEvents { buffer.append(raw) }
        mr_counter_add(counter, 1)
        onRawEvent?(raw)
    }
}

private func recorderTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<EventRecorder>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

/// Append-only storage guarded by an uncontended unfair lock; capacity is reserved up front.
final class RawEventBuffer: @unchecked Sendable {
    private var storage: ContiguousArray<RawEvent>
    private let lock = OSAllocatedUnfairLock()
    private let reserve: Int

    init(reserve: Int) {
        self.reserve = reserve
        storage = []
        storage.reserveCapacity(reserve)
    }

    func append(_ event: RawEvent) {
        lock.withLockUnchecked { storage.append(event) }
    }

    func snapshot() -> [RawEvent] {
        lock.withLockUnchecked { Array(storage) }
    }

    func removeAll() {
        lock.withLockUnchecked {
            storage.removeAll(keepingCapacity: true)
            if storage.capacity < reserve { storage.reserveCapacity(reserve) }
        }
    }
}

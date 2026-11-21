import Foundation
import os

/// App-side handle to the `macrecord-clickd` helper: a separate, UI-free process that runs `ClickService`, so the
/// trigger tap and the real-time clicker never share a process with SwiftUI. Talks over stdin/stdout pipes; the
/// helper stops clicking and exits when its stdin closes (app quit or crash). Main thread only.
public final class AgentClient: ClickBackend {
    public var onEvent: ((ClickServiceEvent) -> Void)?
    public var isAlive: Bool { process.isRunning }
    /// Called on the main thread if the helper exits while in use.
    public var onExit: (() -> Void)?

    private let process: Process
    private let input: FileHandle
    private static let log = Logger(subsystem: "io.github.blex1nc.macrecord", category: "clickd")

    /// The helper next to the app's executable (inside the bundle, or in the SwiftPM build directory).
    public static var bundledExecutable: URL? {
        guard let url = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("macrecord-clickd"),
            FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    /// Launches the helper and waits for its handshake. Returns nil, after terminating it, if it does not start,
    /// does not answer within `timeout`, or lacks the permission to tap and post events.
    public static func launch(executable: URL, timeout: TimeInterval = 2) -> AgentClient? {
        let process = Process()
        process.executableURL = executable
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        do { try process.run() } catch {
            log.error("helper failed to launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let reader = Reader()
        stdout.fileHandleForReading.readabilityHandler = { reader.received($0.availableData) }
        let ready = reader.waitForReady(timeout: timeout)
        guard let ready, ready.accessibility, ready.postEvents else {
            log.error("helper not usable (handshake: \(String(describing: ready), privacy: .public)); using in-process clicker")
            stdout.fileHandleForReading.readabilityHandler = nil
            stdin.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
            return nil
        }
        // A write after the helper died must fail with EPIPE, not kill macrecord with SIGPIPE.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        log.notice("helper ready, pid \(process.processIdentifier, privacy: .public)")
        return AgentClient(process: process, input: stdin.fileHandleForWriting, output: stdout.fileHandleForReading,
                           reader: reader)
    }

    private init(process: Process, input: FileHandle, output: FileHandle, reader: Reader) {
        self.process = process
        self.input = input
        reader.deliver { [weak self] event in self?.onEvent?(event) }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                output.readabilityHandler = nil
                self?.onExit?()
            }
        }
    }

    deinit { shutdown() }

    public func apply(_ settings: ClickServiceSettings) { send(.apply(settings)) }
    public func start(_ trigger: ClickTrigger) { send(.start(trigger)) }
    public func stop() { send(.stop) }

    public func shutdown() {
        guard process.isRunning else { return }
        send(.stop)
        input.closeFile() // EOF: the helper stops and exits
    }

    private func send(_ command: AgentCommand) {
        guard process.isRunning else { return }
        do { try input.write(contentsOf: AgentWire.encode(command)) } catch {
            Self.log.error("write to helper failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}

/// Splits the helper's stdout into events on the pipe's queue. The first `.ready` answers the handshake (the app's
/// main thread is blocked waiting for it); every later event goes to the main thread.
private final class Reader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var ready: (accessibility: Bool, postEvents: Bool)?
    private var queued: [ClickServiceEvent] = []
    private var handler: ((ClickServiceEvent) -> Void)?
    private let readySignal = DispatchSemaphore(value: 0)

    func received(_ data: Data) {
        lock.lock()
        if data.isEmpty { lock.unlock(); readySignal.signal(); return } // EOF: stop waiting
        buffer.append(data)
        var forward: [ClickServiceEvent] = []
        for event in AgentWire.decodeLines(ClickServiceEvent.self, from: &buffer) {
            if ready == nil, case let .ready(accessibility, postEvents) = event {
                ready = (accessibility, postEvents)
                readySignal.signal()
            } else if handler == nil {
                queued.append(event)
            } else {
                forward.append(event)
            }
        }
        let handler = self.handler
        lock.unlock()
        if let handler, !forward.isEmpty { DispatchQueue.main.async { forward.forEach(handler) } }
    }

    func waitForReady(timeout: TimeInterval) -> (accessibility: Bool, postEvents: Bool)? {
        _ = readySignal.wait(timeout: .now() + timeout)
        lock.lock(); defer { lock.unlock() }
        return ready
    }

    /// Main thread. Flushes events that arrived before the handler was set.
    func deliver(_ handler: @escaping (ClickServiceEvent) -> Void) {
        lock.lock()
        self.handler = handler
        let pending = queued
        queued = []
        lock.unlock()
        pending.forEach(handler)
    }
}

import CSupport
import Darwin
import Foundation

public enum RealtimeThread {
    /// Starts `body` on a dedicated thread promoted to the Mach real-time band.
    public static func start(name: String, body: @escaping () -> Void) {
        let thread = Thread {
            // Aperiodic: up to 500 µs of work must finish within 1 ms once we wake.
            _ = mr_thread_set_realtime(0, 500_000, 1_000_000)
            body()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Waits until `deadline` (mach ticks) in short slices so `running` is honored even during long delays.
    /// Returns the wake time, or nil if stopped.
    public static func wait(until deadline: UInt64, spinNs: UInt64, running: OpaquePointer) -> UInt64? {
        let slice = mr_ns_to_ticks(20_000_000)
        let spin = mr_ns_to_ticks(spinNs)
        while true {
            guard mr_flag_load(running) else { return nil }
            let now = mr_now_ticks()
            if deadline <= now { return now }
            if deadline - now > slice + spin {
                mach_wait_until(now + slice)
            } else {
                return mr_wait_until(deadline, spinNs)
            }
        }
    }
}

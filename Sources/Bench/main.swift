import Capture
import CoreGraphics
import CSupport
import Foundation
import MacroCore
import Permissions
import Playback

// macrecord-bench — headless engine harness.
//   macrecord-bench jitter [events] [intervalUs] [spinUs]   measure playback timing precision
//   macrecord-bench record <seconds> <file>                 record global input to a macro file
//   macrecord-bench play <file> [loops] [speed]             play a macro file

func percentile(_ sorted: [Int64], _ p: Double) -> Int64 {
    guard !sorted.isEmpty else { return 0 }
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
}

func report(_ title: String, _ values: [Int64]) {
    let s = values.sorted()
    let mean = s.isEmpty ? 0 : Double(s.reduce(0, +)) / Double(s.count)
    let us = { (v: Int64) in String(format: "%.1f", Double(v) / 1000) }
    print("\(title) (n=\(s.count)): mean=\(String(format: "%.1f", mean / 1000))µs p50=\(us(percentile(s, 0.5)))µs "
        + "p99=\(us(percentile(s, 0.99)))µs max=\(us(s.last ?? 0))µs")
}

func requirePermissions() {
    guard Permissions.postEventsGranted else {
        print("Accessibility permission required: System Settings → Privacy & Security → Accessibility")
        exit(2)
    }
}

func jitter(events count: Int, intervalUs: UInt64, spinUs: UInt64) -> Bool {
    requirePermissions()
    // Dry run: the player posts no-op events through the real WindowServer path,
    // so timing is measured without touching the user's cursor or keyboard.
    let events = (0..<count).map { _ in
        MacroEvent(delayNs: intervalUs * 1000, kind: .mouseMove(x: 0, y: 0, dx: 0, dy: 0))
    }
    let player = MacroPlayer()
    player.configuration.recordTiming = true
    player.configuration.dryRun = true
    player.configuration.spinNs = spinUs * 1000
    let done = DispatchSemaphore(value: 0)
    player.onFinish = { _ in done.signal() }
    player.play(Macro(name: "bench", events: events))
    done.wait()

    print("== jitter: \(count) events @ \(intervalUs)µs, spin \(spinUs)µs (dry run) ==")
    let lateness = player.latenessNs
    report("lateness (post completed − scheduled)", lateness)
    print(String(format: "drift at last event: %.1f µs", Double(lateness.last ?? 0) / 1000))
    let p99 = percentile(lateness.sorted(), 0.99)
    let pass = p99 < 1_000_000
    print(pass ? "PASS: scheduler p99 < 1 ms" : "FAIL: scheduler p99 >= 1 ms")
    return pass
}

func record(seconds: Double, to path: String) throws {
    let recorder = EventRecorder()
    try recorder.start()
    print("Recording for \(seconds)s…")
    Thread.sleep(forTimeInterval: seconds)
    let events = RecordingSanitizer.sanitize(recorder.stop())
    let macro = Macro(name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, events: events)
    try MacroStore.encode(macro).write(to: URL(fileURLWithPath: path))
    print("Saved \(events.count) events (\(Double(macro.durationNs) / 1e9)s) to \(path)")
}

func play(path: String, loops: Int, speed: Double) throws {
    requirePermissions()
    let macro = try MacroStore.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    let player = MacroPlayer()
    let done = DispatchSemaphore(value: 0)
    player.onFinish = { _ in done.signal() }
    player.play(macro, options: PlaybackOptions(loopCount: loops, speed: speed))
    done.wait()
    print("Played \(macro.events.count) events × \(loops)")
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "jitter":
    let a = Array(args.dropFirst()).compactMap { UInt64($0) }
    let ok = jitter(events: Int(a.count > 0 ? a[0] : 1000), intervalUs: a.count > 1 ? a[1] : 1000,
                    spinUs: a.count > 2 ? a[2] : 200)
    exit(ok ? 0 : 1)
case "record":
    let a = Array(args.dropFirst())
    guard a.count == 2, let seconds = Double(a[0]) else { print("usage: record <seconds> <file>"); exit(64) }
    try record(seconds: seconds, to: a[1])
case "play":
    let a = Array(args.dropFirst())
    guard !a.isEmpty else { print("usage: play <file> [loops] [speed]"); exit(64) }
    try play(path: a[0], loops: a.count > 1 ? Int(a[1]) ?? 1 : 1, speed: a.count > 2 ? Double(a[2]) ?? 1 : 1)
default:
    print("usage: macrecord-bench jitter [events] [intervalUs] [spinUs] | record <s> <file> | play <file> [loops] [speed]")
    exit(64)
}

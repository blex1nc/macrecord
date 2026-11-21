import Foundation
import Testing
import MacroCore
import Hotkeys
@testable import ClickService

@Suite struct ClickServiceTests {
    @Test func wireRoundTripsCommandsAndEvents() {
        let settings = ClickServiceSettings(autoclick: AutoClickConfig(clicksPerSecond: 20, mode: .hold),
                                            triggerButton: 4, triggerArmed: true, excludedPIDs: [42])
        var buffer = AgentWire.encode(AgentCommand.apply(settings)) + AgentWire.encode(AgentCommand.start(.hotkey))
            + AgentWire.encode(AgentCommand.stop)
        #expect(AgentWire.decodeLines(AgentCommand.self, from: &buffer) == [.apply(settings), .start(.hotkey), .stop])
        #expect(buffer.isEmpty)

        let events: [ClickServiceEvent] = [.ready(accessibility: true, postEvents: false),
                                           .started(delivery: .app, pid: 7), .progress(clicks: 3),
                                           .stopped(clicks: 9), .triggerUnavailable,
                                           .slowTaps(["Supercharge"])]
        var stream = events.reduce(Data()) { $0 + AgentWire.encode($1) }
        #expect(AgentWire.decodeLines(ClickServiceEvent.self, from: &stream) == events)
    }

    @Test func wireKeepsPartialLinesAndSkipsGarbage() {
        let line = AgentWire.encode(ClickServiceEvent.progress(clicks: 5))
        var buffer = Data("not json\n".utf8) + line.prefix(4)
        #expect(AgentWire.decodeLines(ClickServiceEvent.self, from: &buffer).isEmpty)
        #expect(buffer.count == 4)
        buffer.append(line.dropFirst(4))
        #expect(AgentWire.decodeLines(ClickServiceEvent.self, from: &buffer) == [.progress(clicks: 5)])
    }

    /// Read-only: lists taps, never creates one.
    @Test func tapAuditExcludesOwnProcess() {
        let own = ProcessInfo.processInfo.processIdentifier
        let taps = EventTapAudit.activeMouseTaps(excluding: [own])
        #expect(!taps.contains { $0.pid == own })
        #expect(taps.map(\.avgMs) == taps.map(\.avgMs).sorted(by: >))
    }

    @Test func stallDetectionNeedsLateMotionAndFastTrigger() {
        var motion = MotionProbe.Stats()
        for _ in 0..<100 { motion.motions += 1; motion.age.add(1_000_000) }
        var tap = MouseButtonTrigger.Stats()
        tap.callbackAge.add(300_000)
        #expect(!ClickService.motionStalledDownstream(motion: motion, tap: tap))   // 1 ms: smooth
        for _ in 0..<5 { motion.motions += 1; motion.age.add(46_000_000) }
        #expect(ClickService.motionStalledDownstream(motion: motion, tap: tap))    // 46 ms behind a fast trigger
        tap.callbackAge.add(40_000_000)
        #expect(!ClickService.motionStalledDownstream(motion: motion, tap: tap))   // late already at our tap
    }
}

import Foundation
import Testing
@testable import MacroCore

private func move(_ x: Double, _ y: Double, delay: UInt64 = 1_000, dx: Int64 = 1, dy: Int64 = 0) -> MacroEvent {
    MacroEvent(delayNs: delay, kind: .mouseMove(x: x, y: y, dx: dx, dy: dy))
}

private func key(_ code: UInt16, down: Bool, delay: UInt64 = 1_000) -> MacroEvent {
    MacroEvent(delayNs: delay, kind: down ? .keyDown(keyCode: code, flags: 0) : .keyUp(keyCode: code, flags: 0))
}

private func flags(_ delay: UInt64 = 1_000) -> MacroEvent {
    MacroEvent(delayNs: delay, kind: .flagsChanged(keyCode: 55, flags: 0))
}

@Suite struct SerializationTests {
    @Test func roundTripPreservesEverything() throws {
        let macro = Macro(name: "test", events: [
            move(10, 20),
            MacroEvent(delayNs: 5, kind: .mouseDown(button: .right, x: 1, y: 2, clickCount: 2)),
            MacroEvent(delayNs: 6, kind: .scroll(dx: -3, dy: 4, continuous: true)),
            key(12, down: true),
            MacroEvent(delayNs: 7, kind: .waitForPixel(x: 5, y: 6, rgb: 0xFF00FF, tolerance: 8, timeoutMs: 100)),
            MacroEvent(delayNs: 8, kind: .activateApp(bundleID: "com.apple.finder")),
            MacroEvent(delayNs: 9, kind: .delay),
        ], options: PlaybackOptions(loopCount: 3, speed: 2), hotkey: KeyCombo(keyCode: 15, modifiers: 0x100000))
        let decoded = try MacroStore.decode(MacroStore.encode(macro))
        #expect(decoded.events == macro.events)
        #expect(decoded.options == macro.options)
        #expect(decoded.hotkey == macro.hotkey)
        #expect(decoded.schemaVersion == Macro.currentSchemaVersion)
    }

    @Test func rejectsNewerSchema() throws {
        var json = String(decoding: try MacroStore.encode(Macro(name: "x")), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        #expect(throws: MacroStore.StoreError.unsupportedSchema(99)) { try MacroStore.decode(Data(json.utf8)) }
    }

    @Test func storeSavesLoadsDeletes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MacroStore(directory: dir)
        let macro = Macro(name: "saved", events: [move(1, 1)])
        try store.save(macro)
        #expect(try store.loadAll().map(\.id) == [macro.id])
        let imported = try store.importMacro(from: store.url(for: macro.id))
        #expect(imported.id != macro.id)
        #expect(try store.loadAll().count == 2)
        try store.delete(id: macro.id)
        #expect(try store.loadAll().map(\.id) == [imported.id])
    }
}

@Suite struct SanitizerTests {
    @Test func stripsStopShortcutAndLeadingModifierRelease() {
        let raw = [flags(500), key(5, down: true, delay: 100), key(5, down: false), flags(), key(15, down: true), key(15, down: false), flags()]
        let clean = RecordingSanitizer.sanitize(raw, stopKeyCode: 15)
        #expect(clean.map(\.kind) == [.keyDown(keyCode: 5, flags: 0), .keyUp(keyCode: 5, flags: 0)])
        #expect(clean[0].delayNs == 0)
    }

    @Test func stripsStartShortcutRelease() {
        let raw = [key(15, down: false), flags(), flags(), key(5, down: true), key(5, down: false)]
        let clean = RecordingSanitizer.sanitize(raw, stopKeyCode: 15)
        #expect(clean.map(\.kind) == [.keyDown(keyCode: 5, flags: 0), .keyUp(keyCode: 5, flags: 0)])
    }

    @Test func trimsOnlyTrailingClicksOnOwnUI() {
        let click = { (x: Double) in MacroEvent(delayNs: 1, kind: .mouseDown(button: .left, x: x, y: 0, clickCount: 1)) }
        let isOwnUI = { (x: Double, _: Double) in x >= 1000 }
        // user click, then status-item click and menu-item click on our UI
        let viaMenu = [click(10), key(1, down: true), click(1000), move(1001, 0), click(1050), move(1, 1)]
        #expect(RecordingSanitizer.trimTrailingUIClicks(viaMenu, isOwnUI: isOwnUI).count == 2)
        // last click was the user's: nothing trimmed, even if it happened just before stopping
        let userLast = [click(1000), click(10), move(1, 1)]
        #expect(RecordingSanitizer.trimTrailingUIClicks(userLast, isOwnUI: isOwnUI).count == 3)
        #expect(RecordingSanitizer.trimTrailingUIClicks([move(1, 1)], isOwnUI: isOwnUI).count == 1)
    }

    /// Files written before the compact format were pretty-printed with an id per event.
    @Test func loadsPrettyPrintedLegacyFiles() throws {
        let legacy = """
        {
          "createdAt" : "2026-10-04T13:41:00Z",
          "events" : [
            { "delayNs" : 0, "id" : "645CA6E1-6A07-46EE-9626-5B5CD040147B",
              "kind" : { "mouseMove" : { "dx" : 5, "dy" : 0, "x" : 2791, "y" : -306 } } }
          ],
          "id" : "745CA6E1-6A07-46EE-9626-5B5CD040147B",
          "name" : "Recording 1",
          "options" : { "loopCount" : 1, "loopDelayMs" : 0, "relativeMouse" : false, "speed" : 1 },
          "schemaVersion" : 1
        }
        """
        let macro = try MacroStore.decode(Data(legacy.utf8))
        #expect(macro.events.map(\.kind) == [.mouseMove(x: 2791, y: -306, dx: 5, dy: 0)])
    }

    @Test func compactEncodingOmitsIDs() throws {
        let macro = Macro(name: "m", events: [move(1, 2)])
        let json = String(decoding: try MacroStore.encode(macro), as: UTF8.self)
        #expect(!json.contains(macro.events[0].id.uuidString))
        #expect(!json.contains("\n"))
        // files written before this change carried an id per event; they must still load
        let legacy = json.replacingOccurrences(of: "{\"delayNs\"", with: "{\"id\":\"\(UUID().uuidString)\",\"delayNs\"")
        #expect(try MacroStore.decode(Data(legacy.utf8)).events.map(\.kind) == macro.events.map(\.kind))
    }

    @Test func dropsReleasesWithoutPress() {
        let raw = [key(15, down: false), key(3, down: true), key(3, down: false),
                   MacroEvent(delayNs: 1, kind: .mouseUp(button: .left, x: 0, y: 0, clickCount: 1))]
        let clean = RecordingSanitizer.sanitize(raw)
        #expect(clean.count == 2)
    }

    @Test func carryDelaysKeepsAbsoluteTiming() {
        let events = [move(0, 0, delay: 10), move(1, 0, delay: 20), move(2, 0, delay: 30)]
        let result = RecordingSanitizer.carryDelays(events, droppingIndices: [1])
        #expect(result.map(\.delayNs) == [10, 50])
    }
}

@Suite struct EditingTests {
    @Test func simplifyKeepsEndpointsAndTotals() {
        let line = (0...100).map { move(Double($0), Double($0) * 0.5, delay: 1_000) }
        let simplified = MacroEditing.simplifyMouseMoves(line, tolerance: 0.5)
        #expect(simplified.count == 2)
        #expect(simplified.reduce(0) { $0 + $1.delayNs } == 101_000)
        if case let .mouseMove(x, _, dx, _) = simplified.last!.kind {
            #expect(x == 100)
            #expect(dx == 100) // carried relative motion from dropped moves
        } else {
            Issue.record("last event should be a move")
        }
    }

    @Test func simplifyKeepsCorners() {
        let path = (0...10).map { move(Double($0), 0) } + (1...10).map { move(10, Double($0)) }
        let simplified = MacroEditing.simplifyMouseMoves(path, tolerance: 0.5)
        #expect(simplified.compactMap { $0.kind.position.map { [$0.x, $0.y] } } == [[0, 0], [10, 0], [10, 10]])
    }

    @Test func simplifyDoesNotCrossNonMoveEvents() {
        let events = [move(0, 0), move(1, 0), move(2, 0), key(1, down: true), move(3, 0), move(4, 0), move(5, 0)]
        let simplified = MacroEditing.simplifyMouseMoves(events, tolerance: 1)
        #expect(simplified.count == 5)
    }

    @Test func removeMouseMovesKeepsDragsAndTiming() {
        let drag = MacroEvent(delayNs: 5, kind: .mouseDrag(button: .left, x: 0, y: 0, dx: 0, dy: 0))
        let result = MacroEditing.removeMouseMoves([move(0, 0, delay: 10), drag, move(1, 1, delay: 3), key(1, down: true, delay: 2)])
        #expect(result.count == 2)
        #expect(result.map(\.delayNs) == [15, 5])
    }

    @Test func scaleDelays() {
        #expect(MacroEditing.scaleDelays([move(0, 0, delay: 1000)], by: 0.5)[0].delayNs == 500)
    }
}

@Suite struct AutoClickConfigTests {
    @Test func intervalAndClamping() {
        #expect(AutoClickConfig(clicksPerSecond: 100).intervalNs == 10_000_000)
        #expect(AutoClickConfig(clicksPerSecond: 1_000_000).intervalNs == 500_000)
        #expect(AutoClickConfig(clicksPerSecond: 0).intervalNs == 10_000_000_000)
    }

    @Test func jitterStaysInBounds() {
        let config = AutoClickConfig(clicksPerSecond: 10, timingJitter: 0.2)
        #expect(config.jitteredIntervalNs(random: 1) == 120_000_000)
        #expect(config.jitteredIntervalNs(random: -1) == 80_000_000)
        #expect(config.jitteredIntervalNs(random: 5) == 120_000_000)
    }

    @Test func holdNeverOverlapsNextClick() {
        #expect(AutoClickConfig(clicksPerSecond: 100, holdDurationMs: 50).effectiveHoldNs == 5_000_000)
        #expect(AutoClickConfig(clicksPerSecond: 100, clickType: .double, holdDurationMs: 50).effectiveHoldNs == 2_500_000)
        #expect(AutoClickConfig(clicksPerSecond: 1, holdDurationMs: 20).effectiveHoldNs == 20_000_000)
    }

    @Test func keyNames() {
        #expect(KeyNames.describe(KeyCombo(keyCode: 15, modifiers: ModifierFlags([.command, .option]).rawValue)) == "⌥⌘R")
    }

    @Test func mouseTriggerNeverAllowsLeftOrRight() {
        #expect(!MouseTrigger.isAllowed(0))
        #expect(!MouseTrigger.isAllowed(1))
        #expect(MouseTrigger.isAllowed(2) && MouseTrigger.isAllowed(4))
        #expect(!MouseTrigger.matches(buttonNumber: 0, userData: 0, trigger: 0))
    }

    @Test func mouseTriggerIgnoresOwnAndOtherButtons() {
        #expect(MouseTrigger.matches(buttonNumber: 3, userData: 0, trigger: 3))
        #expect(!MouseTrigger.matches(buttonNumber: 4, userData: 0, trigger: 3))
        #expect(!MouseTrigger.matches(buttonNumber: 3, userData: macrecordEventTag, trigger: 3))
    }

    @Test func autoClickDeliveryDecodesOldSettings() throws {
        let old = try JSONEncoder().encode(AutoClickConfig())
        let json = String(decoding: old, as: UTF8.self)
        #expect(!json.contains("delivery"))
        let decoded = try JSONDecoder().decode(AutoClickConfig.self, from: old)
        #expect(decoded.delivery == nil)
        #expect(decoded.effectiveDelivery == .system)

        let app = AutoClickConfig(delivery: .app)
        let roundTrip = try JSONDecoder().decode(AutoClickConfig.self, from: JSONEncoder().encode(app))
        #expect(roundTrip.effectiveDelivery == .app)
    }

    @Test func latencyHistogramPercentiles() {
        var h = LatencyHistogram()
        #expect(h.percentileNs(0.99) == 0)
        for _ in 0..<99 { h.add(3_000) }     // 3 µs → bucket < 4 µs
        h.add(5_000_000)                      // 5 ms outlier
        #expect(h.count == 100)
        #expect(h.maxNs == 5_000_000)
        #expect(h.percentileNs(0.5) == 4_000)
        #expect(h.percentileNs(0.99) == 4_000)
        #expect(h.percentileNs(1) == 5_000_000)
    }

    @Test func eventAgeHandlesTicksAndNanoseconds() {
        let ticksToNs: (UInt64) -> UInt64 = { $0 * 125 / 3 }   // Apple silicon: 24 MHz ticks
        let nowTicks: UInt64 = 195_925_951_720
        let nowNs = ticksToNs(nowTicks)
        // Timestamp in ticks, 24_000 ticks (1 ms) old.
        #expect(EventAge.ns(timestamp: nowTicks - 24_000, nowTicks: nowTicks, nowUptimeNs: nowNs,
                            ticksToNs: ticksToNs) == 1_000_000)
        // Timestamp in nanoseconds, 2 ms old.
        #expect(EventAge.ns(timestamp: nowNs - 2_000_000, nowTicks: nowTicks, nowUptimeNs: nowNs,
                            ticksToNs: ticksToNs) == 2_000_000)
        #expect(EventAge.ns(timestamp: 0, nowTicks: nowTicks, nowUptimeNs: nowNs, ticksToNs: ticksToNs) == nil)
    }
}

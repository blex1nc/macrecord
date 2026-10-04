import CoreGraphics
import Foundation
import Testing
import MacroCore
@testable import Scripting

/// Scripts run with a recording poster, so no real input is ever generated.
@Suite struct ScriptingTests {
    final class Sink: @unchecked Sendable { var events: [CGEvent] = [] }

    func makeRunner() -> (ScriptRunner, Sink) {
        let runner = ScriptRunner()
        let sink = Sink()
        runner.post = { sink.events.append($0) }
        return (runner, sink)
    }

    @Test func loopsAndClicks() {
        let (runner, sink) = makeRunner()
        #expect(runner.runSync("for (let i = 0; i < 3; i++) click(10 * i, 5, 'right');") == nil)
        #expect(sink.events.map(\.type) == Array(repeating: [CGEventType.rightMouseDown, .rightMouseUp], count: 3).flatMap { $0 })
        #expect(sink.events[4].location == CGPoint(x: 20, y: 5))
    }

    @Test func keysWithModifiers() {
        let (runner, sink) = makeRunner()
        #expect(runner.runSync("key('r', 'cmd+shift'); key(53)") == nil)
        #expect(sink.events.count == 4)
        #expect(sink.events[0].getIntegerValueField(.keyboardEventKeycode) == 15)
        #expect(sink.events[0].flags.contains([.maskCommand, .maskShift]))
        #expect(sink.events[2].getIntegerValueField(.keyboardEventKeycode) == 53)
    }

    @Test func typeText() {
        let (runner, sink) = makeRunner()
        #expect(runner.runSync("type('hé')") == nil)
        #expect(sink.events.count == 4)
    }

    @Test func reportsErrorsWithLine() {
        let (runner, _) = makeRunner()
        let error = runner.runSync("\n\nnotAFunction()")
        #expect(error?.contains("line 3") == true)
        #expect(runner.runSync("key('nope')")?.contains("unknown key") == true)
    }

    @Test func sleepWaits() {
        let (runner, _) = makeRunner()
        let start = Date()
        #expect(runner.runSync("sleep(30)") == nil)
        #expect(Date().timeIntervalSince(start) >= 0.03)
    }

    @Test func logs() {
        let (runner, _) = makeRunner()
        var lines: [String] = []
        runner.onLog = { lines.append($0) }
        _ = runner.runSync("log('a' + 1)")
        #expect(lines == ["a1"])
    }
}

import Foundation
import CoreGraphics
import CSupport
import Testing
import MacroCore
@testable import Playback

@Suite struct PlaybackTests {
    @Test func pixelTolerance() {
        #expect(PixelMath.matches(0x102030, 0x102030, tolerance: 0))
        #expect(PixelMath.matches(0x102030, 0x152535, tolerance: 5))
        #expect(!PixelMath.matches(0x102030, 0x162535, tolerance: 5))
    }

    @Test func eventFactoryBuildsTaggedEvents() throws {
        let factory = EventFactory()
        let down = try #require(factory.make(.mouseDown(button: .right, x: 10, y: 20, clickCount: 2)))
        #expect(down.type == .rightMouseDown)
        #expect(down.location == CGPoint(x: 10, y: 20))
        #expect(down.getIntegerValueField(.mouseEventClickState) == 2)
        #expect(down.getIntegerValueField(.eventSourceUserData) == macrecordEventTag)

        let flags = try #require(factory.make(.flagsChanged(keyCode: 56, flags: ModifierFlags.shift.rawValue)))
        #expect(flags.type == .flagsChanged)
        #expect(flags.flags.contains(.maskShift))

        let back = try #require(factory.make(.mouseUp(button: .back, x: 0, y: 0, clickCount: 1)))
        #expect(back.type == .otherMouseUp)
        #expect(back.getIntegerValueField(.mouseEventButtonNumber) == 3)

        let scroll = try #require(factory.make(.scroll(dx: 2, dy: -7, continuous: true)))
        #expect(scroll.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -7)
        #expect(factory.make(.activateApp(bundleID: "x")) == nil)
        #expect(factory.make(.delay) == nil)
    }

    @Test func prepareAppliesSpeed() {
        let player = MacroPlayer()
        let step = player.prepare(MacroEvent(delayNs: 10_000_000, kind: .keyDown(keyCode: 1, flags: 0)), speed: 2)
        #expect(mr_ticks_to_ns(step.delayTicks).distance(to: 5_000_000).magnitude < 100)
    }

    @Test func timeHelpersRoundTrip() {
        #expect(mr_ticks_to_ns(mr_ns_to_ticks(1_000_000_000)).distance(to: 1_000_000_000).magnitude < 100)
    }

    /// Precision is measured by `macrecord-bench jitter` on a real-time thread; here only correctness.
    @Test func waitUntilNeverWakesEarly() {
        for spin: UInt64 in [0, 200_000] {
            let deadline = mr_now_ticks() + mr_ns_to_ticks(2_000_000)
            #expect(mr_wait_until(deadline, spin) >= deadline)
        }
    }

    /// Uses the sink, so no real click is posted (only the no-op warm-up event).
    @Test func autoClickerDeliversThroughSink() throws {
        final class Sink: @unchecked Sendable {
            let lock = NSLock()
            var events: [(CGEventType, CGPoint, Int64)] = []
        }
        let sink = Sink()
        let done = DispatchSemaphore(value: 0)
        let clicker = AutoClicker()
        clicker.post = { event in
            sink.lock.lock()
            sink.events.append((event.type, event.location, event.getIntegerValueField(.mouseEventButtonNumber)))
            sink.lock.unlock()
        }
        clicker.onFinish = { done.signal() }
        clicker.start(AutoClickConfig(clicksPerSecond: 1000, button: .right, target: .fixed(x: 5, y: 7),
                                      limit: .clicks(3)))
        #expect(done.wait(timeout: .now() + 2) == .success)
        sink.lock.lock(); defer { sink.lock.unlock() }
        #expect(sink.events.map(\.0) == [.rightMouseDown, .rightMouseUp, .rightMouseDown, .rightMouseUp,
                                          .rightMouseDown, .rightMouseUp])
        #expect(sink.events.allSatisfy { $0.1 == CGPoint(x: 5, y: 7) && $0.2 == 1 })
        #expect(clicker.clickCount == 3)
    }

    @Test func appDeliveryAddressesTheWindow() throws {
        let event = try #require(EventFactory().mouse(.leftMouseDown, at: .zero, button: .left))
        AutoClicker.address(event, toWindow: 4242)
        #expect(event.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 4242)
        #expect(event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) == 4242)
    }
}

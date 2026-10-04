import Testing
import Permissions
@testable import Capture

/// Listen-only: these tests never post events. Skipped where the tap can't be created (e.g. CI).
@Suite struct CaptureTests {
    @Test(.enabled(if: Permissions.inputMonitoringGranted))
    func immediateStopNeverHangs() throws {
        let recorder = EventRecorder(options: .init(storeEvents: false))
        for _ in 0..<25 {
            try recorder.start()
            #expect(recorder.isRecording)
            recorder.stop()
            #expect(!recorder.isRecording)
        }
    }
}

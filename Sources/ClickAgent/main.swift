// macrecord-clickd: the autoclicker as a separate, UI-free process. Launched by macrecord with pipes on
// stdin/stdout (newline-delimited JSON, see AgentProtocol.swift); never opens a network connection.
// It stops clicking and exits as soon as stdin closes or the parent process dies, so it can never outlive the app.
import AppKit
import ClickService
import Darwin
import Foundation
import Permissions

setvbuf(stdout, nil, _IONBF, 0)
// A window-server connection keeps NSWorkspace's frontmost app and activation notifications current;
// `.prohibited` means no Dock icon, menu bar or windows.
NSApplication.shared.setActivationPolicy(.prohibited)
signal(SIGPIPE, SIG_IGN)

let output = FileHandle.standardOutput
func emit(_ event: ClickServiceEvent) {
    try? output.write(contentsOf: AgentWire.encode(event))
}

let service = ClickService()
service.onEvent = emit

func quit() -> Never {
    service.shutdown()
    exit(0)
}

// Same process tree as the app, so macOS attributes its taps and posted events to macrecord's own grants.
emit(.ready(accessibility: Permissions.accessibilityGranted, postEvents: Permissions.postEventsGranted))

let parent = getppid()
let parentWatch = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
parentWatch.setEventHandler { quit() }
parentWatch.resume()
if getppid() != parent || getppid() == 1 { quit() }

Thread.detachNewThread {
    var buffer = Data()
    while true {
        let chunk = FileHandle.standardInput.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        let commands = AgentWire.decodeLines(AgentCommand.self, from: &buffer)
        DispatchQueue.main.async {
            for command in commands {
                switch command {
                case let .apply(settings): service.apply(settings)
                case let .start(trigger): service.start(trigger)
                case .stop: service.stop()
                }
            }
        }
    }
    DispatchQueue.main.async { quit() }
}

// A run loop on the main thread serves timers and workspace notifications.
RunLoop.main.run()

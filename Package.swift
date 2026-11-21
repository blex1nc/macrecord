// swift-tools-version:6.0
import PackageDescription

// Engine targets run on real-time / event-tap threads and use C callbacks;
// they stay in Swift 5 language mode. Pure data (MacroCore) and tests use Swift 6.
let engine: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "macrecord",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macrecord", targets: ["MacrecordApp"]),
        .executable(name: "macrecord-bench", targets: ["Bench"]),
        .executable(name: "macrecord-clickd", targets: ["ClickAgent"]),
        .library(name: "MacroKit", targets: ["MacroCore", "Capture", "Playback", "Scripting", "Hotkeys", "Permissions"]),
    ],
    targets: [
        .target(name: "CSupport"),
        .target(name: "MacroCore"),
        .target(name: "Permissions", swiftSettings: engine),
        .target(name: "Capture", dependencies: ["MacroCore", "CSupport"], swiftSettings: engine),
        .target(name: "Playback", dependencies: ["MacroCore", "CSupport"], swiftSettings: engine),
        .target(name: "Scripting", dependencies: ["MacroCore", "Playback", "CSupport"], swiftSettings: engine),
        .target(name: "Hotkeys", dependencies: ["MacroCore"], swiftSettings: engine),
        .target(name: "ClickService", dependencies: ["MacroCore", "Playback", "Hotkeys", "CSupport"], swiftSettings: engine),
        .executableTarget(name: "ClickAgent", dependencies: ["ClickService", "Permissions"], swiftSettings: engine),
        .executableTarget(name: "Bench", dependencies: ["MacroCore", "Capture", "Playback", "Permissions", "CSupport"], swiftSettings: engine),
        .executableTarget(
            name: "MacrecordApp",
            dependencies: ["MacroCore", "Capture", "Playback", "Scripting", "Hotkeys", "Permissions", "ClickService"],
            swiftSettings: engine
        ),
        .testTarget(name: "MacroCoreTests", dependencies: ["MacroCore"]),
        .testTarget(name: "CaptureTests", dependencies: ["Capture", "Permissions"], swiftSettings: engine),
        .testTarget(name: "ScriptingTests", dependencies: ["Scripting", "MacroCore"], swiftSettings: engine),
        .testTarget(name: "PlaybackTests", dependencies: ["Playback", "MacroCore", "CSupport"], swiftSettings: engine),
        .testTarget(name: "ClickServiceTests", dependencies: ["ClickService", "MacroCore", "Hotkeys"], swiftSettings: engine),
    ]
)

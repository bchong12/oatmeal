// swift-tools-version:6.2
// Lurker's recorder and editing engine, copied into Oatmeal from Lurker 1.0 (f801092) so captures can be
// recorded with zooms, a frame and your camera. Changes for Oatmeal: the recorder also records the mic,
// and the engine draws a camera bubble from a take's camera.mov.
import PackageDescription

let v6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Lurker",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LurkerCore", targets: ["LurkerCore"]),
        .library(name: "LurkerCapture", targets: ["LurkerCapture"]),
        .library(name: "LurkerEngine", targets: ["LurkerEngine"]),
    ],
    targets: [
        // Project document, ops, undo, time map. Pure Swift.
        .target(name: "LurkerCore", path: "Sources/LurkerCore", swiftSettings: v6),
        // Recording: ScreenCaptureKit, mic, input log, crash-safe writers, all on the host clock.
        .target(name: "LurkerCapture", dependencies: ["LurkerCore"], path: "Sources/LurkerCapture", swiftSettings: v6),
        // Rendering: frame(t) compositor on Metal, audio timeline, export presets.
        .target(name: "LurkerEngine", dependencies: ["LurkerCore"], path: "Sources/LurkerEngine", swiftSettings: v6),
    ]
)

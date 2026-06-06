// swift-tools-version:6.0
import PackageDescription

// Lumen — a native macOS SwiftUI player embedding libmpv in-process.
//
// Build is CLT-only (no Xcode): `swift build` / `swift run`.
//
// Load-bearing flags (verified during design):
//  - The rpath MUST be routed through the linker with the -Xlinker form;
//    a bare ["-rpath", "@executable_path/../Frameworks"] fails to link with
//    "error: unknown argument: '-rpath'".
//  - libmpv headers/lib come from Homebrew (/opt/homebrew). -Xcc -I makes the
//    Clang module importer find <mpv/*.h> when compiling the Cmpv module map.
//  - GL_SILENCE_DEPRECATION: OpenGL/CGL/CAOpenGLLayer are deprecated-but-functional
//    and are the only embeddable HDR-capable render path libmpv exposes today.
let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "Cmpv",
            path: "Sources/Cmpv"
        ),
        .executableTarget(
            name: "Lumen",
            dependencies: ["Cmpv"],
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I/opt/homebrew/include", "-I", "/opt/homebrew/include"]),
                .define("GL_SILENCE_DEPRECATION"),
                // Interop + threading code; tighten to Swift 6 concurrency later.
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "/opt/homebrew/lib",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
    ]
)

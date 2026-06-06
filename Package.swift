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
    // Floor is dictated by the bundled libmpv (built for macOS 26) and enables
    // the Liquid Glass UI.
    platforms: [.macOS("26.0")],
    targets: [
        .systemLibrary(
            name: "Cmpv",
            path: "Sources/Cmpv"
        ),
        .executableTarget(
            name: "Lumen",
            dependencies: ["Cmpv"],
            resources: [
                .copy("Resources/subdl.py"),
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icns"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xcc", "-I/opt/homebrew/include",
                    "-I", "/opt/homebrew/include",
                    // Silence OpenGL/CGL C-API deprecation warnings (OpenGL is the
                    // only HDR-capable embeddable render path libmpv exposes).
                    "-Xcc", "-DGL_SILENCE_DEPRECATION",
                ]),
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

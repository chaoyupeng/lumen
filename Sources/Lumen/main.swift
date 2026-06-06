// Toolchain spike (M1, step 1): prove libmpv links and loads CLT-only.
//
// Success criteria:
//  - `swift build && swift run` links against /opt/homebrew/lib/libmpv.dylib
//    with no pkg-config.
//  - Prints the libmpv client API version (expected 131077 == 2.5 on this box).
//  - mpv_create() returns a non-nil handle; mpv_terminate_destroy() cleans up.
//
// This is intentionally headless. GUI/render code arrives once this holds.

import Cmpv
import Foundation

let version = mpv_client_api_version()
let major = (version >> 16) & 0xFFFF
let minor = version & 0xFFFF
print("libmpv client API version: \(version)  (\(major).\(minor))")

guard let mpv = mpv_create() else {
    FileHandle.standardError.write(Data("FAIL: mpv_create() returned nil\n".utf8))
    exit(1)
}
print("mpv_create(): OK (handle is non-nil)")

mpv_terminate_destroy(mpv)
print("mpv_terminate_destroy(): OK")
print("Toolchain spike PASSED — embed link works CLT-only.")

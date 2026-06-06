import AppKit

/// Ensures the SwiftPM-built executable behaves as a real GUI app: regular
/// activation policy (Dock icon, key focus) and clean shutdown.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var player: PlayerCore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        player?.shutdown()
    }
}

import AppKit

/// Ensures the SwiftPM-built executable behaves as a real GUI app: regular
/// activation policy (Dock icon, key focus) and clean shutdown.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var player: PlayerCore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Dock icon (also works in `swift run`, where there's no app bundle).
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        // Silent check on launch (unless disabled in Settings).
        if UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true {
            UpdateChecker.check(userInitiated: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        player?.shutdown()
    }
}

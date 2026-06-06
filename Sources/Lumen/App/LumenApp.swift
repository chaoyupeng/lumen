import SwiftUI

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerCore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .onAppear { appDelegate.player = player }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 540)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { player.openFileDialog() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateChecker.check(userInitiated: true) }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

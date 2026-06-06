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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { player.openFileDialog() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

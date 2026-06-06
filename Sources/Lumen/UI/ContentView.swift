import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerCore

    var body: some View {
        ZStack {
            Color.black
            VideoView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !player.fileLoaded {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.secondary)
                    Text("Open a video to begin")
                        .foregroundStyle(.secondary)
                    Button("Open…") { player.openFileDialog() }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .ignoresSafeArea()
    }
}

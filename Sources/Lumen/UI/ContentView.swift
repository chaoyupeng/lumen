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

            // HDR status badge (top-right). Only shown when EDR is engaged.
            if player.fileLoaded, !player.colorInfo.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        Text(player.isHDRActive ? "HDR" : player.colorInfo)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(player.isHDRActive ? Color.orange.opacity(0.9) : Color.gray.opacity(0.6),
                                        in: Capsule())
                            .foregroundStyle(.white)
                            .help(player.colorInfo)
                            .padding(12)
                    }
                    Spacer()
                }
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .ignoresSafeArea()
    }
}

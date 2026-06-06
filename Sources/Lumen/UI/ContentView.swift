import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerCore
    @State private var controlsVisible = true
    @State private var hideTask: DispatchWorkItem?

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

            // HDR status badge (top-right).
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
                .opacity(controlsVisible ? 1 : 0)
            }

            // Transport controls (bottom), auto-hiding on mouse idle.
            if player.fileLoaded {
                VStack {
                    Spacer()
                    ControlsBar()
                        .environmentObject(player)
                }
                .opacity(controlsVisible ? 1 : 0)
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                showControls()
            case .ended:
                break
            }
        }
    }

    private func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        let task = DispatchWorkItem {
            if player.fileLoaded { controlsVisible = false }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var player: PlayerCore
    @State private var controlsVisible = true
    @State private var hideTask: DispatchWorkItem?
    @State private var subtitlesOpen = false
    @State private var dropTargeted = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            if !player.fileLoaded { emptyState }

            if player.fileLoaded, !player.colorInfo.isEmpty {
                hdrBadge.opacity(controlsVisible ? 1 : 0)
            }

            if player.fileLoaded {
                VStack {
                    Spacer()
                    ControlsBar(showSubtitles: $subtitlesOpen).environmentObject(player)
                }
                .opacity(controlsVisible ? 1 : 0)
            }

            if dropTargeted { dropOverlay }
        }
        .frame(minWidth: 720, minHeight: 405)
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .animation(.easeInOut(duration: 0.15), value: dropTargeted)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .onContinuousHover { phase in
            if case .active = phase { showControls() }
        }
        .onChange(of: subtitlesOpen) { _, open in
            if open { controlsVisible = true; hideTask?.cancel() } else { showControls() }
        }
        // Lift subtitles above the controls whenever the bar is visible.
        .onChange(of: controlsVisible) { _, visible in
            player.setSubtitlesRaised(visible, windowHeight: contentHeight)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { player.open(url: url) }
            }
            return true
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Lumen").font(.largeTitle.weight(.semibold))
                Text("Drop a video here, or open one to start")
                    .foregroundStyle(.secondary)
            }
            Button {
                player.openFileDialog()
            } label: {
                Label("Open Video…", systemImage: "folder")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(40)
    }

    // MARK: - HDR badge

    private var hdrBadge: some View {
        VStack {
            HStack {
                Spacer()
                Text(player.isHDRActive ? "HDR" : player.colorInfo)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassEffect(player.isHDRActive ? .regular.tint(.orange) : .regular,
                                 in: Capsule())
                    .help(player.colorInfo)
                    .padding(16)
            }
            Spacer()
        }
    }

    // MARK: - Drop overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 24)
            .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [10]))
            .background(Color.black.opacity(0.25))
            .overlay {
                Label("Drop to play", systemImage: "arrow.down.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(24)
            .allowsHitTesting(false)
    }

    // MARK: - Auto-hide

    private func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        let task = DispatchWorkItem {
            if player.fileLoaded, !subtitlesOpen { controlsVisible = false }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }
}

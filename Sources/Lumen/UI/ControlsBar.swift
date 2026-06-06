import SwiftUI

/// Format seconds as H:MM:SS or M:SS.
func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// Floating Liquid-Glass transport bar: play/pause, scrubber, time, subtitles,
/// volume, fullscreen.
struct ControlsBar: View {
    @EnvironmentObject var player: PlayerCore
    @Binding var showSubtitles: Bool
    @Binding var scrubbing: Bool
    @State private var sliderValue = 0.0
    @State private var lastPreviewSeek = Date.distantPast

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 14) {
                iconButton(player.isPaused ? "play.fill" : "pause.fill",
                           size: 17, action: player.togglePause)

                Text(timeString(player.timePos))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))

                scrubber

                Text(timeString(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))

                iconButton("captions.bubble", isActive: showSubtitles) { showSubtitles.toggle() }
                    .popover(isPresented: $showSubtitles, arrowEdge: .bottom) {
                        SubtitlesPanel().environmentObject(player)
                    }

                volume

                iconButton("arrow.up.left.and.arrow.down.right") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }

    private var scrubber: some View {
        // The slider owns `sliderValue` while dragging; otherwise it tracks
        // playback. This decoupling prevents the thumb from fighting the live
        // time-pos updates (which caused the jumping).
        Slider(value: $sliderValue, in: 0...1) { editing in
            scrubbing = editing
            if !editing { player.seek(toFraction: sliderValue, exact: true) }
        }
        .controlSize(.small)
        .tint(.white)
        .frame(minWidth: 160)
        .onChange(of: sliderValue) { _, value in
            // Live frame preview while dragging (fast keyframe seeks, throttled).
            guard scrubbing else { return }
            let now = Date()
            if now.timeIntervalSince(lastPreviewSeek) > 0.05 {
                lastPreviewSeek = now
                player.seek(toFraction: value, exact: false)
            }
        }
        .onChange(of: player.timePos) { _, _ in syncSlider() }
        .onChange(of: player.duration) { _, _ in syncSlider() }
    }

    private func syncSlider() {
        guard !scrubbing, player.duration > 0 else { return }
        sliderValue = player.timePos / player.duration
    }

    private var volume: some View {
        HStack(spacing: 6) {
            Image(systemName: player.volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 16)
            Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...130)
                .controlSize(.small)
                .tint(.white)
                .frame(width: 74)
        }
    }

    private func iconButton(_ symbol: String, size: CGFloat = 15, isActive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

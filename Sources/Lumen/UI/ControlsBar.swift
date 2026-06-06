import SwiftUI

/// Format seconds as H:MM:SS or M:SS.
func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

/// Bottom transport bar: play/pause, scrubber, time, subtitles, volume, fullscreen.
struct ControlsBar: View {
    @EnvironmentObject var player: PlayerCore
    @State private var showSubtitles = false
    @State private var scrubbing = false
    @State private var scrubFraction = 0.0

    private var progress: Double {
        if scrubbing { return scrubFraction }
        return player.duration > 0 ? player.timePos / player.duration : 0
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: player.togglePause) {
                Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 18)
            }
            .keyboardShortcut(.space, modifiers: [])

            Text(timeString(player.timePos))
                .font(.caption).monospacedDigit()
                .foregroundStyle(.white)

            Slider(
                value: Binding(get: { progress }, set: { scrubFraction = $0; scrubbing = true }),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(toFraction: scrubFraction)
                        scrubbing = false
                    }
                }
            )

            Text(timeString(player.duration))
                .font(.caption).monospacedDigit()
                .foregroundStyle(.white)

            Button { showSubtitles.toggle() } label: {
                Image(systemName: "captions.bubble")
            }
            .popover(isPresented: $showSubtitles, arrowEdge: .bottom) {
                SubtitlesPanel().environmentObject(player)
            }

            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill").font(.caption)
                Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }),
                       in: 0...130)
                    .frame(width: 70)
            }

            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

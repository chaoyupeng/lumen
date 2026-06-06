import SwiftUI

/// Popover for audio + subtitle track selection, external subtitle files,
/// key-free internet download, and subtitle delay.
struct SubtitlesPanel: View {
    @EnvironmentObject var player: PlayerCore

    private var anySubtitleSelected: Bool {
        player.subtitleTracks.contains { $0.selected }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                audioSection
                Divider()
                subtitleSection
                Divider()
                downloadSection
                Divider()
                delaySection
            }
            .padding(16)
        }
        .frame(width: 320)
        .frame(maxHeight: 520)
    }

    // MARK: - Audio

    @ViewBuilder
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Audio").font(.headline)
            if player.audioTracks.isEmpty {
                Text("No audio tracks").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(player.audioTracks) { track in
                row(label: track.displayName, checked: track.selected) {
                    player.selectAudio(id: track.id)
                }
            }
        }
    }

    // MARK: - Subtitles

    @ViewBuilder
    private var subtitleSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Subtitles").font(.headline)
            row(label: "Off", checked: !anySubtitleSelected) {
                player.selectSubtitle(id: nil)
            }
            ForEach(player.subtitleTracks) { track in
                row(label: track.displayName, checked: track.selected) {
                    player.selectSubtitle(id: track.id)
                }
            }
            Button {
                player.openSubtitleFileDialog()
            } label: {
                Label("Add Subtitle File…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            HStack(spacing: 8) {
                Button {
                    player.syncCurrentSubtitle()
                } label: {
                    Label("Auto-sync to audio", systemImage: "wand.and.stars")
                }
                .buttonStyle(.plain)
                .disabled(player.isSyncing)
                if player.isSyncing { ProgressView().controlSize(.small) }
            }
            if !player.subtitleSyncAvailable {
                Text("Auto-sync needs alass: brew install alass")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Download

    @ViewBuilder
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Download Subtitles").font(.headline)
            if !player.subtitleDownloadAvailable {
                Text("Requires subliminal:").font(.caption).foregroundStyle(.secondary)
                Text("brew install subliminal")
                    .font(.caption.monospaced()).textSelection(.enabled)
            } else {
                HStack(spacing: 8) {
                    Button {
                        player.downloadSubtitles(languages: player.subtitleLanguages)
                    } label: {
                        Label("Download English Subtitles", systemImage: "arrow.down.circle")
                    }
                    .disabled(player.isDownloadingSubs)
                    if player.isDownloadingSubs {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                if let status = player.subStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Delay

    @ViewBuilder
    private var delaySection: some View {
        HStack {
            Text("Subtitle delay").font(.caption)
            Spacer()
            Button { player.setSubDelay(player.subDelay - 0.1) } label: { Image(systemName: "minus") }
            Text(String(format: "%+.1f s", player.subDelay))
                .font(.caption).monospacedDigit().frame(width: 52)
            Button { player.setSubDelay(player.subDelay + 0.1) } label: { Image(systemName: "plus") }
            Button("0") { player.setSubDelay(0) }.font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row(label: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "checkmark").opacity(checked ? 1 : 0).frame(width: 14)
                Text(label).lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

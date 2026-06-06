import SwiftUI

/// Popover for audio + subtitle track selection, external subtitle files, and
/// key-free internet download (subtitles auto-sync to the audio after download).
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
            }
            .padding(16)
        }
        .frame(width: 320)
        .frame(maxHeight: 480)
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
            HStack(spacing: 8) {
                Button {
                    player.openSubtitleFileDialog()
                } label: {
                    Label("Add File…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                if player.isSyncing {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("Syncing…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 2)
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
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
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

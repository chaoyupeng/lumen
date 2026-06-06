import SwiftUI

/// Popover for subtitle track selection, loading external files, delay, and
/// key-free internet download.
struct SubtitlesPanel: View {
    @EnvironmentObject var player: PlayerCore
    @PersistedLanguages private var languages
    @State private var showDownload = false

    private var anySubtitleSelected: Bool {
        player.subtitleTracks.contains { $0.selected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitles").font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                row(label: "Off", checked: !anySubtitleSelected) {
                    player.selectSubtitle(id: nil)
                }
                ForEach(player.subtitleTracks) { track in
                    row(label: track.displayName, checked: track.selected) {
                        player.selectSubtitle(id: track.id)
                    }
                }
                if player.subtitleTracks.isEmpty {
                    Text("No subtitle tracks")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }
            }

            Divider()

            Button {
                player.openSubtitleFileDialog()
            } label: {
                Label("Add Subtitle File…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.plain)

            // Internet download (key-free).
            DisclosureGroup(isExpanded: $showDownload) {
                downloadSection
            } label: {
                Label("Download Subtitles…", systemImage: "arrow.down.circle")
            }

            Divider()

            HStack {
                Text("Delay").font(.caption)
                Spacer()
                Button { player.setSubDelay(player.subDelay - 0.1) } label: {
                    Image(systemName: "minus")
                }
                Text(String(format: "%+.1f s", player.subDelay))
                    .font(.caption).monospacedDigit()
                    .frame(width: 52)
                Button { player.setSubDelay(player.subDelay + 0.1) } label: {
                    Image(systemName: "plus")
                }
                Button("0") { player.setSubDelay(0) }
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder
    private var downloadSection: some View {
        if !player.subtitleDownloadAvailable {
            VStack(alignment: .leading, spacing: 4) {
                Text("Requires subliminal").font(.caption).foregroundStyle(.secondary)
                Text("brew install subliminal")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Languages").font(.caption).foregroundStyle(.secondary)
                LanguagePicker(selected: $languages)
                HStack {
                    Button {
                        player.downloadSubtitles(languages: Array(languages))
                    } label: {
                        if player.isDownloadingSubs {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Download")
                        }
                    }
                    .disabled(player.isDownloadingSubs || languages.isEmpty)
                    Spacer()
                }
                if let status = player.subStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func row(label: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "checkmark")
                    .opacity(checked ? 1 : 0)
                    .frame(width: 14)
                Text(label).lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

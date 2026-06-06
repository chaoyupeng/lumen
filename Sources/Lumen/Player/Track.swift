import Foundation

/// A single media track (subtitle, audio, or video) as reported by mpv's
/// track-list.
struct Track: Identifiable, Hashable {
    let id: Int64        // mpv track id (1-based within its type)
    let type: String     // "sub", "audio", "video"
    let title: String?
    let lang: String?
    let external: Bool
    var selected: Bool

    var displayName: String {
        var parts: [String] = []
        if let lang, !lang.isEmpty { parts.append(lang.uppercased()) }
        if let title, !title.isEmpty { parts.append(title) }
        if parts.isEmpty { parts.append("Track \(id)") }
        if external { parts.append("(external)") }
        return parts.joined(separator: " · ")
    }
}

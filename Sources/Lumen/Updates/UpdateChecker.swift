import AppKit
import Foundation

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, prerelease, assets
    }
}

/// Lightweight "Check for Updates" against GitHub Releases — no Sparkle, no
/// signing infrastructure. Compares the latest release tag to the app version.
enum UpdateChecker {
    static let repo = "chaoyupeng/lumen"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check for a newer release. When `userInitiated`, always reports the
    /// result (including "up to date" and errors); otherwise it's silent unless
    /// a newer version is found, so a launch check never interrupts.
    @MainActor
    static func check(userInitiated: Bool) {
        Task { @MainActor in
            do {
                let release = try await fetchLatest()
                let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                if currentVersion.compare(latest, options: .numeric) == .orderedAscending {
                    presentUpdate(release: release, latest: latest)
                } else if userInitiated {
                    presentUpToDate()
                }
            } catch {
                if userInitiated { presentError(error) }
            }
        }
    }

    private static func fetchLatest() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Lumen.Update", code: code,
                          userInfo: [NSLocalizedDescriptionKey:
                            code == 404 ? "No published releases yet." : "Update check failed (HTTP \(code))."])
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @MainActor
    private static func presentUpdate(release: GitHubRelease, latest: String) {
        let alert = NSAlert()
        alert.messageText = "Lumen \(latest) is available"
        alert.informativeText = (release.body?.isEmpty == false) ? release.body! : "A new version is available."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Remind Me Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        let target = dmg?.browserDownloadURL ?? release.htmlURL
        if let url = URL(string: target) { NSWorkspace.shared.open(url) }
    }

    @MainActor
    private static func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Lumen \(currentVersion) is the latest version."
        alert.runModal()
    }

    @MainActor
    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

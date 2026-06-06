import SwiftUI

/// App preferences. The OpenSubtitles.com account is needed to *download*
/// subtitles: the old free OpenSubtitles.org API shut down in Jan 2026, and the
/// REST API serves files only to logged-in users. A free account works.
///
/// Note: credentials are stored in UserDefaults for now; this should move to the
/// Keychain once the app ships code-signed (see M7).
struct SettingsView: View {
    @AppStorage("osUsername") private var username = ""
    @AppStorage("osPassword") private var password = ""
    @AppStorage("osApiKey") private var apiKey = ""

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                TextField("API key (optional)", text: $apiKey)
            } header: {
                Text("OpenSubtitles.com Account")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required to download subtitles. A free account is enough.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Create a free account →", destination: URL(string: "https://www.opensubtitles.com/newuser")!)
                        .font(.caption)
                    Text("The API key is optional — a built-in key is used for searching. Leave it blank unless you have your own.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
    }
}

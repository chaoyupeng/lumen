import SwiftUI

/// App preferences. The OpenSubtitles.com account is needed to *download*
/// subtitles: the old free OpenSubtitles.org API shut down in Jan 2026, and the
/// REST API serves files only to logged-in users. A free account works.
///
/// Note: credentials are stored in UserDefaults for now; this should move to the
/// Keychain once the app ships code-signed (see M7).
struct SettingsView: View {
    @State private var username = UserDefaults.standard.string(forKey: "osUsername") ?? ""
    @State private var password = UserDefaults.standard.string(forKey: "osPassword") ?? ""
    @State private var apiKey = UserDefaults.standard.string(forKey: "osApiKey") ?? ""
    @AppStorage("autoSubtitles") private var autoSubtitles = true

    @State private var verifying = false
    @State private var status: SubtitleService.VerifyResult?

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                TextField("API key (optional)", text: $apiKey)

                HStack(spacing: 8) {
                    Button(verifying ? "Verifying…" : "Save & Verify") { saveAndVerify() }
                        .disabled(verifying || username.isEmpty || password.isEmpty)
                    if verifying { ProgressView().controlSize(.small) }
                    statusView
                    Spacer()
                }
                Link("Create a free account →",
                     destination: URL(string: "https://www.opensubtitles.com/newuser")!)
                    .font(.caption)
            } header: {
                Text("OpenSubtitles.com Account")
            } footer: {
                Text("Required to download subtitles. A free account is enough. The API key is optional — a built-in key is used for searching.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Automatically load or download subtitles", isOn: $autoSubtitles)
            } header: {
                Text("Subtitles")
            } footer: {
                Text("On open: use the video's embedded subtitles if present, otherwise download them in your chosen languages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 340)
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .success:
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red).font(.caption).lineLimit(2)
        case nil:
            EmptyView()
        }
    }

    private func saveAndVerify() {
        UserDefaults.standard.set(username, forKey: "osUsername")
        UserDefaults.standard.set(password, forKey: "osPassword")
        UserDefaults.standard.set(apiKey, forKey: "osApiKey")
        verifying = true
        status = nil
        Task {
            let result = await SubtitleService.verifyAccount(username: username,
                                                             password: password,
                                                             apiKey: apiKey)
            verifying = false
            status = result
        }
    }
}

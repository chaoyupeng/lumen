import SwiftUI

struct SubtitleLanguage: Identifiable, Hashable {
    let code: String   // IETF tag passed to subliminal
    let name: String
    var id: String { code }
}

/// Common subtitle languages (IETF tags babelfish understands).
let subtitleLanguages: [SubtitleLanguage] = [
    .init(code: "en", name: "English"),
    .init(code: "es", name: "Spanish"),
    .init(code: "fr", name: "French"),
    .init(code: "de", name: "German"),
    .init(code: "it", name: "Italian"),
    .init(code: "pt", name: "Portuguese"),
    .init(code: "pt-BR", name: "Portuguese (Brazil)"),
    .init(code: "nl", name: "Dutch"),
    .init(code: "ru", name: "Russian"),
    .init(code: "pl", name: "Polish"),
    .init(code: "tr", name: "Turkish"),
    .init(code: "sv", name: "Swedish"),
    .init(code: "uk", name: "Ukrainian"),
    .init(code: "zh-Hans", name: "Chinese (Simplified)"),
    .init(code: "zh-Hant", name: "Chinese (Traditional)"),
    .init(code: "ja", name: "Japanese"),
    .init(code: "ko", name: "Korean"),
    .init(code: "ar", name: "Arabic"),
    .init(code: "vi", name: "Vietnamese"),
    .init(code: "cs", name: "Czech"),
    .init(code: "el", name: "Greek"),
    .init(code: "he", name: "Hebrew"),
    .init(code: "hi", name: "Hindi"),
    .init(code: "id", name: "Indonesian"),
    .init(code: "ro", name: "Romanian"),
    .init(code: "hu", name: "Hungarian"),
    .init(code: "fi", name: "Finnish"),
    .init(code: "da", name: "Danish"),
    .init(code: "nb", name: "Norwegian"),
    .init(code: "th", name: "Thai"),
]

/// Multi-select language list with the selection persisted in UserDefaults.
struct LanguagePicker: View {
    @Binding var selected: Set<String>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(subtitleLanguages) { lang in
                    Button {
                        if selected.contains(lang.code) { selected.remove(lang.code) }
                        else { selected.insert(lang.code) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(lang.code) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selected.contains(lang.code) ? Color.accentColor : .secondary)
                            Text(lang.name).font(.callout)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 160)
    }
}

/// Persists a Set<String> of language codes as a comma-separated UserDefaults value.
@propertyWrapper
struct PersistedLanguages: DynamicProperty {
    @AppStorage("subtitleLanguages") private var raw: String = "en"

    var wrappedValue: Set<String> {
        get { Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }) }
        nonmutating set { raw = newValue.sorted().joined(separator: ",") }
    }

    var projectedValue: Binding<Set<String>> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

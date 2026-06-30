import SwiftUI
import AVFoundation

/// Lets the user pick which installed voice reads replies aloud, or leave it on
/// automatic (matched to the reply's language). Tapping a voice previews it.
struct VoicePickerView: View {
    @Bindable var store: ChatStore

    private var voices: [AVSpeechSynthesisVoice] { store.availableVoices() }

    /// Group voices by their language for readable sections.
    private var grouped: [(String, [AVSpeechSynthesisVoice])] {
        let dict = Dictionary(grouping: voices) { $0.language }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Button {
                    store.selectedVoiceID = SpeechManager.autoVoiceID
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic")
                            Text("Match the reply's language")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.selectedVoiceID == SpeechManager.autoVoiceID {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }

            ForEach(grouped, id: \.0) { language, list in
                Section(languageName(language)) {
                    ForEach(list, id: \.identifier) { voice in
                        Button {
                            store.selectedVoiceID = voice.identifier
                            store.previewVoice(voice.identifier)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                    if let q = qualityLabel(voice.quality) {
                                        Text(q)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.tint)
                                    }
                                }
                                Spacer()
                                if store.selectedVoiceID == voice.identifier {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String? {
        switch q {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return nil
        }
    }
}

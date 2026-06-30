import SwiftUI
import AVFoundation
import UIKit

/// Picks which installed voice reads replies aloud (or "Automatic"), and points
/// the user to the system Settings to add or remove voices.
///
/// Note: iOS does not let an app download or delete system voices — that is
/// handled only in Settings ▸ Accessibility ▸ Spoken Content ▸ Voices. This
/// screen shows what's installed and links out for the rest.
struct VoicePickerView: View {
    @Bindable var store: ChatStore

    private var voices: [AVSpeechSynthesisVoice] { store.availableVoices() }

    /// Premium and enhanced voices — the best-sounding ones, surfaced at the top.
    private var premiumVoices: [AVSpeechSynthesisVoice] {
        voices
            .filter { $0.quality == .premium || $0.quality == .enhanced }
            .sorted {
                // Premium before enhanced, then by language, then name.
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.name < $1.name
            }
    }

    /// Everything else (default quality), grouped by language for the dropdown.
    private var standardGrouped: [(code: String, name: String, voices: [AVSpeechSynthesisVoice])] {
        let standard = voices.filter { $0.quality != .premium && $0.quality != .enhanced }
        let dict = Dictionary(grouping: standard) { $0.language }
        return dict.keys
            .map { (code: $0, name: languageName($0)) }
            .sorted { $0.name < $1.name }
            .map { (code: $0.code, name: $0.name, voices: dict[$0.code] ?? []) }
    }

    /// The currently selected voice, if a concrete one is chosen (not Automatic).
    private var selectedVoice: AVSpeechSynthesisVoice? {
        guard store.selectedVoiceID != SpeechManager.autoVoiceID else { return nil }
        return voices.first { $0.identifier == store.selectedVoiceID }
    }

    var body: some View {
        List {
            // Currently selected — always visible so the choice is obvious.
            Section {
                if let voice = selectedVoice {
                    voiceRow(voice)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic")
                            Text("Match the reply's language")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            } header: {
                Text("Selected")
            }

            // Automatic option
            Section {
                Button {
                    store.selectedVoiceID = SpeechManager.autoVoiceID
                } label: {
                    row(title: "Automatic",
                        subtitle: "Match the reply's language",
                        selected: store.selectedVoiceID == SpeechManager.autoVoiceID)
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Default")
            }

            // Premium / enhanced voices — pinned to the top.
            if !premiumVoices.isEmpty {
                Section {
                    ForEach(premiumVoices, id: \.identifier) { voice in
                        voiceRow(voice)
                    }
                } header: {
                    Label("Premium voices", systemImage: "sparkles")
                } footer: {
                    Text("Higher-quality enhanced and premium voices installed on this device.")
                }
            }

            // Standard voices — tucked under a collapsible dropdown.
            if !standardGrouped.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(standardGrouped, id: \.code) { group in
                            ForEach(group.voices, id: \.identifier) { voice in
                                voiceRow(voice, languageLabel: group.name)
                            }
                        }
                    } label: {
                        Label("All other voices", systemImage: "waveform")
                    }
                }
            }

            // Add / remove voices — handled by the system
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Manage voices in Settings", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("Voices are downloaded and deleted in Settings ▸ Accessibility ▸ Spoken Content ▸ Voices. New voices appear here automatically — tap one to preview and select it.")
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A selectable voice row: name, quality/language tags, preview + checkmark.
    @ViewBuilder
    private func voiceRow(_ voice: AVSpeechSynthesisVoice,
                          languageLabel: String? = nil) -> some View {
        let isSelected = store.selectedVoiceID == voice.identifier
        Button {
            store.selectedVoiceID = voice.identifier
            store.previewVoice(voice.identifier)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                    HStack(spacing: 6) {
                        if let q = qualityLabel(voice.quality) {
                            Text(q)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                        if let lang = languageLabel {
                            Text(lang)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "play.circle")
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func row(title: String, subtitle: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
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

import SwiftUI

/// Status strip shown during hands-free voice conversation: current phase plus
/// the live transcript of what's being heard.
struct ConversationBanner: View {
    let phase: ChatStore.ConversationPhase
    let transcript: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20))
                .foregroundStyle(.tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative,
                              isActive: phase == .listening || phase == .speaking)
                .symbolEffect(.pulse, isActive: phase == .thinking)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                if phase == .listening && !transcript.isEmpty {
                    Text(transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }

    private var icon: String {
        switch phase {
        case .idle: return "waveform"
        case .listening: return "waveform"
        case .thinking: return "brain.head.profile"
        case .speaking: return "speaker.wave.2.fill"
        }
    }

    private var label: String {
        switch phase {
        case .idle: return "Voice mode"
        case .listening: return transcript.isEmpty ? "Listening…" : "Listening"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        }
    }
}

import SwiftUI

/// Friendly empty state with model-aware suggestions the user can tap to start.
struct EmptyChatView: View {
    let modelName: String
    let systemPrompt: String
    let onPick: (String) -> Void
    @State private var appeared = false

    private var info: ModelInfo? { ModelCatalog.info(for: modelName) }

    private var suggestions: [String] {
        switch info?.kind {
        case .vision:
            return ["Describe the attached photo", "What text is in this image?", "Identify objects in the picture"]
        case .audio:
            return ["Hold the mic and ask a question", "Summarize what I just said"]
        default:
            return ["Explain quantum computing simply", "Write a haiku about the sea", "Draft a polite follow-up email"]
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: info?.kind.iconName ?? "message").font(.system(size: 34))
                .foregroundStyle(DS.onAccent)
                .frame(width: 76, height: 76)
                .background(DS.accentGradient, in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                .shadow(color: DS.accent.opacity(0.35), radius: 20, y: 8)
                .padding(.top, 40)

            VStack(spacing: 6) {
                Text(info?.displayName ?? "Liquid Chat")
                    .font(DS.display(24))
                Text("Everything runs privately on your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !systemPrompt.isEmpty {
                Text(systemPrompt)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 10) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { i, prompt in
                    Button {
                        onPick(prompt)
                    } label: {
                        HStack {
                            Text(prompt)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "sparkles").font(.system(size: 14))
                                .foregroundStyle(DS.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsCard(radius: DS.Radius.m)
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .animation(.snappy(duration: 0.4).delay(0.15 + Double(i) * 0.07),
                               value: appeared)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .frame(maxWidth: 440)
        .onAppear { appeared = true }
    }
}

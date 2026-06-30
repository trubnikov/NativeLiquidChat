import SwiftUI

/// Friendly empty state with model-aware suggestions the user can tap to start.
struct EmptyChatView: View {
    let modelName: String
    let systemPrompt: String
    let onPick: (String) -> Void

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
            Image(systemName: info?.iconName ?? "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
                .padding(.top, 40)

            VStack(spacing: 6) {
                Text(info?.displayName ?? "Liquid Chat")
                    .font(.title3.weight(.semibold))
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
                ForEach(suggestions, id: \.self) { prompt in
                    Button {
                        onPick(prompt)
                    } label: {
                        HStack {
                            Text(prompt)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .frame(maxWidth: 440)
    }
}

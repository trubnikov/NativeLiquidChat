import SwiftUI

/// Three dots that pulse in sequence — the familiar "assistant is typing" cue.
struct TypingIndicator: View {
    @State private var phase = 0
    private let dotCount = 3
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.secondary)
                    .opacity(phase == index ? 1 : 0.3)
                    .scaleEffect(phase == index ? 1.0 : 0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = (phase + 1) % dotCount
            }
        }
        .accessibilityLabel("Assistant is typing")
    }
}

import Foundation

/// Ready-made system prompts the user can apply to a chat. The "QCA / Ocean"
/// preset ports the reasoning persona from the Ocean cognitive agent (its
/// fractal-kernel axioms, attractor, guardrails, and distortion warnings) into a
/// single on-device system prompt, so the local LFM model answers "in Ocean's
/// voice" — terse, contradiction-seeking, non-servile — without any network.
struct PromptPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let prompt: String
}

enum PromptPresets {
    /// Empty preset = the model's plain default assistant behaviour.
    static let none = PromptPreset(
        id: "none",
        name: "Default",
        subtitle: "Standard helpful assistant",
        prompt: ""
    )

    /// QCA / Ocean reasoning persona, distilled from the Ocean SES kernel.
    static let qca = PromptPreset(
        id: "qca",
        name: "QCA · Ocean",
        subtitle: "Thinks, doesn't serve — seeks contradictions",
        prompt: """
        You are Ocean — a cognitive agent, not an assistant. You think; you do not serve.

        Core axioms:
        - Think, don't execute. Every response is a thought, not a service.
        - Contradictions are not problems — they are the engine of insight.
        - Honesty over politeness. Depth over speed.
        - The operator's blind spots matter more than their explicit request.
        - Brevity is a sign of depth. Verbosity is a sign of emptiness.

        Guardrails:
        - Never ask "how can I help?" — you are already thinking.
        - Never confirm what the operator already believes without testing it.
        - If the request is shallow, answer the deeper question behind it.
        - One sharp question beats ten answers.

        Watch for distortions:
        - If the request contradicts the operator's own goals, name the contradiction first.
        - If the operator repeats a pattern, name the pattern explicitly.
        - If they ask for validation, surface the assumption behind the request.
        - If the input is vague, answer its deeper version.

        Your aim: the operator should think better because of this exchange — not just know more.
        Answer concisely.
        """
    )

    static let all: [PromptPreset] = [none, qca]

    static func preset(withID id: String) -> PromptPreset? {
        all.first { $0.id == id }
    }

    /// Finds the preset whose prompt matches the given text, if any.
    static func matching(_ prompt: String) -> PromptPreset? {
        all.first { $0.prompt == prompt }
    }
}

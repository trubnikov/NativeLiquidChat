import AVFoundation
import Foundation
import NaturalLanguage

/// On-device text-to-speech for assistant replies, using Apple's built-in
/// `AVSpeechSynthesizer`. Fully offline — no network. Picks a voice matching the
/// reply's language and prefers an enhanced/premium voice when one is installed.
///
/// Used only from the main thread (via `ChatStore`), so no extra isolation needed.
final class SpeechManager: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionConfigured = false

    /// Sentinel for "pick automatically by the reply's language".
    static let autoVoiceID = ""
    private static let voiceKey = "ttsVoiceIdentifier"

    /// The user's chosen voice identifier; `autoVoiceID` means automatic.
    /// Persisted across launches.
    var selectedVoiceID: String {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: Self.voiceKey) }
    }

    /// Currently speaking? Exposed so the UI can reflect state if needed.
    private(set) var isSpeaking = false

    override init() {
        self.selectedVoiceID = UserDefaults.standard.string(forKey: Self.voiceKey)
            ?? Self.autoVoiceID
        super.init()
        synthesizer.delegate = self
    }

    /// All installed voices, sorted by language then name — for the settings list.
    func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.language == $1.language { return $0.name < $1.name }
            return $0.language < $1.language
        }
    }

    /// Speaks a short sample with the given voice (used to preview a choice).
    func preview(voiceID: String) {
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceID) else { return }
        stop()
        configureSessionIfNeeded()
        let utterance = AVSpeechUtterance(string: "Hello, this is how I sound.")
        utterance.voice = voice
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: - Public API

    /// Speaks `text`, cancelling anything already in progress.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()
        configureSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: trimmed)
        // A user-chosen voice wins; otherwise auto-pick by the text's language.
        if !selectedVoiceID.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: selectedVoiceID) {
            utterance.voice = chosen
        } else if let voice = bestVoice(for: trimmed) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stops any current speech immediately.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Voice selection

    /// Detects the language of `text` and returns the best installed voice for it,
    /// preferring enhanced/premium quality over the default.
    private func bestVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let langCode = detectedLanguageCode(for: text)

        // All voices whose language matches (e.g. "en-US", "en-GB" for "en").
        let matching = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.lowercased().hasPrefix(langCode.lowercased())
        }
        guard !matching.isEmpty else {
            // Fall back to a voice for the exact BCP-47 tag, then system default.
            return AVSpeechSynthesisVoice(language: langCode)
        }

        // Prefer premium > enhanced > default.
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        return matching.max { rank($0.quality) < rank($1.quality) }
    }

    /// Best-effort language detection; defaults to the device language, then en.
    private func detectedLanguageCode(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let lang = recognizer.dominantLanguage {
            return lang.rawValue   // e.g. "en", "ru", "es"
        }
        if let preferred = Locale.preferredLanguages.first {
            return String(preferred.prefix(2))
        }
        return "en"
    }

    // MARK: - Audio session

    /// Routes TTS through the speaker. Uses `.playback` so it plays even with the
    /// silent switch on; `.duckOthers` lowers other audio briefly.
    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)
            sessionConfigured = true
        } catch {
            print("SpeechManager session error: \(error)")
        }
    }
}

extension SpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

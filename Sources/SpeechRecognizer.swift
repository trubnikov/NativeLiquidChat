import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text for hands-free conversation. Uses Apple's
/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` (no network),
/// and reports when the user has stopped talking (a short trailing silence).
final class SpeechRecognizer {
    enum RecognizerError: Error {
        case notAuthorized
        case notAvailable
        case onDeviceUnavailable
    }

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Fires whenever the partial transcript changes.
    var onPartial: ((String) -> Void)?
    /// Fires once we decide the user finished (final text, possibly empty).
    var onFinished: ((String) -> Void)?

    private var latestTranscript = ""
    private var silenceTimer: Timer?
    private var didFinish = false
    /// How long of a pause counts as "done speaking".
    private let silenceInterval: TimeInterval = 1.6
    /// If nothing is heard at all, give up after this long and report empty.
    private let noSpeechTimeout: TimeInterval = 8.0
    private var noSpeechTimer: Timer?

    init(locale: Locale = Locale.current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Requests mic + speech permission. Calls back on the main thread.
    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            let speechOK = (status == .authorized)
            AVAudioApplication.requestRecordPermission { micOK in
                DispatchQueue.main.async { completion(speechOK && micOK) }
            }
        }
    }

    /// Begins listening. Throws if recognition isn't available or on-device
    /// recognition isn't supported for this locale.
    func start(timeoutEnabled: Bool = true) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw RecognizerError.notAvailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw RecognizerError.onDeviceUnavailable
        }

        // Reset any previous run.
        stop()

        latestTranscript = ""
        didFinish = false

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true   // strictly offline
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty {
                    self.latestTranscript = text
                    DispatchQueue.main.async { self.onPartial?(text) }
                    // Only start counting silence once we've actually heard words.
                    self.resetSilenceTimer()
                }
                if result.isFinal {
                    self.finish()
                }
            }
            if let error {
                // A cancel after we've already finished is expected; ignore it.
                // Otherwise treat as end-of-utterance with whatever we have.
                #if DEBUG
                print("[STT] task error: \(error.localizedDescription)")
                #endif
                self.finish()
            }
        }

        // If the user never says anything, resolve empty after a while so the
        // conversation loop doesn't hang forever.
        if timeoutEnabled {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.noSpeechTimer = Timer.scheduledTimer(
                    withTimeInterval: self.noSpeechTimeout, repeats: false
                ) { [weak self] _ in
                    self?.finish()
                }
            }
        }
    }

    /// Stops listening immediately without emitting a finished transcript.
    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        noSpeechTimer?.invalidate()
        noSpeechTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    // MARK: - Silence detection

    private func resetSilenceTimer() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(
                withTimeInterval: self.silenceInterval, repeats: false
            ) { [weak self] _ in
                self?.finish()
            }
        }
    }

    /// Resolves the turn exactly once: captures the transcript, tears down, and
    /// reports it. Guarded so the silence timer, `isFinal`, and a cancel error
    /// can't all fire it.
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        let text = latestTranscript
        stop()
        DispatchQueue.main.async { self.onFinished?(text) }
    }
}

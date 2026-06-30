import SwiftUI
import LeapSDK
import AVFoundation

@Observable
class ChatStore {
    var sessions: [ChatSession] = []
    var currentSessionId: UUID?
    
    // Model Loading State
    var isModelLoading = false
    var loadedModelName: String?
    var downloadProgress: Double = 0.0
    var isLoadingResponse = false
    var executionStatus: String?

    // Voice/Audio State
    var isRecording = false
    var recordingStatus = "Ready"

    // Text-to-Speech (read assistant replies aloud, fully on-device)
    var speakResponses: Bool {
        didSet {
            UserDefaults.standard.set(speakResponses, forKey: "speakResponses")
            if !speakResponses { speech.stop() }
        }
    }
    private let speech = SpeechManager()
    
    // Chat Stream State & Speed
    var currentAssistantMessage = ""
    var currentAssistantSpeed: Double?
    
    private var modelRunner: (any ModelRunner)?
    private var conversation: (any Conversation)?
    private var generationTask: Task<Void, Never>?
    
    var showingCamera = false
    var attachedImage: UIImage? = nil

    private let playbackManager = AudioPlaybackManager()
    private let recorder = AudioRecorder()
    
    var currentSession: ChatSession? {
        sessions.first(where: { $0.id == currentSessionId })
    }
    
    init() {
        self.speakResponses = UserDefaults.standard.bool(forKey: "speakResponses")
        self.sessions = ChatStorage.loadSessions()
        if self.sessions.isEmpty {
            createSession()
        } else {
            self.currentSessionId = self.sessions.first?.id
        }
        playbackManager.prepareSession()
    }
    
    func createSession(modelName: String = "LFM2.5-1.2B-Instruct", systemPrompt: String = "") {
        let newSession = ChatSession(
            title: "Chat \(sessions.count + 1)",
            modelName: modelName,
            systemPrompt: systemPrompt
        )
        sessions.insert(newSession, at: 0)
        currentSessionId = newSession.id
        save()
    }
    
    func deleteSession(id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        if currentSessionId == id {
            currentSessionId = sessions.first?.id
        }
        if sessions.isEmpty {
            createSession()
        }
        save()
    }
    
    func renameSession(id: UUID, newTitle: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].title = newTitle
            save()
        }
    }
    
    func updateSystemPrompt(id: UUID, systemPrompt: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].systemPrompt = systemPrompt
            save()
            if currentSessionId == id {
                self.conversation = nil
            }
        }
    }
    
    func updateModel(id: UUID, modelName: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].modelName = modelName
            save()
            if currentSessionId == id {
                self.conversation = nil
            }
        }
    }
    
    private func save() {
        ChatStorage.saveSessions(sessions)
    }
    
    // MARK: - Model Loading

    /// Loads the requested model via the high-level `Leap.shared.load` API, which
    /// resolves and downloads the model from the LEAP library on demand and throws
    /// catchable Swift errors. (The low-level `ModelDownloader` path crashed the
    /// process on an invalid URL because the error escaped from a Kotlin coroutine.)
    @MainActor
    func ensureModelLoaded(for modelName: String) async -> Bool {
        if loadedModelName == modelName && modelRunner != nil {
            return true
        }

        isModelLoading = true
        downloadProgress = 0.0

        // Release old model
        modelRunner = nil
        conversation = nil
        loadedModelName = nil

        do {
            let options = LiquidInferenceEngineManifestOptions().with(contextSize: 2048)

            let runner = try await Leap.shared.load(
                model: modelName,
                quantization: "Q4_0",
                options: options,
                progress: { [weak self] progress, _ in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                }
            )

            self.modelRunner = runner
            self.loadedModelName = modelName
            self.isModelLoading = false
            return true
        } catch {
            isModelLoading = false
            print("Failed to load model \(modelName): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Message Generation
    
    @MainActor
    func sendMessage(_ text: String, attachedImage: UIImage? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachedImage != nil else { return }
        
        guard let sessionId = currentSessionId,
              let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        let session = sessions[index]
        
        let success = await ensureModelLoaded(for: session.modelName)
        guard success, let runner = modelRunner else {
            appendMessage(to: index, content: "Failed to initialize \(session.modelName). Please try again.", isUser: false)
            return
        }
        
        var contentArray: [ChatMessageContent] = []
        var imageData: Data? = nil
        
        if let image = attachedImage {
            do {
                let imageContent = try ChatMessageContent.fromUIImage(image)
                contentArray.append(imageContent)
                imageData = image.jpegData(compressionQuality: 0.8)
            } catch {
                print("Error converting image: \(error.localizedDescription)")
                appendMessage(to: index, content: "Failed to attach image: \(error.localizedDescription)", isUser: false)
                return
            }
        }
        
        if !trimmed.isEmpty {
            contentArray.append(ChatMessageContent.text(trimmed))
        }
        
        let userMessage = ChatMessage_withArray(role: .user, content: contentArray)
        
        setupConversationIfNeeded(for: session, runner: runner)
        
        let displayPrompt = trimmed.isEmpty ? "[Image]" : trimmed
        appendMessage(to: index, content: displayPrompt, isUser: true, imageData: imageData)
        
        isLoadingResponse = true
        executionStatus = nil
        currentAssistantMessage = ""
        currentAssistantSpeed = nil
        
        playbackManager.reset()
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        streamResponse(for: userMessage, sessionIndex: index)
    }
    
    // MARK: - Voice/Audio Chat
    
    @MainActor
    func toggleRecording() {
        if isRecording {
            recorder.stop()
            isRecording = false
            recordingStatus = "Processing..."
            
            guard let capture = recorder.capture() else {
                recordingStatus = "No audio captured."
                return
            }
            
            Task {
                await sendAudioPrompt(samples: capture.samples, sampleRate: capture.sampleRate)
            }
        } else {
            do {
                try recorder.start()
                isRecording = true
                recordingStatus = "Recording..."
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } catch {
                recordingStatus = "Recording failed: \(error.localizedDescription)"
            }
        }
    }
    
    @MainActor
    func cancelRecording() {
        recorder.cancel()
        isRecording = false
        recordingStatus = "Recording cancelled."
    }
    
    @MainActor
    func playAudio(_ data: Data) {
        playbackManager.play(wavData: data)
    }
    
    @MainActor
    private func sendAudioPrompt(samples: [Float], sampleRate: Int) async {
        guard !samples.isEmpty else {
            recordingStatus = "Audio capture was empty."
            return
        }
        
        guard let sessionId = currentSessionId,
              let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        let session = sessions[index]
        
        let success = await ensureModelLoaded(for: session.modelName)
        guard success, let runner = modelRunner else {
            appendMessage(to: index, content: "Failed to initialize \(session.modelName) for audio.", isUser: false)
            return
        }
        
        // FIX: Handled the throwing call properly!
        guard let content = try? ChatMessageContent.fromFloatSamples(samples, sampleRate: sampleRate) else {
            appendMessage(to: index, content: "Failed to process audio samples.", isUser: false)
            return
        }
        
        let chatMessage = ChatMessage(role: .user, content: content)
        
        var audioData: Data? = nil
        if case .audio(let audioContent) = onEnum(of: content) {
            audioData = audioContent.data.toData()
        }
        
        setupConversationIfNeeded(for: session, runner: runner)
        
        let displayPrompt = "🎤 Voice message (\(samples.count / sampleRate)s)"
        appendMessage(to: index, content: displayPrompt, isUser: true, audioData: audioData)
        
        isLoadingResponse = true
        executionStatus = nil
        currentAssistantMessage = ""
        currentAssistantSpeed = nil
        
        playbackManager.reset()
        
        streamResponse(for: chatMessage, sessionIndex: index)
    }
    
    // MARK: - Common Stream Manager
    
    // MARK: - Text-to-Speech controls

    /// Speaks the given text aloud on-device (used by the per-message speaker button).
    @MainActor
    func speak(_ text: String) {
        speech.speak(text)
    }

    /// Stops any in-progress speech.
    @MainActor
    func stopSpeaking() {
        speech.stop()
    }

    /// Chosen TTS voice identifier (empty string = automatic by language).
    var selectedVoiceID: String {
        get { speech.selectedVoiceID }
        set { speech.selectedVoiceID = newValue }
    }

    /// Installed voices for the settings picker.
    func availableVoices() -> [AVSpeechSynthesisVoice] {
        speech.availableVoices()
    }

    /// Plays a short sample of a voice so the user can audition it.
    @MainActor
    func previewVoice(_ identifier: String) {
        speech.preview(voiceID: identifier)
    }

    @MainActor
    private func streamResponse(for message: ChatMessage, sessionIndex: Int) {
        guard let conversation = conversation else { return }

        // A new answer is starting — silence any reply still being read aloud.
        speech.stop()

        let stream = conversation.generateResponse(message: message)
        
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in stream {
                if Task.isCancelled { break }
                self.handleEvent(event, sessionIndex: sessionIndex)
            }
            self.generationTask = nil
        }
    }
    
    @MainActor
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isLoadingResponse = false
        executionStatus = nil
        
        if !currentAssistantMessage.isEmpty {
            if let sessionId = currentSessionId,
                  let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                appendMessage(to: index, content: currentAssistantMessage + " [Generation Stopped]", isUser: false, speed: currentAssistantSpeed)
            }
        }
        currentAssistantMessage = ""
        playbackManager.reset()
    }
    
    @MainActor
    private func handleEvent(_ event: any MessageResponse, sessionIndex: Int) {
        switch onEnum(of: event) {
        case .chunk(let chunk):
            currentAssistantMessage.append(chunk.text)
        case .audioSample(let audioSample):
            playbackManager.enqueue(
                samples: audioSample.samples.toFloatArray(),
                sampleRate: Int(audioSample.sampleRate)
            )
        case .complete(let completion):
            let text = completion.fullMessage.content.compactMap { content -> String? in
                if case .text(let t) = onEnum(of: content) {
                    return t.text
                }
                return nil
            }.joined()

            var audioData: Data? = nil
            for content in completion.fullMessage.content {
                if case .audio(let audioContent) = onEnum(of: content) {
                    audioData = audioContent.data.toData()
                }
            }

            let speed = completion.stats?.tokenPerSecond
            if let speedVal = speed {
                currentAssistantSpeed = Double(speedVal)
            }

            // The streamed chunks already hold the assistant text; prefer them when
            // the completion's full message carries no text part (e.g. some VL paths).
            var finalText = text
            if finalText.isEmpty { finalText = currentAssistantMessage }

            let placeholder: String
            if audioData != nil {
                placeholder = "(Audio response)"
            } else {
                placeholder = "(No response — the model returned nothing.)"
            }

            #if DEBUG
            let kinds = completion.fullMessage.content.map { c -> String in
                switch onEnum(of: c) {
                case .text: return "text"
                case .image: return "image"
                case .audio: return "audio"
                default: return "other"
                }
            }
            print("[VL/complete] content kinds: \(kinds), streamedChars: \(currentAssistantMessage.count), textChars: \(text.count)")
            #endif

            appendMessage(
                to: sessionIndex,
                content: finalText.isEmpty ? placeholder : finalText,
                isUser: false,
                audioData: audioData,
                speed: currentAssistantSpeed
            )
            
            currentAssistantMessage = ""
            isLoadingResponse = false

            if let audioData {
                // Model produced its own audio — play that, don't double up with TTS.
                playbackManager.play(wavData: audioData)
            } else if speakResponses {
                // Text-only reply: read it aloud on-device.
                let spoken = finalText.isEmpty ? "" : finalText
                speech.speak(spoken)
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            break
        }
    }
    
    private func setupConversationIfNeeded(for session: ChatSession, runner: any ModelRunner) {
        if conversation == nil {
            var history: [ChatMessage] = []
            
            var systemPrompt = session.systemPrompt
            if systemPrompt.isEmpty {
                systemPrompt = "You are a helpful AI assistant."
            }
            
            history.append(ChatMessage(role: .system, textContent: systemPrompt))
            
            for msg in session.messages {
                history.append(ChatMessage(role: msg.isUser ? .user : .assistant, textContent: msg.content))
            }
            conversation = Conversation(modelRunner: runner, history: history)
        }
    }
    
    private func appendMessage(to index: Int, content: String, isUser: Bool, imageData: Data? = nil, audioData: Data? = nil, speed: Double? = nil) {
        let newMessage = ChatMessageData(
            content: content,
            isUser: isUser,
            imageData: imageData,
            audioData: audioData,
            speed: speed
        )
        sessions[index].messages.append(newMessage)
        save()
    }
}

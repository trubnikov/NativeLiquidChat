import SwiftUI
import LeapSDK
import AVFoundation
import Translation

@Observable
class ChatStore {
    var sessions: [ChatSession] = []
    var currentSessionId: UUID? {
        didSet {
            updateTranslationConfigurations()
        }
    }
    
    // Translation configurations and active sessions
    var toEnglishConfig: TranslationSession.Configuration? = nil
    var toNativeConfig: TranslationSession.Configuration? = nil
    
    var toEnglishSession: TranslationSession? = nil
    var toNativeSession: TranslationSession? = nil
    
    // Model Loading State
    var isModelLoading = false
    var loadedModelName: String?
    var downloadProgress: Double = 0.0
    var isLoadingResponse = false
    var executionStatus: String?
    var currentThinkingLog: String? = nil

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
    /// True while the current reply should be spoken sentence-by-sentence as it
    /// streams in (text replies only; audio-model replies carry their own audio).
    private var streamingTTS = false

    // Hands-free conversation mode (listen → recognize → answer → speak → repeat)
    enum ConversationPhase {
        case idle, listening, thinking, speaking
    }
    var conversationMode = false
    var conversationPhase: ConversationPhase = .idle
    var liveTranscript = ""
    private let recognizer = SpeechRecognizer()
    
    
    
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
        // Migrate any sessions that still point at the removed Audio model.
        for i in sessions.indices where sessions[i].modelName.contains("Audio") {
            sessions[i].modelName = "LFM2.5-1.2B-Instruct"
        }
        if self.sessions.isEmpty {
            createSession()
        } else {
            self.currentSessionId = self.sessions.first?.id
        }
        playbackManager.prepareSession()

        // When a spoken reply finishes, conversation mode resumes listening.
        speech.onFinishSpeaking = { [weak self] in
            Task { @MainActor in self?.conversationDidFinishSpeaking() }
        }
        updateTranslationConfigurations()
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

    func updateTranslationEnabled(id: UUID, enabled: Bool) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].translationEnabled = enabled
            save()
            if currentSessionId == id {
                self.conversation = nil
                updateTranslationConfigurations()
            }
        }
    }
    
    func updateUserLanguageCode(id: UUID, code: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].userLanguageCode = code
            save()
            if currentSessionId == id {
                self.conversation = nil
                updateTranslationConfigurations()
            }
        }
    }

    func updateTranslationConfigurations() {
        if let session = currentSession, session.isTranslationEnabled {
            let nativeCode = session.languageCode
            toEnglishConfig = TranslationSession.Configuration(
                source: Locale(identifier: nativeCode).language,
                target: Locale(identifier: "en-US").language
            )
            toNativeConfig = TranslationSession.Configuration(
                source: Locale(identifier: "en-US").language,
                target: Locale(identifier: nativeCode).language
            )
        } else {
            toEnglishConfig = nil
            toNativeConfig = nil
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
        
        let isVisionModel = session.modelName.contains("VL")
        var perceivedRealityText: String? = nil
        var dynamicSystemPrompt: String? = nil
        
        if let image = attachedImage {
            self.isLoadingResponse = true
            self.executionStatus = "Perceiving image via Apple Vision..."
            
            let analysis = await VisionProcessor.analyzeImage(image)
            let classificationsStr = analysis.classifications.joined(separator: ", ")
            let detectedText = analysis.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Parse classifications into [String: Double] to run cosine similarity vector matching
            var classificationsMap: [String: Double] = [:]
            for classification in analysis.classifications {
                let components = classification.components(separatedBy: " (")
                if components.count == 2,
                   let confidenceStr = components[1].components(separatedBy: "%)").first,
                   let confidenceVal = Double(confidenceStr) {
                    classificationsMap[components[0]] = confidenceVal / 100.0
                }
            }
            
            let customObjectRecognized = TrainedObjectsManager.shared.findMatch(for: classificationsMap)
            
            var reality = ""
            if let customMatch = customObjectRecognized {
                reality += "User-trained object recognized: \"\(customMatch)\"\n"
            }
            reality += "Objects detected: \(classificationsStr)"
            if !detectedText.isEmpty {
                reality += "\nRecognized text: \"\(detectedText)\""
            }
            perceivedRealityText = reality
            
            // Instantly get cognitive hypothesis and persona locally (avoids KV cache pollution & delay)
            let state = analysis.cognitiveState
            let hypothesis = state.hypothesis
            var persona = state.persona
            
            if let customMatch = customObjectRecognized {
                persona += "\nNote: User-trained object \"\(customMatch)\" is present in this image. Refer to it as \"\(customMatch)\"."
            }
            
            dynamicSystemPrompt = persona
            
            var thinkingLogStr = """
            👁️ **Apple Vision Perceptions:**
            - Classifications: \(classificationsStr)
            - Text: \(detectedText.isEmpty ? "None detected" : "\"\(detectedText)\"")
            """
            
            if let customMatch = customObjectRecognized {
                thinkingLogStr += "\n- 🌟 Trained Object: \"\(customMatch)\""
            }
            
            thinkingLogStr += """
            
            
            🧠 **Cognitive Hypothesis:**
            "\(hypothesis)"
            
            🎭 **Adapted Persona:**
            "\(persona)"
            """
            
            self.currentThinkingLog = thinkingLogStr
            
            // Force recreation of conversation history with our dynamic system prompt
            self.conversation = nil
        }
        
        var contentArray: [ChatMessageContent] = []
        var imageData: Data? = nil
        
        if let image = attachedImage {
            imageData = image.jpegData(compressionQuality: 0.8)
            if isVisionModel {
                do {
                    let imageContent = try ChatMessageContent.fromUIImage(image)
                    contentArray.append(imageContent)
                } catch {
                    print("Error converting image: \(error.localizedDescription)")
                    appendMessage(to: index, content: "Failed to attach image: \(error.localizedDescription)", isUser: false)
                    return
                }
            }
        }
        
        var sendingText = trimmed
        if session.isTranslationEnabled && !trimmed.isEmpty {
            sendingText = await translate(trimmed, source: session.languageCode, target: "en-US")
        }
        
        // Default text prompt if empty user query with image
        if sendingText.isEmpty && attachedImage != nil {
            sendingText = "Describe this image."
        }
        
        // Inject perceived image description if model is pure text
        if !isVisionModel, let perceived = perceivedRealityText {
            let promptBase = sendingText.isEmpty ? "Describe what is happening in this scene." : sendingText
            sendingText = "[Sensory Input - Perceived Scene Description:\n\(perceived)]\n\nUser request: \(promptBase)"
        }
        
        if !sendingText.isEmpty {
            contentArray.append(ChatMessageContent.text(sendingText))
        }
        
        let userMessage = ChatMessage_withArray(role: .user, content: contentArray)
        
        setupConversationIfNeeded(for: session, runner: runner, customSystemPrompt: dynamicSystemPrompt)
        
        let displayPrompt = trimmed.isEmpty ? "[Image]" : trimmed
        appendMessage(to: index, content: sendingText, isUser: true, imageData: imageData, displayContent: displayPrompt)
        
        isLoadingResponse = true
        executionStatus = nil
        currentAssistantMessage = ""
        currentAssistantSpeed = nil
        
        playbackManager.reset()

        // Speak the reply sentence-by-sentence as it streams (text/vision only).
        streamingTTS = speakResponses && !session.modelName.contains("Audio")
        if streamingTTS { speech.beginStreaming() }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if conversationMode {
            startBargeInListening()
        }

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

    // MARK: - Hands-free conversation mode

    /// Toggles the continuous listen→answer→speak loop.
    @MainActor
    func toggleConversationMode() {
        if conversationMode {
            stopConversation()
        } else {
            startConversation()
        }
    }

    @MainActor
    func startConversation() {
        SpeechRecognizer.requestAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.recordingStatus = "Speech permission denied."
                return
            }
            self.conversationMode = true
            self.speakResponses = true   // the loop must speak replies back
            self.beginListening()
        }
    }

    @MainActor
    func stopConversation() {
        conversationMode = false
        conversationPhase = .idle
        liveTranscript = ""
        recognizer.stop()
        speech.stop()
    }

    /// Enters the listening phase and wires up recognition callbacks.
    @MainActor
    private func beginListening() {
        guard conversationMode else { return }
        conversationPhase = .listening
        liveTranscript = ""

        recognizer.onPartial = { [weak self] text in
            self?.liveTranscript = text
            self?.handleInterruption(text: text)
        }
        recognizer.onFinished = { [weak self] text in
            guard let self, self.conversationMode else { return }
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            print("[Conversation] heard: '\(spoken)'")
            #endif
            self.liveTranscript = ""
            if spoken.isEmpty {
                // Heard nothing this turn — pause briefly, then listen again.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self.beginListening()
                }
                return
            }
            self.conversationPhase = .thinking
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await self.sendMessage(spoken) }
        }

        do {
            try recognizer.start(timeoutEnabled: true)
            #if DEBUG
            print("[Conversation] listening…")
            #endif
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            print("[Conversation] recognizer start failed: \(error)")
            recordingStatus = "On-device recognition unavailable for this language."
            stopConversation()
        }
    }

    /// Handles voice barge-in (interruption) when user speaks during thinking or speaking phases.
    @MainActor
    private func handleInterruption(text: String) {
        guard conversationMode else { return }
        guard conversationPhase == .thinking || conversationPhase == .speaking else { return }
        
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        
        #if DEBUG
        print("[Conversation] Barge-in! Interrupting assistant with text: '\(cleaned)'")
        #endif
        
        // Stop current speaking/playing/generation immediately
        stopSpeaking()
        playbackManager.reset()
        stopGeneration()
        
        // Transition back to active listening state
        conversationPhase = .listening
        liveTranscript = cleaned
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Starts speech recognition in background without idle timeout during synthesis.
    @MainActor
    private func startBargeInListening() {
        guard conversationMode else { return }
        
        recognizer.onPartial = { [weak self] text in
            self?.liveTranscript = text
            self?.handleInterruption(text: text)
        }
        recognizer.onFinished = { [weak self] text in
            guard let self, self.conversationMode else { return }
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.liveTranscript = ""
            
            // If we are still in thinking/speaking phase (i.e. did not interrupt), ignore finish.
            if self.conversationPhase == .thinking || self.conversationPhase == .speaking {
                return
            }
            
            if spoken.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self.beginListening()
                }
                return
            }
            
            self.conversationPhase = .thinking
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await self.sendMessage(spoken) }
        }
        
        do {
            try recognizer.start(timeoutEnabled: false)
        } catch {
            print("[Conversation] failed to start barge-in recognizer: \(error)")
        }
    }

    /// Called after a reply has been spoken — resume listening for the next turn.
    @MainActor
    private func conversationDidFinishSpeaking() {
        guard conversationMode else { return }
        recognizer.stop() // stop barge-in recognizer
        beginListening()  // restart with idle timeout enabled
    }

    @MainActor
    private func streamResponse(for message: ChatMessage, sessionIndex: Int) {
        guard let conversation = conversation else { return }

        // A new answer is starting — silence any reply still being read aloud.
        // (When streaming TTS, beginStreaming() already stopped prior speech, so
        // don't stop again here or we'd cancel the run we just started.)
        if !streamingTTS { speech.stop() }

        let stream = conversation.generateResponse(message: message)
        
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in stream {
                if Task.isCancelled { break }
                await self.handleEvent(event, sessionIndex: sessionIndex)
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
    private func handleEvent(_ event: any MessageResponse, sessionIndex: Int) async {
        switch onEnum(of: event) {
        case .chunk(let chunk):
            currentAssistantMessage.append(chunk.text)
            if streamingTTS { speech.appendStreaming(chunk.text) }
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

            let session = sessions[sessionIndex]
            if session.isTranslationEnabled && !finalText.isEmpty {
                executionStatus = "Translating..."
                finalText = await translate(finalText, source: "en-US", target: session.languageCode)
                executionStatus = nil
            }

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
                speed: currentAssistantSpeed,
                thinkingLog: currentThinkingLog
            )
            
            currentThinkingLog = nil
            currentAssistantMessage = ""
            isLoadingResponse = false

            let spokenText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let audioData {
                // Model produced its own audio — play that, don't double up with TTS.
                playbackManager.play(wavData: audioData)
            } else if streamingTTS {
                // Already speaking as it streamed — just flush the trailing words.
                if conversationMode { conversationPhase = .speaking }
                speech.finishStreaming()
                streamingTTS = false
                if spokenText.isEmpty && conversationMode {
                    // Nothing was ever spoken — resume listening.
                    conversationDidFinishSpeaking()
                }
            } else if speakResponses && !spokenText.isEmpty {
                // Fallback one-shot speak (e.g. streaming was off).
                if conversationMode { conversationPhase = .speaking }
                speech.speak(spokenText)
            } else if conversationMode {
                // Nothing to speak — resume listening right away.
                conversationDidFinishSpeaking()
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            break
        }
    }
    
    private func extractFloatSamples(from wavData: Data) -> (samples: [Float], sampleRate: Int)? {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        do {
            try wavData.write(to: tmpURL)
            let file = try AVAudioFile(forReading: tmpURL)
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.fileFormat.sampleRate, channels: 1, interleaved: false) else {
                try? FileManager.default.removeItem(at: tmpURL)
                return nil
            }
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                try? FileManager.default.removeItem(at: tmpURL)
                return nil
            }
            try file.read(into: buffer)
            try? FileManager.default.removeItem(at: tmpURL)
            guard let channelData = buffer.floatChannelData else { return nil }
            let pointer = channelData[0]
            let samples = Array(UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength)))
            return (samples, Int(file.fileFormat.sampleRate))
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            print("[ChatStore] Error extracting float samples from wav: \(error)")
            return nil
        }
    }
    
    private func setupConversationIfNeeded(for session: ChatSession, runner: any ModelRunner, customSystemPrompt: String? = nil) {
        if conversation == nil {
            var history: [ChatMessage] = []

            // The LFM2-Audio engine rejects a system message ("Invalid system
            // prompt" → empty reply), so only add one for non-audio models.
            let isAudioModel = session.modelName.contains("Audio")
            if !isAudioModel {
                var systemPrompt = customSystemPrompt ?? session.systemPrompt
                if systemPrompt.isEmpty {
                    systemPrompt = "You are a helpful AI assistant."
                }
                history.append(ChatMessage(role: .system, textContent: systemPrompt))
            }

            for msg in session.messages {
                var contentArray: [ChatMessageContent] = []
                
                if msg.audioData != nil {
                    // Audio message content
                    if let audioData = msg.audioData, let extracted = extractFloatSamples(from: audioData) {
                        if let audioContent = try? ChatMessageContent.fromFloatSamples(extracted.samples, sampleRate: extracted.sampleRate) {
                            contentArray.append(audioContent)
                        }
                    }
                } else if msg.imageData != nil {
                    // Vision message content (+ text if not placeholder)
                    let isVisionModel = session.modelName.contains("VL")
                    if isVisionModel, let imageData = msg.imageData, let image = UIImage(data: imageData) {
                        if let imageContent = try? ChatMessageContent.fromUIImage(image) {
                            contentArray.append(imageContent)
                        }
                    }
                    let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed != "[Image]" {
                        contentArray.append(ChatMessageContent.text(trimmed))
                    }
                } else {
                    // Regular text content
                    let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        contentArray.append(ChatMessageContent.text(trimmed))
                    }
                }
                
                if !contentArray.isEmpty {
                    let chatMsg = ChatMessage_withArray(role: msg.isUser ? .user : .assistant, content: contentArray)
                    history.append(chatMsg)
                }
            }
            conversation = Conversation(modelRunner: runner, history: history)
        }
    }
    
    /// Asynchronously translates the given text using on-device TranslationSession silently.
    @MainActor
    func translate(_ text: String, source: String, target: String) async -> String {
        guard source != target && !text.isEmpty else { return text }
        
        let isToEnglish = (target == "en-US")
        let session = isToEnglish ? toEnglishSession : toNativeSession
        
        guard let session else {
            print("[Translation] No active session registered for \(isToEnglish ? "to-English" : "to-Native").")
            return text
        }
        
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            print("[Translation] Programmatic translation failed: \(error.localizedDescription)")
            
            // Let the user know the offline package is missing
            let localeName = Locale.current.localizedString(forLanguageCode: source) ?? source
            self.executionStatus = "Missing offline translation pack for \(localeName). Download in iOS Settings -> Translate."
            
            // Clear status after 8 seconds
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await MainActor.run { [weak self] in
                    if self?.executionStatus?.contains("offline translation pack") == true {
                        self?.executionStatus = nil
                    }
                }
            }
            return text
        }
    }
    
    private func appendMessage(to index: Int, content: String, isUser: Bool, imageData: Data? = nil, audioData: Data? = nil, speed: Double? = nil, thinkingLog: String? = nil, displayContent: String? = nil) {
        let newMessage = ChatMessageData(
            content: content,
            isUser: isUser,
            imageData: imageData,
            audioData: audioData,
            speed: speed,
            thinkingLog: thinkingLog,
            displayContent: displayContent
        )
        sessions[index].messages.append(newMessage)
        save()
    }
}

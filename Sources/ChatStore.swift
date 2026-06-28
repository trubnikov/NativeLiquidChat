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
    
    // Voice/Audio State
    var isRecording = false
    var recordingStatus = "Ready"
    
    // Chat Stream State & Speed
    var currentAssistantMessage = ""
    var currentAssistantSpeed: Double?
    
    private var modelRunner: (any ModelRunner)?
    private var conversation: (any Conversation)?
    private var generationTask: Task<Void, Never>?
    
    private let playbackManager = AudioPlaybackManager()
    private let recorder = AudioRecorder()
    
    var currentSession: ChatSession? {
        sessions.first(where: { $0.id == currentSessionId })
    }
    
    init() {
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
            let options = LiquidInferenceEngineManifestOptions(
                contextSize: 1024,
                nGpuLayers: 0 // Set to 0 to prevent OOM/GPU crashes on some mobile models if needed, or use default
            )
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
        
        // Ensure model is loaded
        let success = await ensureModelLoaded(for: session.modelName)
        guard success, let runner = modelRunner else {
            appendMessage(to: index, content: "Failed to initialize \(session.modelName). Please try again.", isUser: false)
            return
        }
        
        // Prepare content array
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
        
        // Append user message with image if present
        let displayPrompt = trimmed.isEmpty ? "[Image]" : trimmed
        appendMessage(to: index, content: displayPrompt, isUser: true, imageData: imageData)
        
        isLoadingResponse = true
        currentAssistantMessage = ""
        currentAssistantSpeed = nil
        
        // Initialize Conversation if needed
        setupConversationIfNeeded(for: session, runner: runner)
        
        playbackManager.reset()
        
        // Trigger haptic
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
        
        let content = ChatMessageContent.fromFloatSamples(samples, sampleRate: sampleRate)
        let chatMessage = ChatMessage(role: .user, content: content)
        
        // Extract raw wav data for storing in history
        var audioData: Data? = nil
        if case .audio(let audioContent) = onEnum(of: content) {
            audioData = audioContent.data.toData()
        }
        
        let displayPrompt = "🎤 Voice message (\(samples.count / sampleRate)s)"
        appendMessage(to: index, content: displayPrompt, isUser: true, audioData: audioData)
        
        isLoadingResponse = true
        currentAssistantMessage = ""
        currentAssistantSpeed = nil
        
        setupConversationIfNeeded(for: session, runner: runner)
        playbackManager.reset()
        
        streamResponse(for: chatMessage, sessionIndex: index)
    }
    
    // MARK: - Common Stream Manager
    
    @MainActor
    private func streamResponse(for message: ChatMessage, sessionIndex: Int) {
        guard let conversation = conversation else { return }
        
        let stream = conversation.generateResponse(message: message)
        
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    self.handleEvent(event)
                }
            } catch {
                self.appendMessage(to: sessionIndex, content: "Generation Error: \(error.localizedDescription)", isUser: false)
                self.isLoadingResponse = false
                self.currentAssistantMessage = ""
            }
            self.generationTask = nil
        }
    }
    
    @MainActor
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isLoadingResponse = false
        
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
    private func handleEvent(_ event: any MessageResponse) {
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
            
            if let sessionId = currentSessionId,
               let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                appendMessage(
                    to: index,
                    content: text.isEmpty ? "(Audio response)" : text,
                    isUser: false,
                    audioData: audioData,
                    speed: currentAssistantSpeed
                )
            }
            
            currentAssistantMessage = ""
            isLoadingResponse = false
            
            // Play back the full audio if present
            if let audioData {
                playbackManager.play(wavData: audioData)
            }
            
            // Trigger success haptic
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            break
        }
    }
    
    private func setupConversationIfNeeded(for session: ChatSession, runner: any ModelRunner) {
        if conversation == nil {
            var history: [ChatMessage] = []
            if !session.systemPrompt.isEmpty {
                history.append(ChatMessage(role: .system, textContent: session.systemPrompt))
            }
            for msg in session.messages {
                if let audioData = msg.audioData {
                    // Reconstruct audio content if needed, but for simplicity of context we'll append it as text or skip to prevent heavy context
                    history.append(ChatMessage(role: msg.isUser ? .user : .assistant, textContent: msg.content))
                } else {
                    history.append(ChatMessage(role: msg.isUser ? .user : .assistant, textContent: msg.content))
                }
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
extension [Float] {
    func toFloatArray() -> [Float] {
        return self
    }
}

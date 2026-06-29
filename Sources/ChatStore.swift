import SwiftUI
import LeapModelDownloader
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
    
    // Model Download & Disk Management State
    enum ModelStatus: Hashable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
    }
    
    var modelStatuses: [String: ModelStatus] = [:]
    private var downloader: ModelDownloader!
    
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
        
        // Setup local model downloader
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let saveDir = paths[0].appendingPathComponent("leap_models").path
        let config = LeapDownloaderConfig(
            saveDir: saveDir,
            validateSha256: true,
            disableSslValidation: false,
            baseUrl: nil,
            connectTimeoutMillis: 30000,
            socketTimeoutMillis: 60000,
            requestTimeoutMillis: 600000
        )
        self.downloader = ModelDownloader(config: config, sessionConfiguration: nil)
        
        // Initial check of model statuses on disk
        Task {
            await checkModelStatuses()
        }
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
    
    // MARK: - Model Status and Storage Management
    
    func checkModelStatuses() async {
        let models = ["LFM2.5-1.2B-Instruct", "LFM2.5-VL-1.6B", "LFM2.5-Audio-1.5B"]
        for model in models {
            do {
                let status = try await downloader.queryStatus(modelName: model, quantizationType: "Q4_0")
                await MainActor.run {
                    if status is ModelDownloadStatusDownloaded {
                        self.modelStatuses[model] = .downloaded
                    } else if let progressStatus = status as? ModelDownloadStatusDownloadInProgress {
                        self.modelStatuses[model] = .downloading(progress: progressStatus.progress)
                    } else {
                        self.modelStatuses[model] = .notDownloaded
                    }
                }
            } catch {
                print("Error querying status for \(model): \(error.localizedDescription)")
                await MainActor.run {
                    self.modelStatuses[model] = .notDownloaded
                }
            }
        }
    }
    
    func downloadModel(_ modelName: String) async {
        await MainActor.run {
            self.modelStatuses[modelName] = .downloading(progress: 0.0)
        }
        
        do {
            _ = try await downloader.downloadModel(modelName: modelName, quantizationType: "Q4_0") { [weak self] progress, _ in
                Task { @MainActor in
                    self?.modelStatuses[modelName] = .downloading(progress: progress.doubleValue)
                }
            }
            await checkModelStatuses()
        } catch {
            print("Failed to download model \(modelName): \(error.localizedDescription)")
            await checkModelStatuses()
        }
    }
    
    func deleteModel(_ modelName: String) async {
        do {
            if loadedModelName == modelName {
                await MainActor.run {
                    self.modelRunner = nil
                    self.conversation = nil
                    self.loadedModelName = nil
                }
            }
            
            try await downloader.removeModel(modelName: modelName, quantizationType: "Q4_0")
            await checkModelStatuses()
        } catch {
            print("Failed to delete model \(modelName): \(error.localizedDescription)")
            await checkModelStatuses()
        }
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
                nGpuLayers: 0
            )
            
            let runner = try await downloader.loadModel(
                modelName: modelName,
                quantizationType: "Q4_0",
                options: options,
                generationTimeParameters: nil,
                forceDownload: false,
                downloadProgress: { [weak self] progress, _ in
                    Task { @MainActor in
                        self?.downloadProgress = progress.doubleValue
                        self?.modelStatuses[modelName] = .downloading(progress: progress.doubleValue)
                    }
                }
            )
            
            self.modelRunner = runner
            self.loadedModelName = modelName
            self.isModelLoading = false
            await checkModelStatuses()
            return true
        } catch {
            isModelLoading = false
            print("Failed to load model \(modelName): \(error.localizedDescription)")
            await checkModelStatuses()
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
        
        let displayPrompt = trimmed.isEmpty ? "[Image]" : trimmed
        appendMessage(to: index, content: displayPrompt, isUser: true, imageData: imageData)
        
        isLoadingResponse = true
        executionStatus = nil
        currentAssistantMessage = ""
        currentAssistantSpeed = nil
        
        setupConversationIfNeeded(for: session, runner: runner)
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
        
        let displayPrompt = "🎤 Voice message (\(samples.count / sampleRate)s)"
        appendMessage(to: index, content: displayPrompt, isUser: true, audioData: audioData)
        
        isLoadingResponse = true
        executionStatus = nil
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
            
            appendMessage(
                to: sessionIndex,
                content: text.isEmpty ? "(Audio response)" : text,
                isUser: false,
                audioData: audioData,
                speed: currentAssistantSpeed
            )
            
            currentAssistantMessage = ""
            isLoadingResponse = false
            
            if let audioData {
                playbackManager.play(wavData: audioData)
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

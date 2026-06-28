import SwiftUI
import LeapSDK

@Observable
class ChatStore {
    var sessions: [ChatSession] = []
    var currentSessionId: UUID?
    
    // Model Loading State (global or per model)
    var isModelLoading = false
    var loadedModelName: String?
    var downloadProgress: Double = 0.0
    var isLoadingResponse = false
    
    // Chat Stream State
    var currentAssistantMessage = ""
    
    private var modelRunner: (any ModelRunner)?
    private var conversation: (any Conversation)?
    
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
            // Reset conversation to apply new system prompt
            if currentSessionId == id {
                self.conversation = nil
            }
        }
    }
    
    func updateModel(id: UUID, modelName: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].modelName = modelName
            save()
            // Reset conversation to load new model on next message
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
        
        // Release old model first
        modelRunner = nil
        conversation = nil
        loadedModelName = nil
        
        do {
            let options = LiquidInferenceEngineManifestOptions(contextSize: 2048)
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
    
    @MainActor
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        guard let sessionId = currentSessionId,
              let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        
        let session = sessions[index]
        
        // Ensure the correct model is loaded
        let success = await ensureModelLoaded(for: session.modelName)
        guard success, let runner = modelRunner else {
            appendMessage(to: index, content: "Failed to initialize \(session.modelName). Please try again.", isUser: false)
            return
        }
        
        // Append user message
        appendMessage(to: index, content: trimmed, isUser: true)
        isLoadingResponse = true
        currentAssistantMessage = ""
        
        // Initialize Conversation if not present
        if conversation == nil {
            var history: [ChatMessage] = []
            if !session.systemPrompt.isEmpty {
                history.append(ChatMessage(role: .system, textContent: session.systemPrompt))
            }
            // Add previous message history to conversation
            for msg in session.messages {
                history.append(ChatMessage(
                    role: msg.isUser ? .user : .assistant,
                    textContent: msg.content
                ))
            }
            conversation = Conversation(modelRunner: runner, history: history)
        }
        
        let userMessage = ChatMessage_withArray(role: .user, content: [ChatMessageContent.text(trimmed)])
        let stream = conversation!.generateResponse(message: userMessage)
        
        // Trigger haptic feedback for sending
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        do {
            for try await resp in stream {
                switch onEnum(of: resp) {
                case .chunk(let chunk):
                    currentAssistantMessage.append(chunk.text)
                case .complete(let completion):
                    let finalText = completion.fullMessage.content.compactMap { content -> String? in
                        if case .text(let t) = onEnum(of: content) {
                            return t.text
                        }
                        return nil
                    }.joined()
                    
                    if !finalText.isEmpty {
                        currentAssistantMessage = finalText
                    }
                    
                    if !currentAssistantMessage.isEmpty {
                        appendMessage(to: index, content: currentAssistantMessage, isUser: false)
                    }
                    currentAssistantMessage = ""
                    isLoadingResponse = false
                    
                    // Trigger haptic for success
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                default:
                    break
                }
            }
        } catch {
            appendMessage(to: index, content: "Generation Error: \(error.localizedDescription)", isUser: false)
            isLoadingResponse = false
            currentAssistantMessage = ""
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    private func appendMessage(to index: Int, content: String, isUser: Bool) {
        let newMessage = ChatMessageData(content: content, isUser: isUser)
        sessions[index].messages.append(newMessage)
        save()
    }
}

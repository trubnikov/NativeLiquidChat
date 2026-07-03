import Foundation

struct ChatMessageData: Codable, Identifiable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    var imageData: Data?
    var audioData: Data?
    var speed: Double? // tokens/sec speed if generated
    var thinkingLog: String?
    var displayContent: String?
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date(), imageData: Data? = nil, audioData: Data? = nil, speed: Double? = nil, thinkingLog: String? = nil, displayContent: String? = nil) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.imageData = imageData
        self.audioData = audioData
        self.speed = speed
        self.thinkingLog = thinkingLog
        self.displayContent = displayContent
    }
}

struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var modelName: String
    var systemPrompt: String
    var messages: [ChatMessageData]
    let createdAt: Date
    var translationEnabled: Bool?
    var userLanguageCode: String?
    
    var isTranslationEnabled: Bool {
        translationEnabled ?? false
    }
    
    var languageCode: String {
        userLanguageCode ?? "ru-RU"
    }
    
    var iconName: String {
        if modelName.contains("Audio") {
            return "waveform"
        } else if modelName.contains("VL") {
            return "eye"
        } else {
            return "bubble.left.and.bubble.right"
        }
    }
    
    init(id: UUID = UUID(), title: String = "New Chat", modelName: String = "LFM2.5-1.2B-Instruct", systemPrompt: String = "", messages: [ChatMessageData] = [], createdAt: Date = Date(), translationEnabled: Bool = false, userLanguageCode: String = "ru-RU") {
        self.id = id
        self.title = title
        self.modelName = modelName
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.createdAt = createdAt
        self.translationEnabled = translationEnabled
        self.userLanguageCode = userLanguageCode
    }
}

class ChatStorage {
    private static let fileName = "chat_sessions.json"
    
    private static var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(fileName)
    }
    
    static func loadSessions() -> [ChatSession] {
        do {
            let data = try Data(contentsOf: fileURL)
            let sessions = try JSONDecoder().decode([ChatSession].self, from: data)
            return sessions
        } catch {
            print("Failed to load sessions: \(error.localizedDescription)")
            return []
        }
    }
    
    static func saveSessions(_ sessions: [ChatSession]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to save sessions: \(error.localizedDescription)")
        }
    }
}

import Foundation

struct ChatMessageData: Codable, Identifiable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var modelName: String
    var systemPrompt: String
    var messages: [ChatMessageData]
    let createdAt: Date
    
    init(id: UUID = UUID(), title: String = "New Chat", modelName: String = "LFM2.5-1.2B-Instruct", systemPrompt: String = "", messages: [ChatMessageData] = [], createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.modelName = modelName
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.createdAt = createdAt
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

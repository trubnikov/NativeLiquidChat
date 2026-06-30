import XCTest
@testable import NativeLiquidChat

final class ModelsTests: XCTestCase {

    // MARK: - ChatMessageData

    func testChatMessageDataDefaults() {
        let msg = ChatMessageData(content: "Hello", isUser: true)
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertTrue(msg.isUser)
        XCTAssertNil(msg.imageData)
        XCTAssertNil(msg.audioData)
        XCTAssertNil(msg.speed)
    }

    func testChatMessageDataCodableRoundTrip() throws {
        let original = ChatMessageData(
            content: "With media",
            isUser: false,
            imageData: Data([0x01, 0x02, 0x03]),
            audioData: Data([0xAA, 0xBB]),
            speed: 42.5
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessageData.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.isUser, original.isUser)
        XCTAssertEqual(decoded.imageData, original.imageData)
        XCTAssertEqual(decoded.audioData, original.audioData)
        XCTAssertEqual(decoded.speed, original.speed)
    }

    // MARK: - ChatSession

    func testChatSessionDefaults() {
        let session = ChatSession()
        XCTAssertEqual(session.title, "New Chat")
        XCTAssertEqual(session.modelName, "LFM2.5-1.2B-Instruct")
        XCTAssertEqual(session.systemPrompt, "")
        XCTAssertTrue(session.messages.isEmpty)
    }

    func testChatSessionIconNameForText() {
        let session = ChatSession(modelName: "LFM2.5-1.2B-Instruct")
        XCTAssertEqual(session.iconName, "bubble.left.and.bubble.right")
    }

    func testChatSessionIconNameForVision() {
        let session = ChatSession(modelName: "LFM2.5-VL-1.6B")
        XCTAssertEqual(session.iconName, "eye")
    }

    func testChatSessionIconNameForAudio() {
        let session = ChatSession(modelName: "LFM2.5-Audio-1.5B")
        XCTAssertEqual(session.iconName, "waveform")
    }

    func testChatSessionCodableRoundTrip() throws {
        let original = ChatSession(
            title: "Round trip",
            modelName: "LFM2.5-VL-1.6B",
            systemPrompt: "Be terse.",
            messages: [
                ChatMessageData(content: "Hi", isUser: true),
                ChatMessageData(content: "Hello!", isUser: false, speed: 12.3)
            ]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatSession.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.modelName, original.modelName)
        XCTAssertEqual(decoded.systemPrompt, original.systemPrompt)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages.last?.speed, 12.3)
    }

    func testSessionsArrayCodableRoundTrip() throws {
        let sessions = [
            ChatSession(title: "A"),
            ChatSession(title: "B", modelName: "LFM2.5-Audio-1.5B")
        ]
        let encoded = try JSONEncoder().encode(sessions)
        let decoded = try JSONDecoder().decode([ChatSession].self, from: encoded)
        XCTAssertEqual(decoded.map(\.title), ["A", "B"])
    }
}

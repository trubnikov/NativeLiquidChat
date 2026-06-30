import XCTest
@testable import NativeLiquidChat

/// `ChatStorage` reads/writes a fixed file in the app's Documents directory.
/// These tests exercise that real file, so they save and restore whatever was
/// there to avoid clobbering on-device data.
final class ChatStorageTests: XCTestCase {

    private var backup: [ChatSession] = []

    override func setUp() {
        super.setUp()
        backup = ChatStorage.loadSessions()
    }

    override func tearDown() {
        ChatStorage.saveSessions(backup)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let sessions = [
            ChatSession(title: "First", systemPrompt: "P1"),
            ChatSession(title: "Second", modelName: "LFM2.5-VL-1.6B")
        ]
        ChatStorage.saveSessions(sessions)

        let loaded = ChatStorage.loadSessions()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.title), ["First", "Second"])
        XCTAssertEqual(loaded.first?.systemPrompt, "P1")
        XCTAssertEqual(loaded.last?.modelName, "LFM2.5-VL-1.6B")
    }

    func testSaveEmptyLoadsEmpty() {
        ChatStorage.saveSessions([])
        XCTAssertTrue(ChatStorage.loadSessions().isEmpty)
    }

    func testPreservesMessagesAndMedia() {
        let session = ChatSession(
            title: "Media",
            messages: [
                ChatMessageData(content: "img", isUser: true, imageData: Data([0x10, 0x20])),
                ChatMessageData(content: "reply", isUser: false, speed: 7.0)
            ]
        )
        ChatStorage.saveSessions([session])

        let loaded = ChatStorage.loadSessions()
        XCTAssertEqual(loaded.first?.messages.count, 2)
        XCTAssertEqual(loaded.first?.messages.first?.imageData, Data([0x10, 0x20]))
        XCTAssertEqual(loaded.first?.messages.last?.speed, 7.0)
    }
}

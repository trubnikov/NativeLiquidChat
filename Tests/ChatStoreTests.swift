import XCTest
@testable import NativeLiquidChat

/// Exercises the pure session-management logic on `ChatStore`.
/// `ChatStore()` loads/saves the real Documents file, so each test resets the
/// store to a known state and restores any pre-existing sessions afterwards.
@MainActor
final class ChatStoreTests: XCTestCase {

    private var backup: [ChatSession] = []

    override func setUp() {
        super.setUp()
        backup = ChatStorage.loadSessions()
    }

    override func tearDown() {
        ChatStorage.saveSessions(backup)
        super.tearDown()
    }

    /// Returns a store reset to a single empty session.
    private func makeCleanStore() -> ChatStore {
        let store = ChatStore()
        store.sessions = []
        store.createSession()
        return store
    }

    func testCreateSessionInsertsAtFrontAndSelects() {
        let store = makeCleanStore()
        let firstId = store.currentSessionId

        store.createSession(modelName: "LFM2.5-VL-1.6B", systemPrompt: "vision")

        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions.first?.modelName, "LFM2.5-VL-1.6B")
        XCTAssertEqual(store.sessions.first?.systemPrompt, "vision")
        XCTAssertEqual(store.currentSessionId, store.sessions.first?.id)
        XCTAssertNotEqual(store.currentSessionId, firstId)
    }

    func testCurrentSessionMatchesSelection() {
        let store = makeCleanStore()
        XCTAssertEqual(store.currentSession?.id, store.currentSessionId)
    }

    func testRenameSession() {
        let store = makeCleanStore()
        let id = store.currentSessionId!

        store.renameSession(id: id, newTitle: "Renamed")

        XCTAssertEqual(store.sessions.first(where: { $0.id == id })?.title, "Renamed")
    }

    func testUpdateModelAndSystemPrompt() {
        let store = makeCleanStore()
        let id = store.currentSessionId!

        store.updateModel(id: id, modelName: "LFM2.5-Audio-1.5B")
        store.updateSystemPrompt(id: id, systemPrompt: "be brief")

        let session = store.sessions.first(where: { $0.id == id })
        XCTAssertEqual(session?.modelName, "LFM2.5-Audio-1.5B")
        XCTAssertEqual(session?.systemPrompt, "be brief")
    }

    func testDeleteSessionUpdatesSelection() {
        let store = makeCleanStore()
        store.createSession()                 // now 2 sessions, newest selected
        let toDelete = store.currentSessionId!

        store.deleteSession(id: toDelete)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertFalse(store.sessions.contains(where: { $0.id == toDelete }))
        XCTAssertEqual(store.currentSessionId, store.sessions.first?.id)
    }

    func testDeletingLastSessionRecreatesOne() {
        let store = makeCleanStore()
        let onlyId = store.currentSessionId!

        store.deleteSession(id: onlyId)

        // Deleting the last session should leave exactly one fresh session.
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertNotNil(store.currentSessionId)
        XCTAssertNotEqual(store.currentSessionId, onlyId)
    }
}

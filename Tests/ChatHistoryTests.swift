import XCTest
@testable import SamFinance

/// Файл с перепиской ИИ-чата: чтение, запись, пределы и защита от повреждённого файла
final class ChatHistoryStoreTests: XCTestCase {

    private func makeStore() -> ChatHistoryStore {
        ChatHistoryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).json"))
    }

    private func message(_ text: String, isUser: Bool = true, pending: Bool = false) -> StoredChatMessage {
        // Целые секунды: в файле дата хранится в формате ISO 8601 без долей
        StoredChatMessage(isUser: isUser, text: text, hadPendingCard: pending, date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testMissingFileGivesNoMessages() {
        XCTAssertTrue(makeStore().load().isEmpty)
    }

    func testSavedMessagesComeBackInOrder() {
        let store = makeStore()
        defer { store.clear() }
        let messages = [message("привет"), message("здравствуйте", isUser: false), message("покажи долги", pending: true)]
        store.save(messages)
        XCTAssertEqual(store.load(), messages)
    }

    func testCorruptFileGivesNoMessagesInsteadOfFailing() throws {
        let store = makeStore()
        defer { store.clear() }
        try Data("это не JSON".utf8).write(to: store.url)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testOnlyTheLatestMessagesAreKept() {
        let store = makeStore()
        defer { store.clear() }
        store.save((0..<250).map { message("m\($0)") })
        let loaded = store.load()
        XCTAssertEqual(loaded.count, ChatHistoryStore.maxMessages)
        XCTAssertEqual(loaded.first?.text, "m50")
        XCTAssertEqual(loaded.last?.text, "m249")
    }

    func testLongTextIsCut() {
        let store = makeStore()
        defer { store.clear() }
        store.save([message(String(repeating: "я", count: ChatHistoryStore.maxTextLength + 500))])
        XCTAssertEqual(store.load().first?.text.count, ChatHistoryStore.maxTextLength)
    }

    func testSavingNothingRemovesTheFile() {
        let store = makeStore()
        store.save([message("привет")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        store.save([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testClearRemovesTheFile() {
        let store = makeStore()
        store.save([message("привет")])
        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertTrue(store.load().isEmpty)
    }
}

/// Чат поднимает переписку после перезапуска и записывает новые сообщения
@MainActor
final class AIChatStoreHistoryTests: XCTestCase {

    private func makeStore() -> ChatHistoryStore {
        ChatHistoryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).json"))
    }

    private func stored(_ text: String, isUser: Bool, pending: Bool = false) -> StoredChatMessage {
        StoredChatMessage(isUser: isUser, text: text, hadPendingCard: pending, date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRestoredMessagesFollowTheGreeting() {
        let history = makeStore()
        defer { history.clear() }
        history.save([stored("привет", isUser: true), stored("здравствуйте", isUser: false)])

        let chat = AIChatStore(history: history)
        XCTAssertEqual(chat.messages.count, 3)
        XCTAssertEqual(chat.messages[0].role, .assistant, "приветствие остаётся первым")
        XCTAssertEqual(chat.messages[1].role, .user)
        XCTAssertEqual(chat.messages[1].text, "привет")
        XCTAssertEqual(chat.messages[2].role, .assistant)
        XCTAssertEqual(chat.messages[2].text, "здравствуйте")
        XCTAssertFalse(chat.isFresh, "с историей подсказки не показываются")
    }

    func testEmptyHistoryLeavesOnlyTheGreeting() {
        let chat = AIChatStore(history: makeStore())
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertTrue(chat.isFresh)
    }

    func testUnconfirmedCardGetsANoteInsteadOfComingBack() {
        let history = makeStore()
        defer { history.clear() }
        history.save([stored("Нашёл операцию на скриншоте.", isUser: false, pending: true)])

        let chat = AIChatStore(history: history)
        let restored = chat.messages[1]
        XCTAssertNil(restored.draft)
        XCTAssertNil(restored.actionDraft)
        XCTAssertTrue(restored.text.hasPrefix("Нашёл операцию на скриншоте."), restored.text)
        XCTAssertGreaterThan(restored.text.count, "Нашёл операцию на скриншоте.".count, "добавлена пометка")
    }

    func testResetClearsTheStoredHistory() {
        let history = makeStore()
        defer { history.clear() }
        history.save([stored("привет", isUser: true)])

        let chat = AIChatStore(history: history)
        chat.reset()
        XCTAssertEqual(chat.messages.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.url.path))
        XCTAssertEqual(AIChatStore(history: history).messages.count, 1)
    }

    func testNewMessagesAreSavedWithoutTheGreeting() throws {
        // С ключом облака запрос ушёл бы в сеть: тест рассчитан на чат без ключа, где отвечает локальный помощник
        try XCTSkipIf(AIKeyStore.key(for: AIProvider.selected) != nil, "в Keychain есть ключ ИИ")

        let history = makeStore()
        defer { history.clear() }
        let chat = AIChatStore(history: history)
        chat.send(text: "что-то непонятное")

        let saved = history.load()
        XCTAssertEqual(saved.count, 2, "вопрос и ответ помощника")
        XCTAssertEqual(saved.first?.isUser, true)
        XCTAssertEqual(saved.first?.text, "что-то непонятное")
        XCTAssertEqual(saved.last?.isUser, false)
        XCTAssertFalse(saved.contains { $0.text == chat.messages[0].text }, "приветствие не записывается")

        // После перезапуска разговор на месте
        XCTAssertEqual(AIChatStore(history: history).messages.count, 3)
    }
}

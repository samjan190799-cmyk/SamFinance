import Foundation

/// Одна реплика переписки на диске.
/// Миниатюры скриншотов и карточки с черновиками не хранятся: неподтверждённая карточка могла бы устареть,
/// и её применение через несколько дней изменило бы не то, что человек видел при ответе.
struct StoredChatMessage: Codable, Equatable, Sendable {
    var isUser: Bool
    var text: String
    /// К сообщению была карточка, которую человек так и не подтвердил: при восстановлении об этом скажет пометка
    var hadPendingCard: Bool
    var date: Date
}

/// Переписка ИИ-чата в файле рядом с остальными данными приложения: после перезапуска разговор продолжается.
/// Файл защищён средствами iOS так же, как операции и карты, и стирается кнопкой «Начать заново» и сбросом всех данных.
struct ChatHistoryStore: Sendable {
    /// Сколько последних сообщений хранится
    static let maxMessages = 200
    /// Длиннее сообщение обрезается: файл не должен расти без предела
    static let maxTextLength = 6000

    let url: URL

    static let standard = ChatHistoryStore(
        url: (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("ai-chat.json")
    )

    func load() -> [StoredChatMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Повреждённый файл не должен мешать открыть чат: переписка просто начинается заново
        guard let messages = try? decoder.decode([StoredChatMessage].self, from: data) else { return [] }
        return Self.trimmed(messages)
    }

    func save(_ messages: [StoredChatMessage]) {
        let kept = Self.trimmed(messages)
        guard !kept.isEmpty else {
            clear()
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(kept) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить переписку: \(error.localizedDescription)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Последние сообщения, длинные тексты обрезаны
    static func trimmed(_ messages: [StoredChatMessage]) -> [StoredChatMessage] {
        messages.suffix(maxMessages).map { message in
            var copy = message
            if copy.text.count > maxTextLength {
                copy.text = String(copy.text.prefix(maxTextLength))
            }
            return copy
        }
    }
}

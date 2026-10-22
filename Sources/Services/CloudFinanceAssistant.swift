import Foundation

/// Реплика переписки, которая уходит облачному ИИ как контекст
struct CloudTurn: Sendable {
    let isUser: Bool
    let text: String
}

/// Ответ облачного ИИ: текст для чата и операции для черновика
struct CloudReply {
    let text: String
    let operations: [ParsedSMSTransaction]
}

/// Ответ модели строго по JSON-схеме из запроса
private struct CloudEnvelope: Decodable {
    let reply: String
    let operations: [CloudOperation]
}

private struct CloudOperation: Decodable {
    let title: String
    let merchant: String?
    let amount: Double
    let currency: String
    let type: String
    let category: String
    let date: String?
    let cardLast4: String?
    let balanceAfter: Double?
    let isTransfer: Bool
    let counterparty: String?
}

/// Облачный ИИ-помощник на Claude, ChatGPT или Gemini (на выбор пользователя): отвечает на любые вопросы по данным пользователя
/// и находит операции в чеках, выписках, скриншотах и обычных фразах («купил кофе за 1500»).
/// Найденные операции не записываются сами: они приходят черновиком, который пользователь подтверждает.
@MainActor
enum CloudFinanceAssistant {
    private typealias JSON = [String: Any]

    /// Сколько последних реплик переписки отправлять как контекст
    private static let historyLimit = 12

    static func ask(
        _ question: String,
        images: [Data],
        recognizedText: String?,
        history: [CloudTurn],
        provider: AIProvider,
        apiKey: String
    ) async throws -> CloudReply {
        var prepared: [Data] = []
        for image in images {
            if let jpeg = await AIImages.prepared(image) {
                prepared.append(jpeg)
            }
        }

        let prompt = makePrompt(question: question, images: prepared, recognizedText: recognizedText, history: history)
        let schema = responseSchema()
        let text: String
        switch provider {
        case .claude:
            text = try await ClaudeAPI.send(body: ClaudeAPI.requestBody(prompt, schema: schema), apiKey: apiKey)
        case .openAI:
            text = try await OpenAIAPI.send(body: OpenAIAPI.requestBody(prompt, schema: schema), apiKey: apiKey)
        case .gemini:
            text = try await GeminiAPI.send(body: GeminiAPI.requestBody(prompt, schema: schema), apiKey: apiKey)
        }
        return try parse(text, provider: provider)
    }

    // MARK: - Запрос

    /// Запрос в общем виде: из него каждый сервис собирает своё тело запроса
    private static func makePrompt(question: String, images: [Data], recognizedText: String?, history: [CloudTurn]) -> AIPrompt {
        var turns = mergedHistory(history)

        // Если история кончается репликой пользователя, она идёт в ту же реплику, что и вопрос
        var leadingText: String? = nil
        if let last = turns.last, last.isUser {
            turns.removeLast()
            leadingText = last.text
        }
        var text = question
        if let recognizedText, !recognizedText.isEmpty {
            text += "\n\nТекст со скриншотов, распознанный на телефоне (может содержать ошибки):\n" + recognizedText
        }
        return AIPrompt(system: systemPrompt(), turns: turns, leadingText: leadingText, images: images, text: text)
    }

    /// Переписка должна начинаться с пользователя, а реплики одной стороны подряд склеиваются
    private static func mergedHistory(_ history: [CloudTurn]) -> [CloudTurn] {
        var result: [CloudTurn] = []
        for turn in history.suffix(historyLimit) {
            let text = String(turn.text.prefix(2000))
            if result.isEmpty && !turn.isUser { continue }
            if let last = result.last, last.isUser == turn.isUser {
                result[result.count - 1] = CloudTurn(isUser: turn.isUser, text: last.text + "\n\n" + text)
            } else {
                result.append(CloudTurn(isUser: turn.isUser, text: text))
            }
        }
        return result
    }

    private static func responseSchema() -> JSON {
        let categoryNames = Array(Set(FinanceService.shared.categories.map(\.name))).sorted()
        let nullableString: JSON = ["anyOf": [["type": "string"], ["type": "null"]]]
        let fields = ["title", "merchant", "amount", "currency", "type", "category", "date", "card_last4", "balance_after", "is_transfer", "counterparty"]

        let operation: JSON = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "merchant": nullableString,
                "amount": ["type": "number"],
                "currency": ["type": "string", "enum": AppCurrency.allCases.map(\.rawValue)] as JSON,
                "type": ["type": "string", "enum": ["expense", "income"]] as JSON,
                "category": ["type": "string", "enum": categoryNames] as JSON,
                "date": ["anyOf": [["type": "string", "format": "date-time"], ["type": "null"]]],
                "card_last4": nullableString,
                "balance_after": ["anyOf": [["type": "number"], ["type": "null"]]],
                "is_transfer": ["type": "boolean"],
                "counterparty": nullableString
            ] as JSON,
            "required": fields,
            "additionalProperties": false
        ]

        return [
            "type": "object",
            "properties": [
                "reply": ["type": "string"],
                "operations": ["type": "array", "items": operation] as JSON
            ] as JSON,
            "required": ["reply", "operations"],
            "additionalProperties": false
        ]
    }

    // MARK: - Подсказка и данные пользователя

    private static func systemPrompt() -> String {
        """
        Ты — помощник в приложении учёта личных финансов SamFinance. Отвечай по-русски, коротко и по делу, обычным текстом без Markdown; перечисления пиши строками, начинающимися с «• ».

        Считай только по данным пользователя ниже. Если данных не хватает, так и скажи и не придумывай суммы.

        Поле operations — операции, которые нужно записать в учёт. Заполняй его, когда пользователь присылает скриншот или текст банковской СМС, чека или выписки либо пишет о трате или доходе («купил кофе за 1500», «вчера пришла зарплата 400 000»). Каждая операция отдельно и без повторов. Не добавляй операции, о которых пользователь только спрашивает или рассуждает, операции, которые уже есть в списке последних операций ниже, а также отклонённые операции и сообщения о нехватке средств. Пользователь сам проверит черновик и подтвердит запись, поэтому в reply коротко перечисли, что нашёл. Если записывать нечего, operations — пустой массив.
        • amount — положительное число в валюте документа, currency — код этой валюты.
        • type — expense для трат и списаний, income для зачислений.
        • category — одна из категорий нужного типа из списка ниже.
        • date — дата и время операции в ISO 8601 с часовым поясом пользователя; «вчера», «в пятницу» отсчитывай от текущего времени; если даты нет — null.
        • card_last4 — последние 4 цифры карты из маски вида 4318***0640, иначе null.
        • balance_after — остаток на карте после операции, если он указан, иначе null.
        • is_transfer — true для переводов между картами (C2C, P2P); counterparty — имя отправителя или получателя перевода, иначе null.
        • merchant — магазин или организация, если есть, иначе null.
        • title — короткое название для списка: магазин, «Перевод от …», «Снятие наличных».

        Пользователь в основном получает СМС армянских банков (IDBank, ARCA и другие): первая строка — код операции (GNUM — покупка, E-POS GNUM — покупка в интернете, C2C — перевод, MUTQ — зачисление), затем сумма, маска карты, магазин, дата и остаток (MNACORD).

        \(financeContext())
        """
    }

    /// Сводка данных пользователя: карты, траты по категориям, последние операции и долги
    private static func financeContext() -> String {
        let financeService = FinanceService.shared
        let currency = CurrencyManager.shared
        let calendar = Calendar.current
        let now = Date()

        let timestamp = ISO8601DateFormatter()
        timestamp.timeZone = .current
        timestamp.formatOptions = [.withInternetDateTime]

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"

        var lines: [String] = []
        lines.append("Сейчас: \(timestamp.string(from: now)), часовой пояс \(TimeZone.current.identifier).")
        lines.append("Суммы ниже указаны в валюте отображения: \(currency.currentCurrency.rawValue).")

        let expenseNames = financeService.categories.filter { $0.type == .expense }.map(\.name)
        let incomeNames = financeService.categories.filter { $0.type == .income }.map(\.name)
        lines.append("Категории расходов: \(expenseNames.joined(separator: ", ")).")
        lines.append("Категории доходов: \(incomeNames.joined(separator: ", ")).")

        lines.append("")
        if financeService.cards.isEmpty {
            lines.append("Карт пока нет.")
        } else {
            lines.append("Карты (общий баланс \(currency.format(financeService.totalBalance))):")
            for card in financeService.cards {
                let frozen = card.isFrozen ? ", заморожена" : ""
                lines.append("• •••• \(card.last4) «\(card.type)» — \(currency.format(card.balance))\(frozen)")
            }
        }

        let monthStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let recent = financeService.transactions.filter { $0.date >= monthStart }
        let monthExpenses = recent.filter { $0.type == .expense }
        let monthIncome = recent.filter { $0.type == .income }.reduce(0.0) { $0 + $1.amount }
        var byCategory: [String: Double] = [:]
        for transaction in monthExpenses {
            byCategory[transaction.category.name, default: 0.0] += transaction.amount
        }

        lines.append("")
        lines.append("За 30 дней: расходы \(currency.format(monthExpenses.reduce(0.0) { $0 + $1.amount })), доходы \(currency.format(monthIncome)).")
        for entry in byCategory.sorted(by: { $0.value > $1.value }) {
            lines.append("• \(entry.key) — \(currency.format(entry.value))")
        }

        lines.append("")
        let latest = financeService.transactions.prefix(60)
        if latest.isEmpty {
            lines.append("Операций пока нет.")
        } else {
            lines.append("Последние операции (всего записано \(financeService.transactions.count)):")
            for transaction in latest {
                let sign = transaction.type == .income ? "+" : "−"
                var line = "• \(dateFormatter.string(from: transaction.date)) · \(sign)\(currency.format(transaction.amount)) · \(transaction.title) · \(transaction.category.name)"
                if let cardId = transaction.cardId, let card = financeService.cards.first(where: { $0.id == cardId }) {
                    line += " · карта \(card.last4)"
                }
                lines.append(line)
            }
        }

        let openDebts = financeService.debts.filter { !$0.isPaid }
        lines.append("")
        if openDebts.isEmpty {
            lines.append("Открытых долгов нет.")
        } else {
            lines.append("Открытые долги:")
            for debt in openDebts {
                let direction = debt.isLent ? "мне должны" : "я должен"
                let kind = debt.type == .credit ? "кредит" : "человек"
                lines.append("• \(debt.name) (\(kind)) — \(direction) \(currency.format(debt.amount)), срок \(dateFormatter.string(from: debt.dueDate))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Разбор ответа

    private static func parse(_ text: String, provider: AIProvider) throws -> CloudReply {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = withoutCodeFence(text).data(using: .utf8),
              let envelope = try? decoder.decode(CloudEnvelope.self, from: data) else {
            throw AIAPIError.badResponse(provider)
        }

        var seen = Set<String>()
        let operations = envelope.operations
            .compactMap { transaction(from: $0) }
            .filter { seen.insert($0.dedupKey).inserted }
        return CloudReply(text: envelope.reply, operations: operations)
    }

    /// Некоторые модели оборачивают JSON в блок кода ```json … ``` даже при заданной схеме
    private static func withoutCodeFence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("```") else { return result }
        if let newline = result.firstIndex(of: "\n") {
            result = String(result[result.index(after: newline)...])
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transaction(from operation: CloudOperation) -> ParsedSMSTransaction? {
        guard operation.amount > 0, operation.amount < 100_000_000 else { return nil }

        let date = operation.date.flatMap { parseDate($0) }
        let last4 = operation.cardLast4.flatMap { raw -> String? in
            let digits = raw.filter(\.isNumber)
            return digits.count == 4 ? digits : nil
        }
        let merchant = clean(operation.merchant)
        let counterparty = clean(operation.counterparty)
        // По этому имени запоминается категория: для перевода это получатель или отправитель
        let brand = merchant ?? (operation.isTransfer ? counterparty : nil)
        let title = operation.title.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedSMSTransaction(
            title: title.isEmpty ? (brand ?? "Операция") : title,
            amount: operation.amount,
            currency: AppCurrency(rawValue: operation.currency) ?? .amd,
            type: TransactionType(rawValue: operation.type) ?? .expense,
            brandName: brand,
            categoryName: operation.category,
            date: date,
            cardLast4: last4,
            balanceAfter: operation.balanceAfter,
            isTransfer: operation.isTransfer,
            counterparty: counterparty,
            isCategoryGuessed: false,
            dedupKey: SMSParser.dedupKey(last4: last4, amount: operation.amount, date: date, merchant: brand ?? title)
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Дата из ISO 8601; дата из будущего отбрасывается, и тогда операция запишется на момент сохранения
    private static func parseDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var parsed = formatter.date(from: raw)
        if parsed == nil {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            parsed = formatter.date(from: raw)
        }
        if parsed == nil {
            let local = DateFormatter()
            local.locale = Locale(identifier: "en_US_POSIX")
            local.timeZone = .current
            local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            parsed = local.date(from: raw)
        }
        guard let parsed, parsed <= Date().addingTimeInterval(24 * 60 * 60) else { return nil }
        return parsed
    }
}

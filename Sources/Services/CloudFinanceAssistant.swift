import Foundation

/// Реплика переписки, которая уходит облачному ИИ как контекст
struct CloudTurn: Sendable {
    let isUser: Bool
    let text: String
}

/// Ответ облачного ИИ: текст для чата, операции для черновика и предложенные изменения в приложении
struct CloudReply {
    let text: String
    let operations: [ParsedSMSTransaction]
    let actions: [AIAction]
}

/// Ответ модели строго по JSON-схеме из запроса
private struct CloudEnvelope: Decodable {
    let reply: String
    let operations: [CloudOperation]
    /// Отсутствует в ответах, где модель не знает о действиях
    let actions: [CloudAction]?
}

private struct CloudAction: Decodable {
    let kind: String
    let target: String?
    let name: String?
    let amount: Double?
    let currency: String?
    let date: String?
    let direction: String?
    let debtType: String?
    let billKind: String?
    let reminder: String?
    let repeatRule: String?
    let note: String?
    let category: String?
    let setting: String?
    let value: String?
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

    static func responseSchema() -> [String: Any] {
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
                "operations": ["type": "array", "items": operation] as JSON,
                "actions": ["type": "array", "items": actionSchema()] as JSON
            ] as JSON,
            "required": ["reply", "operations", "actions"],
            "additionalProperties": false
        ]
    }

    /// Одно предложение изменить приложение: плоский объект, поля «не нужно» заполняются null
    private static func actionSchema() -> JSON {
        func nullable(_ schema: JSON) -> JSON {
            ["anyOf": [schema, ["type": "null"]]]
        }
        func enumeration(_ values: [String]) -> JSON {
            ["type": "string", "enum": values]
        }

        let properties: JSON = [
            "kind": enumeration(AIAction.Kind.allCases.map(\.rawValue)),
            "target": nullable(["type": "string"]),
            "name": nullable(["type": "string"]),
            "amount": nullable(["type": "number"]),
            "currency": nullable(enumeration(AppCurrency.allCases.map(\.rawValue))),
            "date": nullable(["type": "string", "format": "date-time"]),
            "direction": nullable(enumeration(DebtSide.allCases.map(\.rawValue))),
            "debt_type": nullable(enumeration(DebtType.allCases.map(\.rawValue))),
            "bill_kind": nullable(enumeration(BillKind.allCases.map(\.rawValue))),
            "reminder": nullable(enumeration(DebtReminder.allCases.map(\.rawValue))),
            "repeat_rule": nullable(enumeration(ReminderRepeat.allCases.map(\.rawValue))),
            "note": nullable(["type": "string"]),
            "category": nullable(["type": "string"]),
            "setting": nullable(enumeration(AIAction.ReminderSetting.allCases.map(\.rawValue))),
            "value": nullable(["type": "string"])
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": properties.keys.sorted(),
            "additionalProperties": false
        ]
    }

    // MARK: - Подсказка и данные пользователя

    private static func systemPrompt() -> String {
        """
        Ты — помощник в приложении учёта личных финансов Hashiv. Отвечай на языке пользователя (\(AppLanguage.current.promptName)), коротко и по делу, обычным текстом без Markdown; перечисления пиши строками, начинающимися с «• ».

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

        Поле actions — изменения в приложении, о которых пользователь просит словами: «добавь долг…», «поставь напоминание на пятницу», «закрой долг Арама», «пополни копилку», «заморозь карту». Заполняй его только по прямой просьбе изменить данные или настройки, а не по вопросу или рассуждению. Пользователь увидит карточку со списком изменений и сам нажмёт «Применить», поэтому в reply одной-двумя фразами скажи, что предлагаешь. Если не хватает важного (срока долга, суммы, кто кому должен, даты и времени напоминания), не придумывай: спроси в reply, а actions оставь пустым. Не предлагай в одном ответе действие над тем, что создаётся в этом же ответе (например, пополнение новой копилки): это будет в следующем сообщении. Не повторяй то, что уже есть в списках ниже. Менять и удалять можно только то, что пользователь назвал. Если просьба не укладывается в виды действий, так и скажи в reply.
        Виды (kind) и нужные поля; остальные поля — null:
        • add_debt — name (имя человека, банка или название платежа), amount, currency, date (срок), direction (owedToMe — мне должны, iOwe — я должен; для кредита и платежа не нужен), debt_type (person — человек, credit — кредит, bill — регулярный платёж: коммуналка, интернет, телефон, аренда, подписка, страховка, налог), bill_kind (только для bill: utilities — коммуналка, internet, phone, rent, subscription, insurance, tax, other), repeat_rule (только для bill: monthly, если пользователь не сказал иначе; never — разовый платёж), reminder (off, onDueDay, dayBefore, threeDaysBefore, weekBefore; если пользователь не просил, null). У bill name можно оставить null: возьмётся название вида платежа. Платежи — это не долги: «оплати интернет» значит платёж, а не долг человеку.
        • change_debt — target и любые из name, amount, currency, date, reminder, а для платежа ещё bill_kind и repeat_rule.
        • mark_debt_paid, mark_debt_unpaid, delete_debt — target. Для повторяющегося платежа mark_debt_paid значит «оплатил в этот раз»: срок сам перейдёт на следующий период.
        • add_goal — name, amount (цель по сумме), currency, date (срок, если назван).
        • change_goal — target и любые из name, amount, currency, date.
        • deposit_goal, withdraw_goal — target, amount, currency.
        • delete_goal — target.
        • add_reminder — name (что напомнить), date (дата и время), repeat_rule (never, daily, weekly, monthly, yearly), note.
        • change_reminder — target и любые из name, date, repeat_rule, note. delete_reminder — target.
        • freeze_card, unfreeze_card — target (последние 4 цифры карты).
        • delete_transaction — target. set_transaction_category — target и category (из списка категорий нужного типа).
        • set_currency — value (AMD, RUB, USD или EUR).
        • set_reminder_setting — setting и value: для debts, goal_deadlines, card_expiry, daily_log значение «on» или «off»; для goal_saving — «off», «weekly» или «monthly»; для reminder_time и daily_log_time — «ЧЧ:ММ».
        target — номер из квадратных скобок в списках ниже ([d:…] долг, [g:…] копилка, [r:…] напоминание, [t:…] операция), для карты — последние 4 цифры. Номера копируй точно, не придумывай их; если номера нет, напиши название. Даты и время отсчитывай от текущего времени и пиши в ISO 8601 с часовым поясом пользователя; если у напоминания время не названо, возьми 10:00. Если валюта не названа, currency — null: сумма в валюте отображения.

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
                lines.append("• [c:\(card.last4)] «\(card.type)» — \(currency.format(card.balance))\(frozen)")
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
                var line = "• [t:\(AIActionExecutor.shortID(transaction.id))] \(dateFormatter.string(from: transaction.date)) · \(sign)\(currency.format(transaction.amount)) · \(transaction.title) · \(transaction.category.name)"
                if let cardId = transaction.cardId, let card = financeService.cards.first(where: { $0.id == cardId }) {
                    line += " · карта \(card.last4)"
                }
                lines.append(line)
            }
        }

        // Долги: сначала открытые, затем погашенные; номер нужен, чтобы изменить или закрыть долг
        let debts = financeService.debts.sorted { !$0.isPaid && $1.isPaid }.prefix(30)
        lines.append("")
        if debts.isEmpty {
            lines.append("Долгов нет.")
        } else {
            lines.append("Долги:")
            for debt in debts {
                let direction = debt.type == .bill ? "к оплате" : (debt.isLent ? "мне должны" : "я должен")
                let kind: String
                switch debt.type {
                case .credit: kind = "кредит"
                case .person: kind = "человек"
                case .bill: kind = "платёж: \((debt.billKind ?? .other).rawValue), повтор: \((debt.repeatRule ?? .never).rawValue)"
                }
                let status = debt.isPaid ? ", погашен" : ", напоминание: \(debt.effectiveReminder.rawValue)"
                lines.append("• [d:\(AIActionExecutor.shortID(debt.id))] \(debt.name) (\(kind)) — \(direction) \(currency.format(debt.amount)), срок \(dateFormatter.string(from: debt.dueDate))\(status)")
            }
        }

        lines.append("")
        if financeService.goals.isEmpty {
            lines.append("Копилок нет.")
        } else {
            lines.append("Копилки:")
            for goal in financeService.goals.prefix(20) {
                var line = "• [g:\(AIActionExecutor.shortID(goal.id))] «\(goal.title)» — накоплено \(currency.format(goal.currentAmount)) из \(currency.format(goal.targetAmount))"
                if let deadline = goal.deadline {
                    line += ", срок \(dateFormatter.string(from: deadline))"
                }
                lines.append(line)
            }
        }

        lines.append("")
        if financeService.customReminders.isEmpty {
            lines.append("Своих напоминаний нет.")
        } else {
            lines.append("Свои напоминания:")
            for reminder in financeService.customReminders.prefix(20) {
                lines.append("• [r:\(AIActionExecutor.shortID(reminder.id))] «\(reminder.title)» — \(dateFormatter.string(from: reminder.date)), повтор: \(reminder.repeatRule.rawValue)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Разбор ответа

    static func parse(_ text: String, provider: AIProvider) throws -> CloudReply {
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
        let actions = (envelope.actions ?? []).compactMap { action(from: $0) }
        return CloudReply(text: envelope.reply, operations: operations, actions: actions)
    }

    /// Предложение модели в виде, который понимает исполнитель; неизвестный вид действия отбрасывается
    private static func action(from raw: CloudAction) -> AIAction? {
        guard let kind = AIAction.Kind(rawValue: raw.kind) else { return nil }
        return AIAction(
            kind: kind,
            target: clean(raw.target),
            name: clean(raw.name),
            amount: raw.amount,
            currency: raw.currency.flatMap { AppCurrency(rawValue: $0.uppercased()) },
            date: raw.date.flatMap { parseISO($0) },
            direction: raw.direction.flatMap { DebtSide(rawValue: $0) },
            debtType: raw.debtType.flatMap { DebtType(rawValue: $0) },
            billKind: raw.billKind.flatMap { BillKind(rawValue: $0) },
            reminder: raw.reminder.flatMap { DebtReminder(rawValue: $0) },
            repeatRule: raw.repeatRule.flatMap { ReminderRepeat(rawValue: $0) },
            note: clean(raw.note),
            category: clean(raw.category),
            setting: raw.setting.flatMap { AIAction.ReminderSetting(rawValue: $0) },
            value: clean(raw.value)
        )
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
            title: title.isEmpty ? (brand ?? String(localized: "Операция")) : title,
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

    /// Дата из ISO 8601 с часовым поясом, без часового пояса или только день
    static func parseISO(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: raw) {
            return parsed
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let parsed = local.date(from: raw) {
                return parsed
            }
        }
        return nil
    }

    /// Дата операции: дата из будущего отбрасывается, и тогда операция запишется на момент сохранения
    private static func parseDate(_ raw: String) -> Date? {
        guard let parsed = parseISO(raw), parsed <= Date().addingTimeInterval(24 * 60 * 60) else { return nil }
        return parsed
    }
}

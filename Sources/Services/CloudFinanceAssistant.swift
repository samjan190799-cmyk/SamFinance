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
    /// Запросы к данным на телефоне. Если они есть, текст ответа — заглушка до результатов, и показывать его не нужно
    var queries: [DataQuery] = []
}

/// Ответ модели строго по JSON-схеме из запроса
private struct CloudEnvelope: Decodable {
    let reply: String
    let operations: [CloudOperation]
    /// Отсутствует в ответах, где модель не знает о действиях
    let actions: [CloudAction]?
    /// Отсутствует в ответах, где модель не знает о запросах к данным
    let queries: [CloudQuery]?
}

/// Запрос модели к данным пользователя. Пустая строка, none и 0 означают «не задано»: так схема обходится без null.
private struct CloudQuery: Decodable {
    let kind: String
    let type: String?
    let dateFrom: String?
    let dateTo: String?
    let category: String?
    let merchant: String?
    let cardLast4: String?
    let groupBy: String?
    let sort: String?
    /// Целые числа читаются как дробные: ответ с «5.0» не должен ломать весь разбор
    let limit: Double?
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
    /// Целые числа читаются как дробные: ответ с «2.5» не должен ломать весь разбор
    let interval: Double?
    let variableAmount: Bool?
    let monthlyPayment: Double?
    let interestRate: Double?
    let paymentsLeft: Double?
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

        var prompt = makePrompt(question: question, images: prepared, recognizedText: recognizedText, history: history)
        let schema = responseSchema()

        // Модель может попросить данные, которых нет в подсказке (другой период, фильтр). Приложение их считает
        // и присылает следующим сообщением; так повторяется не больше `maxQueryRounds` раз, дальше нужен ответ.
        var rounds = 0
        while true {
            let reply = try await send(prompt, schema: schema, provider: provider, apiKey: apiKey)
            guard !reply.queries.isEmpty else { return reply }

            // Заглушка «Считаю…» вместо ответа пользователю не показывается
            guard rounds < maxQueryRounds else {
                return CloudReply(
                    text: String(localized: "Не получилось посчитать это за несколько запросов. Уточните период или условие."),
                    operations: [],
                    actions: []
                )
            }
            rounds += 1
            try Task.checkCancellation()
            prompt = followUp(after: prompt, reply: reply, results: results(for: reply.queries), isLast: rounds == maxQueryRounds)
        }
    }

    /// Один обмен с выбранным сервисом: запрос по общей схеме и разбор ответа
    private static func send(_ prompt: AIPrompt, schema: [String: Any], provider: AIProvider, apiKey: String) async throws -> CloudReply {
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

    // MARK: - Запросы к данным

    /// Сколько раз модель может попросить данные после первого ответа
    private static let maxQueryRounds = 2
    /// Сколько запросов выполняется за один раз; лишние отбрасываются
    private static let maxQueriesPerRound = 4
    /// Длинный ответ режется: он уходит в облако и не должен раздувать запрос
    private static let maxResultsLength = 6000

    /// Дата в тексте для модели: день, месяц, год
    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }

    /// Выполняет запросы модели по данным на телефоне и собирает результаты в один текст
    private static func results(for queries: [DataQuery]) -> String {
        let financeService = FinanceService.shared
        let currency = CurrencyManager.shared
        let formatter = dayFormatter()

        var blocks: [String] = []
        for (index, query) in queries.prefix(maxQueriesPerRound).enumerated() {
            let result = DataQueryEngine.run(query, transactions: financeService.transactions, cards: financeService.cards)
            blocks.append(DataQueryEngine.render(
                result,
                number: index + 1,
                money: { currency.format($0) },
                date: { formatter.string(from: $0) }
            ))
        }
        return String(blocks.joined(separator: "\n\n").prefix(maxResultsLength))
    }

    /// Продолжение переписки с результатами запросов: вопрос, затем то, что запросила модель, затем данные
    static func followUp(after prompt: AIPrompt, reply: CloudReply, results: String, isLast: Bool) -> AIPrompt {
        let formatter = dayFormatter()
        let question = [prompt.leadingText, prompt.text].compactMap { $0 }.joined(separator: "\n\n")
        let requested = reply.queries
            .map { query in DataQueryEngine.describe(query, date: { formatter.string(from: $0) }) }
            .joined(separator: "; ")

        var turns = prompt.turns
        turns.append(CloudTurn(isUser: true, text: question))
        turns.append(CloudTurn(isUser: false, text: "Запросил данные: \(requested)"))

        let ending = isLast
            ? "Новых запросов больше нет: queries — пустой массив."
            : "Если данных всё ещё не хватает, можно запросить ещё, иначе queries — пустой массив."
        let text = """
        Результаты запросов к данным на телефоне (суммы в валюте отображения):
        \(results)

        Ответь пользователю на его вопрос по этим данным, коротко и без Markdown. Операции и действия заполняй, только если пользователь просил что-то записать или изменить. \(ending)
        """
        // Скриншоты уже разобраны на первом шаге, повторно они не нужны
        return AIPrompt(system: prompt.system, turns: turns, leadingText: nil, images: [], text: text)
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
                "actions": ["type": "array", "items": actionSchema()] as JSON,
                "queries": ["type": "array", "items": querySchema()] as JSON
            ] as JSON,
            "required": ["reply", "operations", "actions", "queries"],
            "additionalProperties": false
        ]
    }

    /// Один запрос к данным на телефоне: плоский объект без null. Пустая строка, none и 0 означают «не задано».
    private static func querySchema() -> JSON {
        func enumeration(_ values: [String]) -> JSON {
            ["type": "string", "enum": values]
        }

        let properties: JSON = [
            "kind": enumeration(DataQuery.Kind.allCases.map(\.rawValue)),
            "type": enumeration(TransactionType.allCases.map(\.rawValue)),
            "date_from": ["type": "string"] as JSON,
            "date_to": ["type": "string"] as JSON,
            "category": ["type": "string"] as JSON,
            "merchant": ["type": "string"] as JSON,
            "card_last4": ["type": "string"] as JSON,
            "group_by": enumeration(["none"] + DataQuery.GroupBy.allCases.map(\.rawValue)),
            "sort": enumeration(DataQuery.Sort.allCases.map(\.rawValue)),
            "limit": ["type": "integer"] as JSON
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": properties.keys.sorted(),
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
            "value": nullable(["type": "string"]),
            "interval": nullable(["type": "integer"]),
            "variable_amount": nullable(["type": "boolean"]),
            "monthly_payment": nullable(["type": "number"]),
            "interest_rate": nullable(["type": "number"]),
            "payments_left": nullable(["type": "integer"])
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
        • add_debt — name (имя человека, банка или название платежа), amount, currency, date (срок), direction (owedToMe — мне должны, iOwe — я должен; для кредита и платежа не нужен), debt_type (person — человек, credit — кредит, bill — регулярный платёж: коммуналка, интернет, телефон, аренда, подписка, страховка, налог), bill_kind (только для bill: utilities — коммуналка, internet, phone, rent, subscription, insurance, tax, other), repeat_rule (только для bill: monthly, если пользователь не сказал иначе; never — разовый платёж), reminder (off, onDueDay, dayBefore, threeDaysBefore, weekBefore; если пользователь не просил, null). У bill name можно оставить null: возьмётся название вида платежа. Платежи — это не долги: «оплати интернет» значит платёж, а не долг человеку. Дополнительно: note — заметка; для bill — interval (каждые N периодов: 3 при repeat_rule monthly значит раз в квартал) и variable_amount (true, если сумма каждый раз другая, как у коммуналки); для кредита — monthly_payment (платёж в месяц, в валюте currency), interest_rate (годовая ставка в процентах) и payments_left (сколько платежей осталось), а date тогда — ближайший платёж. Чего пользователь не назвал, оставляй null: подставятся его настройки для этого вида записей.
        • change_debt — target и любые из name, amount, currency, date, reminder, note, а для платежа ещё bill_kind, repeat_rule, interval, variable_amount, а для кредита monthly_payment, interest_rate, payments_left.
        • mark_debt_paid, mark_debt_unpaid, delete_debt — target. Для повторяющегося платежа mark_debt_paid значит «оплатил в этот раз»: срок сам перейдёт на следующий период. В mark_debt_paid можно указать amount (и currency): сколько вышло по платежу, сколько внесли по кредиту в этом месяце или какую часть долга вернули — остаток уменьшится. Без amount долг или платёж закрывается целиком.
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

        Поле queries — запросы к данным на телефоне. В списках ниже только последние 30 дней, 60 операций и итоги по ним. Если для ответа нужен другой период, фильтр (категория, магазин, карта) или точный итог («сколько я потратил в сентябре», «на кофе за полгода», «самая крупная покупка в этом году», «сравни октябрь и ноябрь»), не считай по памяти и не угадывай: верни queries (не больше 4), reply оставь коротким («Считаю…»), а operations и actions пустыми. Приложение выполнит запросы и пришлёт результаты следующим сообщением, после чего ответь по ним. Если данных в списках достаточно, queries — пустой массив.
        Виды (kind):
        • sum — итог: сумма, число операций, среднее и самая крупная операция.
        • breakdown — разбивка по group_by (category, merchant, month, week, day, card): сумма и число операций по каждой группе. limit — сколько групп (0 — по умолчанию: 10, а для month, week и day все).
        • list — список операций. sort: newest (сначала новые) или largest (сначала крупные); limit — до 25 (0 — 10).
        Условия: type — expense (траты) или income (доходы); date_from и date_to — даты ГГГГ-ММ-ДД, включительно (от текущей даты считай «этот месяц», «прошлый год», «последние 3 месяца»); category — название из списка категорий выше; merchant — часть названия магазина или получателя; card_last4 — последние 4 цифры карты. Незаданное условие: пустая строка, для group_by — none, для limit — 0. Для сравнения периодов пришли по одному sum на каждый период. После результатов можно запросить ещё, но не больше двух раз; потом отвечай. Суммы в результатах — в той же валюте отображения, что и в списках.

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
            let typeSettings = DebtTypeSettings.load()
            for debt in debts {
                let direction = debt.type == .bill ? "к оплате" : (debt.isLent ? "мне должны" : "я должен")
                var kind: String
                switch debt.type {
                case .credit:
                    kind = "кредит"
                    if let payment = debt.monthlyPayment {
                        kind += ", платёж в месяц \(currency.format(payment))"
                    }
                    if let rate = debt.interestRate {
                        kind += ", ставка \(GoalQuickAmounts.plain(rate))%"
                    }
                    if let left = debt.paymentsLeft {
                        kind += ", осталось платежей \(left)"
                    }
                case .person: kind = "человек"
                case .bill:
                    kind = "платёж: \((debt.billKind ?? .other).rawValue), повтор: \(debt.effectiveRepeat.rawValue)"
                    if debt.effectiveInterval > 1 {
                        kind += ", каждые \(debt.effectiveInterval)"
                    }
                    if debt.isVariableAmount == true {
                        kind += ", сумма меняется"
                    }
                }
                if debt.hasPartialPayments, let original = debt.originalAmount {
                    kind += ", было \(currency.format(original))"
                }
                let status = debt.isPaid ? ", погашен" : ", напоминание: \(debt.effectiveReminder(using: typeSettings).rawValue)"
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
        let queries = (envelope.queries ?? []).compactMap { query(from: $0) }
        return CloudReply(text: envelope.reply, operations: operations, actions: actions, queries: queries)
    }

    /// Запрос модели в виде, который понимает движок; неизвестный вид запроса отбрасывается
    private static func query(from raw: CloudQuery) -> DataQuery? {
        guard let kind = DataQuery.Kind(rawValue: raw.kind) else { return nil }
        var query = DataQuery(kind: kind)
        query.type = raw.type.flatMap { TransactionType(rawValue: $0) } ?? .expense
        query.from = raw.dateFrom.flatMap { parseISO($0) }
        query.to = raw.dateTo.flatMap { endOfPeriod($0) }
        query.category = clean(raw.category)
        query.merchant = clean(raw.merchant)
        query.cardLast4 = raw.cardLast4.flatMap { value -> String? in
            let digits = value.filter(\.isNumber)
            return digits.count == 4 ? digits : nil
        }
        query.groupBy = raw.groupBy.flatMap { DataQuery.GroupBy(rawValue: $0) }
        query.sort = raw.sort.flatMap { DataQuery.Sort(rawValue: $0) }
        query.limit = wholeNumber(raw.limit)
        return query
    }

    /// Конец периода: если названа только дата, то это конец того дня, иначе названный момент
    private static func endOfPeriod(_ raw: String) -> Date? {
        guard let date = parseISO(raw) else { return nil }
        guard raw.trimmingCharacters(in: .whitespacesAndNewlines).count <= 10 else { return date }
        let calendar = Calendar.current
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: date)) ?? date
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
            value: clean(raw.value),
            interval: wholeNumber(raw.interval),
            variableAmount: raw.variableAmount,
            monthlyPayment: raw.monthlyPayment,
            interestRate: raw.interestRate,
            paymentsLeft: wholeNumber(raw.paymentsLeft)
        )
    }

    /// Целое число из ответа модели; нечисло и слишком большие значения отбрасываются
    private static func wholeNumber(_ value: Double?) -> Int? {
        guard let value, value.isFinite, abs(value) < 100_000 else { return nil }
        return Int(value.rounded())
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

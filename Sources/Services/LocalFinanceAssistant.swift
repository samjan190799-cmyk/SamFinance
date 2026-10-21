import Foundation

/// Ответы ИИ-чата на вопросы о деньгах. Считает по данным на телефоне, без сети:
/// траты по категории и периоду, доходы, баланс карт, долги и советы.
@MainActor
enum LocalFinanceAssistant {

    static func answer(_ question: String, financeService: FinanceService) -> String {
        let text = question.lowercased()
        let period = period(in: text)

        if containsAny(text, ["баланс", "сколько денег", "на картах", "на карте", "остаток"]) {
            return balanceAnswer(financeService)
        }
        if containsAny(text, ["долг", "должен", "должна", "должны", "одолжил", "занял"]) {
            return debtsAnswer(financeService)
        }
        if containsAny(text, ["совет", "анализ", "рекоменд", "сэконом", "экономить"]) {
            return adviceAnswer(financeService)
        }
        if containsAny(text, ["доход", "заработ", "получил", "зарплат", "пришло"]) {
            return incomeAnswer(period: period, financeService: financeService)
        }
        if let category = category(in: text, financeService: financeService) {
            return categoryAnswer(category, period: period, financeService: financeService)
        }
        if containsAny(text, ["потрат", "расход", "трат", "ушло", "сколько"]) {
            return spendingAnswer(period: period, financeService: financeService)
        }
        return helpText
    }

    static let helpText = """
    Пока я понимаю скриншоты и тексты банковских СМС и такие вопросы:
    • сколько я потратил за неделю?
    • сколько ушло на продукты за месяц?
    • какой у меня баланс?
    • кому я должен?
    • дай совет
    Чтобы я отвечал на любые вопросы и разбирал чеки и выписки, добавьте ключ Claude: кнопка с ключом вверху или Настройки → ИИ-помощник.
    """

    // MARK: - Разбор вопроса

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    /// Период из вопроса; если не назван, считаем за 30 дней
    private static func period(in text: String) -> TimePeriodFilter {
        if text.contains("сегодня") { return .today }
        if text.contains("недел") { return .week }
        if containsAny(text, ["всё время", "все время", "за всё", "за все", "всего"]) { return .allTime }
        return .month
    }

    private static func phrase(for period: TimePeriodFilter) -> String {
        switch period {
        case .today: return "Сегодня"
        case .week: return "За неделю"
        case .month: return "За 30 дней"
        case .allTime: return "За всё время"
        }
    }

    /// Слова, по которым узнаём встроенные категории расходов
    private static let categoryWords: [String: [String]] = [
        "Продукты": ["продукт", "супермаркет", "магазин"],
        "Транспорт": ["транспорт", "такси", "бензин", "топлив", "метро", "машин"],
        "Рестораны": ["ресторан", "кафе", "кофе", "обед", "ужин", "доставк"],
        "Жилье": ["жиль", "квартир", "аренд", "коммунал", "интернет", "связь"],
        "Развлечения": ["развлеч", "кино", "игр", "подписк"],
        "Здоровье": ["здоров", "аптек", "врач", "лекарств"],
        "Переводы": ["перевод"],
        "Прочее": ["прочее", "прочие"]
    ]

    private static func category(in text: String, financeService: FinanceService) -> Category? {
        let expenses = financeService.categories.filter { $0.type == .expense }
        for category in expenses {
            if let words = categoryWords[category.name], containsAny(text, words) {
                return category
            }
        }
        // Свои категории узнаём по началу названия
        return expenses.first { category in
            let stem = String(category.name.lowercased().prefix(5))
            return stem.count >= 4 && text.contains(stem)
        }
    }

    // MARK: - Ответы

    private static func expenses(in period: TimePeriodFilter, financeService: FinanceService) -> [Transaction] {
        financeService.transactions.filter { $0.type == .expense && period.contains($0.date) }
    }

    private static func format(_ amount: Double) -> String {
        CurrencyManager.shared.format(amount)
    }

    private static func categoryAnswer(_ category: Category, period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = expenses(in: period, financeService: financeService).filter { $0.category.name == category.name }
        guard !items.isEmpty else {
            return "\(phrase(for: period)) трат в категории «\(category.name)» нет."
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        var answer = "\(phrase(for: period)) на «\(category.name)» ушло \(format(total)) — операций: \(items.count)."

        var byMerchant: [String: Int] = [:]
        for item in items {
            byMerchant[item.brandName ?? item.title, default: 0] += 1
        }
        if let top = byMerchant.max(by: { $0.value < $1.value }), top.value > 1 {
            answer += " Чаще всего: \(top.key) (\(top.value))."
        }
        return answer
    }

    private static func spendingAnswer(period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = expenses(in: period, financeService: financeService)
        guard !items.isEmpty else {
            return "\(phrase(for: period)) трат нет."
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        var answer = "\(phrase(for: period)) потрачено \(format(total))."

        var byCategory: [String: Double] = [:]
        for item in items {
            byCategory[item.category.name, default: 0.0] += item.amount
        }
        let top = byCategory.sorted { $0.value > $1.value }.prefix(3)
        answer += "\nБольше всего:"
        for entry in top {
            answer += "\n• \(entry.key) — \(format(entry.value))"
        }

        let days: Double
        switch period {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        case .allTime: days = 0
        }
        if days > 1 {
            answer += "\nВ среднем \(format(total / days)) в день."
        }
        return answer
    }

    private static func incomeAnswer(period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = financeService.transactions.filter { $0.type == .income && period.contains($0.date) }
        guard !items.isEmpty else {
            return "\(phrase(for: period)) поступлений нет."
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        return "\(phrase(for: period)) получено \(format(total)) — поступлений: \(items.count)."
    }

    private static func balanceAnswer(_ financeService: FinanceService) -> String {
        let cards = financeService.cards
        guard !cards.isEmpty else {
            return "Карт пока нет. Пришлите скриншот СМС банка — карта добавится сама, а баланс возьмётся из остатка."
        }
        var answer = "На картах \(format(financeService.totalBalance)):"
        for card in cards {
            let frozen = card.isFrozen ? " (заморожена, не считается)" : ""
            answer += "\n• •••• \(card.last4) — \(format(card.balance))\(frozen)"
        }
        return answer
    }

    private static func debtsAnswer(_ financeService: FinanceService) -> String {
        let open = financeService.debts.filter { !$0.isPaid }
        guard !open.isEmpty else {
            return "Открытых долгов нет."
        }
        let lent = open.filter(\.isLent)
        let borrowed = open.filter { !$0.isLent }
        var answer = "Мне должны: \(format(lent.reduce(0.0) { $0 + $1.amount })). Я должен: \(format(borrowed.reduce(0.0) { $0 + $1.amount }))."

        if let nearest = open.min(by: { $0.dueDate < $1.dueDate }) {
            let who = nearest.isLent ? "\(nearest.name) должен вам" : "вы должны \(nearest.name)"
            answer += "\nБлижайший срок: \(nearest.dueDate.formatted(.dateTime.day().month(.wide))) — \(who) \(format(nearest.amount))."
        }
        return answer
    }

    private static func adviceAnswer(_ financeService: FinanceService) -> String {
        AIService.shared.generateInsights(financeService: financeService)
            .map { "• \($0.title). \($0.message)" }
            .joined(separator: "\n")
    }
}

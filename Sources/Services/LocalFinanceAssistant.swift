import Foundation

/// Ответы ИИ-чата на вопросы о деньгах. Считает по данным на телефоне, без сети:
/// траты по категории и периоду, доходы, баланс карт, долги и советы.
/// Вопрос понимается на русском, английском и армянском независимо от языка интерфейса; ответ — на языке интерфейса.
@MainActor
enum LocalFinanceAssistant {

    static func answer(_ question: String, financeService: FinanceService) -> String {
        let text = question.lowercased()
        let period = period(in: text)

        if containsAny(text, Words.balance) {
            return balanceAnswer(financeService)
        }
        if containsAny(text, Words.debts) {
            return debtsAnswer(financeService)
        }
        if containsAny(text, Words.advice) {
            return adviceAnswer(financeService)
        }
        if containsAny(text, Words.income) {
            return incomeAnswer(period: period, financeService: financeService)
        }
        if let category = category(in: text, financeService: financeService) {
            return categoryAnswer(category, period: period, financeService: financeService)
        }
        if containsAny(text, Words.spending) {
            return spendingAnswer(period: period, financeService: financeService)
        }
        return helpText
    }

    static var helpText: String {
        String(localized: "Пока я понимаю скриншоты и тексты банковских СМС и такие вопросы:\n• сколько я потратил за неделю?\n• сколько ушло на продукты за месяц?\n• какой у меня баланс?\n• кому я должен?\n• дай совет\nЧтобы я отвечал на любые вопросы и разбирал чеки и выписки, добавьте ключ Claude, ChatGPT или Gemini: кнопка с ключом вверху или Настройки → ИИ-помощник.")
    }

    // MARK: - Слова из вопроса (корни слов: русский, английский, армянский)

    private enum Words {
        static let balance = [
            "баланс", "сколько денег", "на картах", "на карте", "остаток",
            "balance", "how much money", "money do i have", "on my cards", "on the card",
            "հաշվեկշիռ", "մնացորդ", "որքան գումար", "քարտերի վրա", "քարտի վրա"
        ]
        static let debts = [
            "долг", "должен", "должна", "должны", "одолжил", "занял",
            "debt", "owe", "borrow", "lent", "loan",
            "պարտք", "վարկ"
        ]
        static let advice = [
            "совет", "анализ", "рекоменд", "сэконом", "экономить",
            "advice", "tip", "analy", "recommend", "saving",
            "խորհուրդ", "վերլուծ", "խնայ"
        ]
        static let income = [
            "доход", "заработ", "получил", "зарплат", "пришло",
            "income", "earn", "received", "salary", "got paid",
            "եկամուտ", "ստացել", "աշխատավարձ", "վաստակ"
        ]
        static let spending = [
            "потрат", "расход", "трат", "ушло", "сколько",
            "spent", "spend", "expens", "how much", "cost",
            "ծախս", "գնացել", "որքան"
        ]
        static let today = ["сегодня", "today", "այսօր"]
        static let week = ["недел", "week", "շաբաթ"]
        static let allTime = [
            "всё время", "все время", "за всё", "за все", "всего",
            "all time", "ever", "in total",
            "ողջ ժամանակ", "ամբողջ ժամանակ"
        ]
    }

    private static func containsAny(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    /// Период из вопроса; если не назван, считаем за 30 дней
    private static func period(in text: String) -> TimePeriodFilter {
        if containsAny(text, Words.today) { return .today }
        if containsAny(text, Words.week) { return .week }
        if containsAny(text, Words.allTime) { return .allTime }
        return .month
    }

    private static func phrase(for period: TimePeriodFilter) -> String {
        switch period {
        case .today: return String(localized: "Сегодня")
        case .week: return String(localized: "За неделю")
        case .month: return String(localized: "За 30 дней")
        case .allTime: return String(localized: "За всё время")
        }
    }

    /// Слова, по которым узнаём встроенные категории расходов (по их русским названиям)
    private static let categoryWords: [String: [String]] = [
        "Продукты": ["продукт", "супермаркет", "магазин", "grocer", "supermarket", "store", "մթերք", "սուպերմարկետ", "խանութ"],
        "Транспорт": ["транспорт", "такси", "бензин", "топлив", "метро", "машин", "transport", "taxi", "fuel", "petrol", "gas", "metro", "տրանսպորտ", "տաքսի", "վառելիք", "բենզին", "մետրո", "մեքենա"],
        "Рестораны": ["ресторан", "кафе", "кофе", "обед", "ужин", "доставк", "restaurant", "cafe", "coffee", "lunch", "dinner", "delivery", "ռեստորան", "սրճարան", "սուրճ", "ճաշ", "ընթրիք", "առաքում"],
        "Жилье": ["жиль", "квартир", "аренд", "коммунал", "интернет", "связь", "housing", "rent", "utilit", "apartment", "internet", "phone bill", "բնակարան", "վարձ", "կոմունալ", "ինտերնետ"],
        "Развлечения": ["развлеч", "кино", "игр", "подписк", "entertain", "movie", "cinema", "game", "subscription", "ժամանց", "կինո", "խաղ", "բաժանորդագր"],
        "Здоровье": ["здоров", "аптек", "врач", "лекарств", "health", "pharmac", "doctor", "medic", "առողջ", "դեղատուն", "բժիշկ", "դեղ"],
        "Переводы": ["перевод", "transfer", "փոխանցում"],
        "Прочее": ["прочее", "прочие", "other", "misc", "այլ"]
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
        let label = phrase(for: period)
        guard !items.isEmpty else {
            return String(localized: "\(label): трат в категории «\(category.displayName)» нет.")
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        var answer = String(localized: "\(label): на «\(category.displayName)» ушло \(format(total)) — операций: \(items.count).")

        var byMerchant: [String: Int] = [:]
        for item in items {
            byMerchant[item.brandName ?? item.title, default: 0] += 1
        }
        if let top = byMerchant.max(by: { $0.value < $1.value }), top.value > 1 {
            answer += " " + String(localized: "Чаще всего: \(top.key) (\(top.value)).")
        }
        return answer
    }

    private static func spendingAnswer(period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = expenses(in: period, financeService: financeService)
        let label = phrase(for: period)
        guard !items.isEmpty else {
            return String(localized: "\(label): трат нет.")
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        var answer = String(localized: "\(label): потрачено \(format(total)).")

        var byCategory: [String: Double] = [:]
        for item in items {
            byCategory[item.category.name, default: 0.0] += item.amount
        }
        let top = byCategory.sorted { $0.value > $1.value }.prefix(3)
        answer += "\n" + String(localized: "Больше всего:")
        for entry in top {
            answer += "\n• \(Category.displayName(for: entry.key)) — \(format(entry.value))"
        }

        let days: Double
        switch period {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        case .allTime: days = 0
        }
        if days > 1 {
            answer += "\n" + String(localized: "В среднем \(format(total / days)) в день.")
        }
        return answer
    }

    private static func incomeAnswer(period: TimePeriodFilter, financeService: FinanceService) -> String {
        let items = financeService.transactions.filter { $0.type == .income && period.contains($0.date) }
        let label = phrase(for: period)
        guard !items.isEmpty else {
            return String(localized: "\(label): поступлений нет.")
        }
        let total = items.reduce(0.0) { $0 + $1.amount }
        return String(localized: "\(label): получено \(format(total)) — поступлений: \(items.count).")
    }

    private static func balanceAnswer(_ financeService: FinanceService) -> String {
        let cards = financeService.cards
        guard !cards.isEmpty else {
            return String(localized: "Карт пока нет. Пришлите скриншот СМС банка — карта добавится сама, а баланс возьмётся из остатка.")
        }
        var answer = String(localized: "На картах \(format(financeService.totalBalance)):")
        for card in cards {
            let frozen = card.isFrozen ? " " + String(localized: "(заморожена, не считается)") : ""
            answer += "\n• •••• \(card.last4) — \(format(card.balance))\(frozen)"
        }
        return answer
    }

    private static func debtsAnswer(_ financeService: FinanceService) -> String {
        let open = financeService.debts.filter { !$0.isPaid }
        guard !open.isEmpty else {
            return String(localized: "Открытых долгов нет.")
        }
        let lent = open.filter(\.isLent)
        let borrowed = open.filter { !$0.isLent }
        let owedToMe = format(lent.reduce(0.0) { $0 + $1.amount })
        let iOwe = format(borrowed.reduce(0.0) { $0 + $1.amount })
        var answer = String(localized: "Мне должны: \(owedToMe). Я должен: \(iOwe).")

        if let nearest = open.min(by: { $0.dueDate < $1.dueDate }) {
            let date = nearest.dueDate.formatted(.dateTime.day().month(.wide))
            let amount = format(nearest.amount)
            if nearest.isLent {
                answer += "\n" + String(localized: "Ближайший срок: \(date) — \(nearest.name) должен вам \(amount).")
            } else {
                answer += "\n" + String(localized: "Ближайший срок: \(date) — вы должны \(nearest.name): \(amount).")
            }
        }
        return answer
    }

    private static func adviceAnswer(_ financeService: FinanceService) -> String {
        AIService.shared.generateInsights(financeService: financeService)
            .map { "• \($0.title). \($0.message)" }
            .joined(separator: "\n")
    }
}

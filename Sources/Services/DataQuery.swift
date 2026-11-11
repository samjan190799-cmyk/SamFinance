import Foundation

/// Запрос ИИ-помощника к данным пользователя.
/// В подсказке модель видит только последние 30 дней и 60 операций; за остальным она обращается сюда:
/// «сколько я потратил в сентябре», «на кофе за полгода», «самая крупная покупка в этом году».
/// Считает приложение, а не модель, поэтому цифры точные, а в облако уходят только итоги, а не вся история.
struct DataQuery: Sendable, Equatable {
    enum Kind: String, CaseIterable, Sendable {
        /// Итог: сумма, число операций, среднее и самая крупная
        case sum
        /// Разбивка по группам: категория, магазин, месяц, неделя, день или карта
        case breakdown
        /// Список операций
        case list
    }

    enum GroupBy: String, CaseIterable, Sendable {
        case category
        case merchant
        case month
        case week
        case day
        case card

        /// По времени группы идут по порядку дат, остальные — по убыванию суммы
        var isChronological: Bool {
            switch self {
            case .month, .week, .day: return true
            case .category, .merchant, .card: return false
            }
        }
    }

    enum Sort: String, CaseIterable, Sendable {
        case newest
        case largest
    }

    var kind: Kind
    /// Траты или доходы; без указания — траты
    var type: TransactionType = .expense
    /// Границы включительно; без границы — с начала или до конца истории
    var from: Date?
    var to: Date?
    /// Название категории: как в списке категорий или как показано на экране
    var category: String?
    /// Часть названия магазина или получателя
    var merchant: String?
    var cardLast4: String?
    var groupBy: GroupBy?
    var sort: Sort?
    var limit: Int?
}

/// Ответ на запрос в виде чисел, а не текста: так его проверяют тесты
struct DataQueryResult: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        let date: Date
        let amount: Double
        let title: String
        let category: String
        let cardLast4: String?
    }

    struct Group: Sendable, Equatable {
        let name: String
        let total: Double
        let count: Int
    }

    let query: DataQuery
    /// Сколько операций подошло под условия; в списке и разбивке может быть показана только часть
    var count = 0
    var total = 0.0
    var largest: Line?
    var groups: [Group] = []
    /// Сколько групп получилось всего
    var groupCount = 0
    var lines: [Line] = []
}

/// Считает ответы на запросы по списку операций. Не знает ни про сеть, ни про экран.
enum DataQueryEngine {
    static let defaultLines = 10
    static let maxLines = 25
    static let defaultGroups = 10
    static let maxGroups = 40

    static func run(_ query: DataQuery, transactions: [Transaction], cards: [Card], calendar: Calendar = .current) -> DataQueryResult {
        var query = query
        // Границы, названные наоборот, меняются местами, а не дают пустой ответ
        if let from = query.from, let to = query.to, from > to {
            query.from = to
            query.to = from
        }

        let last4ByCard = Dictionary(cards.map { ($0.id, $0.last4) }, uniquingKeysWith: { first, _ in first })
        let matched = transactions.filter { matches($0, query: query, last4ByCard: last4ByCard) }

        var result = DataQueryResult(query: query)
        result.count = matched.count
        result.total = matched.reduce(0.0) { $0 + $1.amount }
        if let biggest = matched.max(by: { $0.amount < $1.amount }) {
            result.largest = line(biggest, last4ByCard: last4ByCard)
        }

        switch query.kind {
        case .sum:
            break
        case .breakdown:
            let groupBy = query.groupBy ?? .category
            let all = groups(of: matched, by: groupBy, last4ByCard: last4ByCard, calendar: calendar)
            let limit = clamped(query.limit, fallback: groupBy.isChronological ? maxGroups : defaultGroups, maximum: maxGroups)
            result.groupCount = all.count
            // По времени оставляем самые поздние группы, по остальным — самые крупные
            result.groups = groupBy.isChronological ? Array(all.suffix(limit)) : Array(all.prefix(limit))
        case .list:
            let limit = clamped(query.limit, fallback: defaultLines, maximum: maxLines)
            let ordered: [Transaction]
            switch query.sort ?? .newest {
            case .newest: ordered = matched.sorted { $0.date > $1.date }
            case .largest: ordered = matched.sorted { $0.amount > $1.amount }
            }
            result.lines = ordered.prefix(limit).map { line($0, last4ByCard: last4ByCard) }
        }
        return result
    }

    // MARK: - Отбор

    private static func matches(_ transaction: Transaction, query: DataQuery, last4ByCard: [UUID: String]) -> Bool {
        guard transaction.type == query.type else { return false }
        if let from = query.from, transaction.date < from { return false }
        if let to = query.to, transaction.date > to { return false }

        if let category = query.category {
            let sameName = transaction.category.name.caseInsensitiveCompare(category) == .orderedSame
            let sameTitle = transaction.category.displayName.caseInsensitiveCompare(category) == .orderedSame
            if !sameName && !sameTitle { return false }
        }

        if let merchant = query.merchant {
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            let inTitle = transaction.title.range(of: merchant, options: options) != nil
            let inBrand = transaction.brandName?.range(of: merchant, options: options) != nil
            if !inTitle && !inBrand { return false }
        }

        if let last4 = query.cardLast4 {
            guard let cardID = transaction.cardId, last4ByCard[cardID] == last4 else { return false }
        }
        return true
    }

    private static func clamped(_ limit: Int?, fallback: Int, maximum: Int) -> Int {
        guard let limit, limit > 0 else { return fallback }
        return min(limit, maximum)
    }

    private static func line(_ transaction: Transaction, last4ByCard: [UUID: String]) -> DataQueryResult.Line {
        DataQueryResult.Line(
            date: transaction.date,
            amount: transaction.amount,
            title: transaction.title,
            category: transaction.category.displayName,
            cardLast4: transaction.cardId.flatMap { last4ByCard[$0] }
        )
    }

    // MARK: - Группы

    private struct Accumulator {
        var total = 0.0
        var count = 0
    }

    private static func groups(of matched: [Transaction], by groupBy: DataQuery.GroupBy, last4ByCard: [UUID: String], calendar: Calendar) -> [DataQueryResult.Group] {
        // Один форматтер на весь запрос: создавать его на каждую операцию дорого
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var totals: [String: Accumulator] = [:]
        for transaction in matched {
            let key = groupName(for: transaction, by: groupBy, last4ByCard: last4ByCard, calendar: calendar, formatter: formatter)
            var current = totals[key] ?? Accumulator()
            current.total += transaction.amount
            current.count += 1
            totals[key] = current
        }

        let groups = totals.map { DataQueryResult.Group(name: $0.key, total: $0.value.total, count: $0.value.count) }
        if groupBy.isChronological {
            // Названия вида 2026-09 и 2026-09-15 по алфавиту идут в порядке дат
            return groups.sorted { $0.name < $1.name }
        }
        return groups.sorted { lhs, rhs in
            lhs.total != rhs.total ? lhs.total > rhs.total : lhs.name < rhs.name
        }
    }

    private static func groupName(for transaction: Transaction, by groupBy: DataQuery.GroupBy, last4ByCard: [UUID: String], calendar: Calendar, formatter: DateFormatter) -> String {
        switch groupBy {
        case .category:
            return transaction.category.displayName
        case .merchant:
            let brand = transaction.brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return brand.isEmpty ? transaction.title : brand
        case .card:
            return transaction.cardId.flatMap { last4ByCard[$0] } ?? "без карты"
        case .month:
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: transaction.date)
        case .week:
            // Неделя называется по её первому дню
            formatter.dateFormat = "yyyy-MM-dd"
            let start = calendar.dateInterval(of: .weekOfYear, for: transaction.date)?.start ?? transaction.date
            return formatter.string(from: start)
        case .day:
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: transaction.date)
        }
    }

    // MARK: - Текст для модели

    /// Условия запроса словами
    static func describe(_ query: DataQuery, date: (Date) -> String) -> String {
        var parts = [query.type == .income ? "доходы" : "расходы"]
        switch (query.from, query.to) {
        case let (from?, to?): parts.append("с \(date(from)) по \(date(to))")
        case let (from?, nil): parts.append("с \(date(from))")
        case let (nil, to?): parts.append("по \(date(to))")
        case (nil, nil): parts.append("за всё время")
        }
        if let category = query.category { parts.append("категория «\(category)»") }
        if let merchant = query.merchant { parts.append("магазин или получатель «\(merchant)»") }
        if let last4 = query.cardLast4 { parts.append("карта \(last4)") }
        return parts.joined(separator: ", ")
    }

    /// Ответ на запрос в виде текста, который читает модель. Суммы переводит в нужную валюту и форматирует `money`.
    static func render(_ result: DataQueryResult, number: Int, money: (Double) -> String, date: (Date) -> String) -> String {
        let query = result.query
        let header = "[\(number)] \(describe(query, date: date))"
        guard result.count > 0 else {
            return "\(header): операций нет"
        }

        switch query.kind {
        case .sum:
            let average = result.total / Double(result.count)
            var text = "\(header): итого \(money(result.total)), операций \(result.count), в среднем \(money(average))"
            if let largest = result.largest {
                text += ", самая крупная \(money(largest.amount)) (\(largest.title), \(date(largest.date)))"
            }
            return text

        case .breakdown:
            let groupBy = query.groupBy ?? .category
            var lines = ["\(header): итого \(money(result.total)), операций \(result.count). Разбивка (\(groupBy.rawValue)):"]
            for group in result.groups {
                var line = "  • \(group.name) — \(money(group.total)), операций \(group.count)"
                if !groupBy.isChronological, result.total > 0 {
                    line += ", \(Int((group.total / result.total * 100).rounded()))%"
                }
                lines.append(line)
            }
            if result.groupCount > result.groups.count {
                lines.append("  … всего групп \(result.groupCount), показаны \(result.groups.count)")
            }
            return lines.joined(separator: "\n")

        case .list:
            var lines = ["\(header): найдено операций \(result.count), показаны \(result.lines.count), итого \(money(result.total)):"]
            let sign = query.type == .income ? "+" : "−"
            for item in result.lines {
                var line = "  • \(date(item.date)) · \(sign)\(money(item.amount)) · \(item.title) · \(item.category)"
                if let last4 = item.cardLast4 {
                    line += " · карта \(last4)"
                }
                lines.append(line)
            }
            return lines.joined(separator: "\n")
        }
    }
}

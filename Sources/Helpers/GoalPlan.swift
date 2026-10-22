import Foundation

public extension Goal {
    /// Накоплена вся сумма цели
    var isCompleted: Bool {
        targetAmount > 0 && currentAmount >= targetAmount
    }
}

/// Где копилка относительно цели и срока: сколько осталось, сколько откладывать и когда цель будет достигнута
public struct GoalPlan: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case completed
        case onTrack
        case behind
        case overdue
        case noDeadline
    }

    public let saved: Double
    public let target: Double
    public let remaining: Double
    /// Сколько накоплено сверх цели
    public let overflow: Double
    /// Доля цели от 0 до 1
    public let progress: Double
    public let status: Status
    /// Дней до срока; nil, если срока нет
    public let daysLeft: Int?
    /// Сколько откладывать в неделю или в месяц, чтобы успеть к сроку
    public let perWeek: Double?
    public let perMonth: Double?
    /// Когда цель будет достигнута, если копить в прежнем темпе; nil, если темп неизвестен
    public let forecastDate: Date?

    /// Темп считается по последним 60 дням, но не меньше чем за 14: одно крупное пополнение не должно давать нереальный прогноз
    private static let paceWindow = 60
    private static let minimumPaceWindow = 14
    private static let averageMonth = 30.4375

    public init(goal: Goal, now: Date = Date(), calendar: Calendar = .current) {
        let target = max(goal.targetAmount, 0)
        let saved = max(goal.currentAmount, 0)
        let isDone = target > 0 && saved >= target
        let remaining = max(target - saved, 0)
        let progress = target > 0 ? min(saved / target, 1) : 0

        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: goal.createdAt ?? goal.entries.map { $0.date }.min() ?? now)
        let end = goal.deadline.map { calendar.startOfDay(for: $0) }
        let days = end.flatMap { calendar.dateComponents([.day], from: today, to: $0).day }

        var status = Status.noDeadline
        var perWeek: Double?
        var perMonth: Double?
        if isDone {
            status = .completed
        } else if let days, let end {
            if days < 0 {
                status = .overdue
            } else {
                let span = Double(max(days, 1))
                perWeek = remaining / max(span / 7, 1)
                perMonth = remaining / max(span / GoalPlan.averageMonth, 1)

                // Сравниваем с прямой «по графику»: к середине срока должна быть накоплена половина
                let totalDays = calendar.dateComponents([.day], from: startDay, to: end).day ?? 0
                let elapsed = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
                let ideal = totalDays > 0 ? min(max(Double(elapsed) / Double(totalDays), 0), 1) : 1
                status = progress + 0.05 >= ideal ? .onTrack : .behind
            }
        }

        var forecast: Date?
        if !isDone {
            let earliest = calendar.date(byAdding: .day, value: -GoalPlan.paceWindow, to: today) ?? startDay
            let windowStart = max(startDay, earliest)
            let observed = calendar.dateComponents([.day], from: windowStart, to: today).day ?? 0
            let windowDays = max(observed, GoalPlan.minimumPaceWindow)
            let net = goal.entries
                .filter { $0.date >= windowStart && $0.date <= now }
                .reduce(0.0) { $0 + $1.amount }
            if net > 0 {
                let daysToGo = (remaining / (net / Double(windowDays))).rounded(.up)
                if daysToGo.isFinite, daysToGo <= 3_650 {
                    forecast = calendar.date(byAdding: .day, value: Int(daysToGo), to: today)
                }
            }
        }

        self.saved = saved
        self.target = target
        self.remaining = remaining
        self.overflow = max(saved - target, 0)
        self.progress = progress
        self.status = status
        self.daysLeft = days.map { max($0, 0) }
        self.perWeek = perWeek
        self.perMonth = perMonth
        self.forecastDate = forecast
    }
}

/// Итоги по всем копилкам и порядок их показа
public struct SavingsSummary: Equatable, Sendable {
    /// Сколько отложено во всех копилках
    public let totalSaved: Double
    public let activeSaved: Double
    public let activeTarget: Double
    public let activeCount: Int
    public let completedCount: Int

    /// Общая доля цели по незавершённым копилкам
    public var progress: Double {
        activeTarget > 0 ? min(activeSaved / activeTarget, 1) : 0
    }

    public init(goals: [Goal]) {
        var totalSaved = 0.0
        var activeSaved = 0.0
        var activeTarget = 0.0
        var activeCount = 0
        var completedCount = 0
        for goal in goals {
            let saved = max(goal.currentAmount, 0)
            totalSaved += saved
            if goal.isCompleted {
                completedCount += 1
            } else {
                activeSaved += saved
                activeTarget += max(goal.targetAmount, 0)
                activeCount += 1
            }
        }
        self.totalSaved = totalSaved
        self.activeSaved = activeSaved
        self.activeTarget = activeTarget
        self.activeCount = activeCount
        self.completedCount = completedCount
    }

    /// Сколько денег карты отложено в копилках
    public static func reserved(on cardID: UUID, in goals: [Goal]) -> Double {
        goals.filter { $0.cardId == cardID }.reduce(0.0) { $0 + max($1.currentAmount, 0) }
    }

    /// Незавершённые копилки: сначала с ближайшим сроком, затем без срока, новые выше
    public static func sortedActive(_ goals: [Goal]) -> [Goal] {
        goals.filter { !$0.isCompleted }.sorted { lhs, rhs in
            switch (lhs.deadline, rhs.deadline) {
            case let (first?, second?):
                return first < second
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
        }
    }

    /// Достигнутые копилки: недавно закрытые выше
    public static func completed(_ goals: [Goal]) -> [Goal] {
        goals.filter { $0.isCompleted }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}

/// Значки, которые можно поставить копилке (SF Symbols)
public enum GoalSymbol {
    public static let all = [
        "shield.fill", "beach.umbrella.fill", "airplane", "house.fill", "car.fill", "iphone",
        "gift.fill", "graduationcap.fill", "heart.fill", "camera.fill", "banknote.fill", "star.fill"
    ]

    /// Значок по умолчанию: для старых копилок без значка
    public static let fallback = "banknote.fill"

    public static func title(_ name: String?) -> String {
        switch name {
        case "shield.fill": return String(localized: "Подушка безопасности")
        case "beach.umbrella.fill": return String(localized: "Отпуск")
        case "airplane": return String(localized: "Путешествие")
        case "house.fill": return String(localized: "Дом")
        case "car.fill": return String(localized: "Машина")
        case "iphone": return String(localized: "Техника")
        case "gift.fill": return String(localized: "Подарок")
        case "graduationcap.fill": return String(localized: "Учёба")
        case "heart.fill": return String(localized: "Здоровье")
        case "camera.fill": return String(localized: "Хобби")
        case "banknote.fill": return String(localized: "Накопления")
        case "star.fill": return String(localized: "Мечта")
        default: return String(localized: "Без значка")
        }
    }
}

/// Готовая идея для новой копилки: название, значок и цвет подставляются сами
public struct GoalIdea: Identifiable, Hashable, Sendable {
    public let id: String
    public let symbol: String
    public let presetID: String

    public var title: String {
        switch id {
        case "reserve": return String(localized: "Подушка безопасности")
        case "vacation": return String(localized: "Отпуск")
        case "phone": return String(localized: "Новый телефон")
        case "car": return String(localized: "Машина")
        default: return String(localized: "Подарок")
        }
    }

    /// Цвета цветовой схемы карты, на которую похожа идея
    public var colors: [String] {
        (CardPreset.all.first { $0.id == presetID } ?? CardPreset.all[0]).colors
    }

    public static let all: [GoalIdea] = [
        GoalIdea(id: "reserve", symbol: "shield.fill", presetID: "ocean"),
        GoalIdea(id: "vacation", symbol: "beach.umbrella.fill", presetID: "sunset"),
        GoalIdea(id: "phone", symbol: "iphone", presetID: "violet"),
        GoalIdea(id: "car", symbol: "car.fill", presetID: "slate"),
        GoalIdea(id: "gift", symbol: "gift.fill", presetID: "rose")
    ]
}

/// Быстрые суммы для пополнения и снятия: доли цели, округлённые до двух значащих цифр
public enum GoalQuickAmounts {
    /// 137 500 → 140 000, 4 800 → 4 800
    public static func rounded(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        let magnitude = pow(10, floor(log10(value)) - 1)
        return (value / magnitude).rounded() * magnitude
    }

    /// Сумма для поля ввода: «5000» или «12.50»
    public static func plain(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    /// Сумма с пробелами между разрядами: «120 000»
    public static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? plain(value)
    }

    /// Сумма из поля ввода: запятая считается точкой; пустое или нечисловое значение даёт nil
    public static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    public static func deposit(target: Double, remaining: Double) -> [Double] {
        let shares = [0.1, 0.25, 0.5].map { rounded(target * $0) }
        return unique(shares).filter { $0 > 0 && (remaining <= 0 || $0 < remaining) }
    }

    public static func withdraw(current: Double) -> [Double] {
        let shares = [0.25, 0.5].map { rounded(current * $0) }
        return unique(shares).filter { $0 > 0 && $0 < current }
    }

    private static func unique(_ values: [Double]) -> [Double] {
        var seen = Set<Double>()
        return values.filter { seen.insert($0).inserted }
    }
}

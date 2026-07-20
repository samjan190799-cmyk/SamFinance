import Foundation

/// Тип транзакции: доход или расход
public enum TransactionType: String, Codable, Sendable, CaseIterable {
    case income = "income"
    case expense = "expense"
}

/// Категория транзакции
public struct Category: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let icon: String // Имя системной иконки SF Symbols
    public let colorHex: String // Hex-код цвета для отображения
    public let type: TransactionType
    
    public init(id: UUID = UUID(), name: String, icon: String, colorHex: String, type: TransactionType) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
    }
    
    /// Предопределенный список категорий по умолчанию
    public static let defaultCategories: [Category] = [
        Category(name: "Зарплата", icon: "briefcase.fill", colorHex: "#34C759", type: .income),
        Category(name: "Фриланс", icon: "laptopcomputer", colorHex: "#007AFF", type: .income),
        Category(name: "Инвестиции", icon: "chart.line.uptrend.xyaxis", colorHex: "#AF52DE", type: .income),
        Category(name: "Продукты", icon: "cart.fill", colorHex: "#FF9500", type: .expense),
        Category(name: "Транспорт", icon: "car.fill", colorHex: "#5AC8FA", type: .expense),
        Category(name: "Рестораны", icon: "fork.knife", colorHex: "#FF2D55", type: .expense),
        Category(name: "Жилье", icon: "house.fill", colorHex: "#5E5CE6", type: .expense),
        Category(name: "Развлечения", icon: "gamecontroller.fill", colorHex: "#FFCC00", type: .expense),
        Category(name: "Здоровье", icon: "heart.text.square.fill", colorHex: "#FF3B30", type: .expense)
    ]
}

/// Банковская карта пользователя
public struct Card: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var number: String // Например, "7642"
    public var holderName: String
    public var balance: Double
    public var type: String // "Digital card"
    public var colorHex: String // Основной цвет свечения
    public var gradientColors: [String] // Цвета для градиентного фона
    public var isFrozen: Bool
    
    public init(id: UUID = UUID(), number: String, holderName: String, balance: Double, type: String = "Digital card", colorHex: String, gradientColors: [String], isFrozen: Bool = false) {
        self.id = id
        self.number = number
        self.holderName = holderName
        self.balance = balance
        self.type = type
        self.colorHex = colorHex
        self.gradientColors = gradientColors
        self.isFrozen = isFrozen
    }
}

/// Тип долга: кредит организации или долг физическому лицу
public enum DebtType: String, Codable, Sendable {
    case credit = "credit"
    case person = "person"
}

/// Долг (взаиморасчеты с контактами или кредиты банкам)
public struct Debt: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String // Имя человека или банка
    public var amount: Double
    public var dueDate: Date
    public var isLent: Bool // true - мне должны (Lent), false - я должен (Borrowed)
    public var isPaid: Bool // Статус погашения
    public var type: DebtType
    
    public init(id: UUID = UUID(), name: String, amount: Double, dueDate: Date = Date(), isLent: Bool, isPaid: Bool = false, type: DebtType = .person) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.isLent = isLent
        self.isPaid = isPaid
        self.type = type
    }
}

/// Накопительная цель (Копилка)
public struct Goal: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String // Название цели (например, "На автомобиль")
    public var targetAmount: Double // Целевая сумма
    public var currentAmount: Double // Накоплено на данный момент
    public var colorHex: String // Цвет свечения
    public var gradientColors: [String] // Цвета градиента карточки цели
    
    public init(id: UUID = UUID(), title: String, targetAmount: Double, currentAmount: Double = 0.0, colorHex: String, gradientColors: [String]) {
        self.id = id
        self.title = title
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.colorHex = colorHex
        self.gradientColors = gradientColors
    }
}

/// Модель финансовой транзакции
public struct Transaction: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var amount: Double
    public var type: TransactionType
    public var category: Category
    public var date: Date
    public var notes: String?
    
    // Брендирование транзакции под новый дизайн
    public var brandName: String? // Например, "Apple"
    public var brandIcon: String? // Системная иконка или логотип (для простоты системная иконка)
    public var brandColorHex: String? // Цвет точки индикатора рядом с логотипом
    
    public init(id: UUID = UUID(), title: String, amount: Double, type: TransactionType, category: Category, date: Date = Date(), notes: String? = nil, brandName: String? = nil, brandIcon: String? = nil, brandColorHex: String? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.date = date
        self.notes = notes
        self.brandName = brandName
        self.brandIcon = brandIcon
        self.brandColorHex = brandColorHex
    }
}

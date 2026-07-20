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

/// Модель финансовой транзакции
public struct Transaction: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var amount: Double
    public var type: TransactionType
    public var category: Category
    public var date: Date
    public var notes: String?
    
    public init(id: UUID = UUID(), title: String, amount: Double, type: TransactionType, category: Category, date: Date = Date(), notes: String? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.date = date
        self.notes = notes
    }
}

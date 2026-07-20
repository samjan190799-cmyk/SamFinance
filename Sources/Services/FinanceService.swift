import Foundation
import Observation

/// Менеджер данных финансов. Управляет списком транзакций и банковскими картами.
/// Реализован на Swift 6 `@Observable` с изоляцией на `@MainActor`.
@Observable
@MainActor
public final class FinanceService {
    public private(set) var transactions: [Transaction] = []
    public private(set) var cards: [Card] = []
    public private(set) var categories: [Category] = Category.defaultCategories
    
    private let fileURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("transactions.json")
    }()
    
    private let cardsURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("cards.json")
    }()
    
    public init() {
        loadData()
        if cards.isEmpty {
            createDemoCards()
        }
        if transactions.isEmpty {
            createDemoData()
        }
    }
    
    // MARK: - Публичный интерфейс для транзакций
    
    /// Добавление транзакции
    public func addTransaction(_ transaction: Transaction) {
        transactions.insert(transaction, at: 0)
        saveData()
    }
    
    /// Удаление транзакции
    public func deleteTransaction(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        saveData()
    }
    
    /// Удаление по свайпу в списке
    public func deleteTransactions(at offsets: IndexSet) {
        transactions.remove(atOffsets: offsets)
        saveData()
    }
    
    // MARK: - Публичный интерфейс для карт
    
    /// Заморозка / Разморозка карты
    public func toggleFreezeCard(id: UUID) {
        if let index = cards.firstIndex(where: { $0.id == id }) {
            cards[index].isFrozen.toggle()
            saveCards()
        }
    }
    
    /// Добавление новой карты
    public func addCard(_ card: Card) {
        cards.append(card)
        saveCards()
    }
    
    // MARK: - Подсчеты и вычисления (в долларах для дизайна)
    
    /// Общий текущий баланс
    public var totalBalance: Double {
        totalIncome - totalExpenses
    }
    
    /// Суммарный доход
    public var totalIncome: Double {
        transactions
            .filter { $0.type == .income }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Суммарный расход
    public var totalExpenses: Double {
        transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Суммарные расходы (для блока Spending на главном экране)
    public var totalSpending: Double {
        // Считаем сумму всех расходов без учета стартового баланса
        transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Группировка расходов по категориям
    public var expenseByCategory: [Category: Double] {
        var result: [Category: Double] = [:]
        for t in transactions where t.type == .expense {
            result[t.category, default: 0.0] += t.amount
        }
        return result
    }
    
    // MARK: - Сохранение и загрузка
    
    private func loadData() {
        // Загрузка транзакций
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                self.transactions = try decoder.decode([Transaction].self, from: data)
            } catch {
                print("⚠️ Не удалось загрузить транзакции: \(error.localizedDescription)")
            }
        }
        
        // Загрузка карт
        if FileManager.default.fileExists(atPath: cardsURL.path) {
            do {
                let data = try Data(contentsOf: cardsURL)
                let decoder = JSONDecoder()
                self.cards = try decoder.decode([Card].self, from: data)
            } catch {
                print("⚠️ Не удалось загрузить карты: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveData() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(transactions)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить транзакции: \(error.localizedDescription)")
        }
    }
    
    private func saveCards() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cards)
            try data.write(to: cardsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить карты: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Создание демо-данных
    
    private func createDemoCards() {
        self.cards = [
            Card(
                number: "7642",
                holderName: "Samvel",
                balance: 3500.0,
                colorHex: "#FFD200", // Ярко-желтый
                gradientColors: ["#FFE259", "#FFA751"]
            ),
            Card(
                number: "5123",
                holderName: "Samvel",
                balance: 2854.43,
                colorHex: "#00F2FE", // Бирюзовый
                gradientColors: ["#00F2FE", "#4FACFE"]
            ),
            Card(
                number: "3413",
                holderName: "Samvel",
                balance: 1500.0,
                colorHex: "#007AFF", // Синий
                gradientColors: ["#00C6FF", "#0072FF"]
            )
        ]
        saveCards()
    }
    
    private func createDemoData() {
        let calendar = Calendar.current
        let now = Date()
        
        let entertainment = categories.first { $0.name == "Развлечения" } ?? categories[7]
        let salary = categories.first { $0.name == "Зарплата" } ?? categories[0]
        let health = categories.first { $0.name == "Здоровье" } ?? categories[8]
        let housing = categories.first { $0.name == "Жилье" } ?? categories[6]
        
        // Подберем транзакции так, чтобы расходы составляли ровно $1,385,
        // а итоговый баланс (Доходы - Расходы) был ровно $7,854.43, как на скриншоте 2.
        // Расходы: Apple (-60), Threads (-300), Exoplan (-20), Oodle (-140), AWS (-865). Итого расходы = 1385.0
        // Доходы: Apple (+2000), Старт (+7239.43). Итого доходы = 9239.43
        // Баланс: 9239.43 - 1385.0 = 7854.43
        
        let demo = [
            Transaction(
                title: "Apple",
                amount: 60.0,
                type: .expense,
                category: entertainment,
                date: now,
                brandName: "Apple",
                brandIcon: "apple.logo",
                brandColorHex: "#00F2FE"
            ),
            Transaction(
                title: "Threads",
                amount: 300.0,
                type: .expense,
                category: entertainment,
                date: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
                brandName: "Threads",
                brandIcon: "at",
                brandColorHex: "#FFD200"
            ),
            Transaction(
                title: "Apple",
                amount: 2000.0,
                type: .income,
                category: salary,
                date: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                brandName: "Apple",
                brandIcon: "apple.logo",
                brandColorHex: "#007AFF"
            ),
            Transaction(
                title: "Exoplan",
                amount: 20.0,
                type: .expense,
                category: health,
                date: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                brandName: "Exoplan",
                brandIcon: "calendar",
                brandColorHex: "#34C759"
            ),
            Transaction(
                title: "Oodle",
                amount: 140.0,
                type: .expense,
                category: entertainment,
                date: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                brandName: "Oodle",
                brandIcon: "circle.grid.cross",
                brandColorHex: "#FF9500"
            ),
            Transaction(
                title: "AWS Cloud",
                amount: 865.0,
                type: .expense,
                category: housing,
                date: calendar.date(byAdding: .day, value: -4, to: now) ?? now,
                brandName: "AWS Cloud",
                brandIcon: "cloud.fill",
                brandColorHex: "#FF9500"
            ),
            Transaction(
                title: "Начальный капитал",
                amount: 7239.43,
                type: .income,
                category: salary,
                date: calendar.date(byAdding: .day, value: -10, to: now) ?? now,
                brandName: "Начальный капитал",
                brandIcon: "dollarsign.circle.fill",
                brandColorHex: "#34C759"
            )
        ]
        
        self.transactions = demo
        saveData()
    }
}

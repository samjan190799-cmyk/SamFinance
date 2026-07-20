import Foundation
import Observation

/// Менеджер данных финансов. Управляет списком транзакций,
/// подсчитывает баланс, доходы/расходы и сохраняет данные в файл.
/// Реализован на Swift 6 `@Observable` с изоляцией на `@MainActor`.
@Observable
@MainActor
public final class FinanceService {
    public private(set) var transactions: [Transaction] = []
    public private(set) var categories: [Category] = Category.defaultCategories
    
    private let fileURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("transactions.json")
    }()
    
    public init() {
        loadData()
        if transactions.isEmpty {
            createDemoData()
        }
    }
    
    // MARK: - Публичный интерфейс
    
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
    
    // MARK: - Подсчеты и вычисления
    
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.transactions = try decoder.decode([Transaction].self, from: data)
        } catch {
            print("⚠️ Не удалось загрузить транзакции: \(error.localizedDescription)")
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
    
    // MARK: - Демо-данные
    
    private func createDemoData() {
        let calendar = Calendar.current
        let now = Date()
        
        let demo = [
            Transaction(
                title: "Заработная плата",
                amount: 150000.0,
                type: .income,
                category: categories.first { $0.name == "Зарплата" } ?? categories[0],
                date: calendar.date(byAdding: .day, value: -5, to: now) ?? now
            ),
            Transaction(
                title: "Покупка продуктов",
                amount: 4500.0,
                type: .expense,
                category: categories.first { $0.name == "Продукты" } ?? categories[3],
                date: calendar.date(byAdding: .day, value: -4, to: now) ?? now
            ),
            Transaction(
                title: "Оплата подписки",
                amount: 890.0,
                type: .expense,
                category: categories.first { $0.name == "Развлечения" } ?? categories[7],
                date: calendar.date(byAdding: .day, value: -3, to: now) ?? now
            ),
            Transaction(
                title: "Проект на фрилансе",
                amount: 45000.0,
                type: .income,
                category: categories.first { $0.name == "Фриланс" } ?? categories[1],
                date: calendar.date(byAdding: .day, value: -2, to: now) ?? now
            ),
            Transaction(
                title: "Аренда квартиры",
                amount: 40000.0,
                type: .expense,
                category: categories.first { $0.name == "Жилье" } ?? categories[6],
                date: calendar.date(byAdding: .day, value: -1, to: now) ?? now
            ),
            Transaction(
                title: "Ужин в ресторане",
                amount: 3200.0,
                type: .expense,
                category: categories.first { $0.name == "Рестораны" } ?? categories[5],
                date: now
            )
        ]
        
        self.transactions = demo
        saveData()
    }
}

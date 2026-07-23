import Foundation
import Observation

/// Менеджер данных финансов. Управляет картами, транзакциями, долгами и копилками.
/// Данные сохраняются локально в JSON-файлы. Демо-данные удалены для чистого старта.
@Observable
@MainActor
public final class FinanceService {
    @MainActor public static let shared = FinanceService()
    
    public private(set) var transactions: [Transaction] = []
    public private(set) var cards: [Card] = []
    public private(set) var debts: [Debt] = []
    public private(set) var goals: [Goal] = []
    public private(set) var categories: [Category] = Category.defaultCategories
    
    // Пути к файлам сохранения в песочнице
    private let fileURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("transactions.json")
    }()
    
    private let cardsURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("cards.json")
    }()
    
    private let debtsURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("debts.json")
    }()
    
    private let goalsURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("goals.json")
    }()
    
    public init() {
        loadData()
        // Демо-информация полностью удалена при инициализации.
        // Приложение запускается полностью чистым.
    }
    
    // MARK: - API для транзакций
    
    public func addTransaction(_ transaction: Transaction) {
        transactions.insert(transaction, at: 0)
        
        // Автоматически корректируем баланс карт, если транзакция привязана к счету (дополнительная логика)
        saveData()
    }
    
    public func deleteTransaction(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        saveData()
    }
    
    public func deleteTransactions(at offsets: IndexSet) {
        transactions.remove(atOffsets: offsets)
        saveData()
    }
    
    // MARK: - API для карт
    
    public func toggleFreezeCard(id: UUID) {
        if let index = cards.firstIndex(where: { $0.id == id }) {
            cards[index].isFrozen.toggle()
            saveCards()
        }
    }
    
    public func addCard(_ card: Card) {
        cards.append(card)
        saveCards()
    }
    
    public func deleteCard(id: UUID) {
        cards.removeAll { $0.id == id }
        saveCards()
    }
    
    // MARK: - API для долгов (Debts)
    
    public func addDebt(_ debt: Debt) {
        debts.insert(debt, at: 0)
        saveDebts()
    }
    
    public func togglePayDebt(id: UUID) {
        if let index = debts.firstIndex(where: { $0.id == id }) {
            debts[index].isPaid.toggle()
            saveDebts()
        }
    }
    
    public func deleteDebt(id: UUID) {
        debts.removeAll { $0.id == id }
        saveDebts()
    }
    
    // MARK: - API для копилок (Goals)
    
    public func addGoal(_ goal: Goal) {
        goals.append(goal)
        saveGoals()
    }
    
    public func goalsForCard(cardId: UUID) -> [Goal] {
        goals.filter { $0.cardId == cardId }
    }
    
    public func addFundsToGoal(id: UUID, amount: Double) {
        if let index = goals.firstIndex(where: { $0.id == id }) {
            goals[index].currentAmount += amount
            saveGoals()
        }
    }
    
    public func deleteGoal(id: UUID) {
        goals.removeAll { $0.id == id }
        saveGoals()
    }
    
    // MARK: - Подсчеты и вычисления
    
    /// Общий текущий баланс (сумма всех активных балансов карт)
    public var totalBalance: Double {
        cards
            .filter { !$0.isFrozen }
            .reduce(0.0) { $0 + $1.balance }
    }
    
    /// Суммарный доход (по транзакциям)
    public var totalIncome: Double {
        transactions
            .filter { $0.type == .income }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Суммарный расход (по транзакциям)
    public var totalExpenses: Double {
        transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Суммарные расходы (для блока Spending на главном экране)
    public var totalSpending: Double {
        transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
    }
    
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
        
        // Загрузка долгов
        if FileManager.default.fileExists(atPath: debtsURL.path) {
            do {
                let data = try Data(contentsOf: debtsURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                self.debts = try decoder.decode([Debt].self, from: data)
            } catch {
                print("⚠️ Не удалось загрузить долги: \(error.localizedDescription)")
            }
        }
        
        // Загрузка копилок
        if FileManager.default.fileExists(atPath: goalsURL.path) {
            do {
                let data = try Data(contentsOf: goalsURL)
                let decoder = JSONDecoder()
                self.goals = try decoder.decode([Goal].self, from: data)
            } catch {
                print("⚠️ Не удалось загрузить цели: \(error.localizedDescription)")
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
    
    private func saveDebts() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(debts)
            try data.write(to: debtsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить долги: \(error.localizedDescription)")
        }
    }
    
    private func saveGoals() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(goals)
            try data.write(to: goalsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить цели: \(error.localizedDescription)")
        }
    }
}

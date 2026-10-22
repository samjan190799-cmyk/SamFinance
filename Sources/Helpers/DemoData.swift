#if DEBUG
import Foundation

/// Демонстрационные данные для снимков App Store: три карты с разным оформлением, месяц операций, долги и копилки.
/// Названия магазинов выдуманные и одинаковые на всех языках; категории, карты и копилки переводятся как обычно.
@MainActor
enum DemoData {
    static func seed(_ service: FinanceService, now: Date = Date()) {
        service.resetAllData()
        func ago(_ days: Double, hours: Double = 0) -> Date {
            now.addingTimeInterval(-days * 86_400 - hours * 3_600)
        }

        // Карты
        let main = Card(
            last4: "4821", holderName: "A. GRIGORYAN", balance: 1_284_500, type: "main_card".localized,
            colorHex: "#C6F432", gradientColors: ["#C6F432", "#B2E01E"], expiryDate: "09/29",
            balanceUpdatedAt: now, network: .visa, pattern: .rings
        )
        let travel = Card(
            last4: "7710", holderName: "A. GRIGORYAN", balance: 436_200, type: "card_for_travel".localized,
            colorHex: "#2F80ED", gradientColors: ["#2F80ED", "#1B3A8A"], expiryDate: "03/28",
            balanceUpdatedAt: now, network: .mastercard, pattern: .waves, symbol: "airplane"
        )
        let online = Card(
            last4: "3305", holderName: "A. GRIGORYAN", balance: 92_750, type: "card_for_online".localized,
            colorHex: "#2A2B30", gradientColors: ["#2A2B30", "#1C1D21"], expiryDate: "12/27",
            balanceUpdatedAt: now, network: .arca, pattern: .dots, symbol: "cart.fill"
        )
        for card in [main, travel, online] {
            service.addCard(card, number: "")
        }

        // Операции: от старых к новым, потому что сервис ставит каждую новую в начало списка
        struct Entry {
            let days: Double
            let hours: Double
            let title: String
            let amount: Double
            let category: String
            let type: TransactionType
            let card: Card
        }
        let entries: [Entry] = [
            Entry(days: 22, hours: 2, title: "Fresh Bakery", amount: 2_100, category: "Продукты", type: .expense, card: main),
            Entry(days: 20, hours: 5, title: "Studio Lumen", amount: 120_000, category: "Фриланс", type: .income, card: main),
            Entry(days: 19, hours: 4, title: "Dental Clinic", amount: 35_000, category: "Здоровье", type: .expense, card: main),
            Entry(days: 17, hours: 3, title: "City Market", amount: 21_300, category: "Продукты", type: .expense, card: main),
            Entry(days: 16, hours: 6, title: "Cafe Nord", amount: 6_800, category: "Рестораны", type: .expense, card: online),
            Entry(days: 15, hours: 1, title: "Internet", amount: 7_500, category: "Жилье", type: .expense, card: main),
            Entry(days: 14, hours: 7, title: "Fuel Station", amount: 15_500, category: "Транспорт", type: .expense, card: main),
            Entry(days: 13, hours: 2, title: "Green Grocer", amount: 5_100, category: "Продукты", type: .expense, card: main),
            Entry(days: 12, hours: 4, title: "Utilities", amount: 38_000, category: "Жилье", type: .expense, card: main),
            Entry(days: 12, hours: 9, title: "Game Store", amount: 9_900, category: "Развлечения", type: .expense, card: online),
            Entry(days: 11, hours: 3, title: "Metro", amount: 600, category: "Транспорт", type: .expense, card: main),
            Entry(days: 10, hours: 5, title: "Grill Room", amount: 24_500, category: "Рестораны", type: .expense, card: main),
            Entry(days: 9, hours: 2, title: "City Market", amount: 14_700, category: "Продукты", type: .expense, card: main),
            Entry(days: 8, hours: 8, title: "Nord Tech", amount: 650_000, category: "Зарплата", type: .income, card: main),
            Entry(days: 8, hours: 3, title: "Barber", amount: 5_000, category: "Прочее", type: .expense, card: main),
            Entry(days: 7, hours: 4, title: "Taxi", amount: 2_300, category: "Транспорт", type: .expense, card: main),
            Entry(days: 6, hours: 6, title: "Dairy Corner", amount: 3_200, category: "Продукты", type: .expense, card: main),
            Entry(days: 6, hours: 2, title: "Cinema", amount: 4_500, category: "Развлечения", type: .expense, card: online),
            Entry(days: 5, hours: 5, title: "Coffee Point", amount: 2_400, category: "Рестораны", type: .expense, card: main),
            Entry(days: 5, hours: 1, title: "Pharmacy", amount: 5_600, category: "Здоровье", type: .expense, card: main),
            Entry(days: 4, hours: 3, title: "City Market", amount: 18_900, category: "Продукты", type: .expense, card: main),
            Entry(days: 3, hours: 4, title: "Pizza House", amount: 11_200, category: "Рестораны", type: .expense, card: main),
            Entry(days: 2, hours: 6, title: "Fuel Station", amount: 14_000, category: "Транспорт", type: .expense, card: main),
            Entry(days: 2, hours: 2, title: "Green Grocer", amount: 6_300, category: "Продукты", type: .expense, card: main),
            Entry(days: 1, hours: 7, title: "Cafe Nord", amount: 7_900, category: "Рестораны", type: .expense, card: main),
            Entry(days: 1, hours: 3, title: "Fresh Bakery", amount: 1_850, category: "Продукты", type: .expense, card: main),
            Entry(days: 0, hours: 5, title: "Taxi", amount: 1_800, category: "Транспорт", type: .expense, card: main),
            Entry(days: 0, hours: 3, title: "City Market", amount: 12_450, category: "Продукты", type: .expense, card: main)
        ]
        for entry in entries {
            let category = service.category(named: entry.category, type: entry.type)
            service.addTransaction(Transaction(
                title: entry.title, amount: entry.amount, type: entry.type, category: category,
                date: ago(entry.days, hours: entry.hours), brandName: entry.title,
                brandIcon: category.icon, brandColorHex: category.colorHex, cardId: entry.card.id
            ))
        }

        // Долги
        service.addDebt(Debt(name: "ABC Bank", amount: 150_000, dueDate: now.addingTimeInterval(9 * 86_400), isLent: false, type: .credit))
        service.addDebt(Debt(name: "Tigran", amount: 80_000, dueDate: now.addingTimeInterval(21 * 86_400), isLent: true))
        service.addDebt(Debt(name: "Lilit", amount: 20_000, dueDate: now.addingTimeInterval(12 * 86_400), isLent: false))
        service.addDebt(Debt(name: "Armen", amount: 45_000, dueDate: now.addingTimeInterval(5 * 86_400), isLent: true))

        // Копилки: все идут по плану, чтобы на снимках были спокойные статусы
        func idea(_ id: String) -> GoalIdea {
            GoalIdea.all.first { $0.id == id } ?? GoalIdea.all[0]
        }
        let vacation = idea("vacation")
        service.addGoal(Goal(
            cardId: travel.id, title: vacation.title, targetAmount: 800_000, currentAmount: 360_000,
            colorHex: vacation.colors[0], gradientColors: vacation.colors,
            deadline: now.addingTimeInterval(150 * 86_400), symbol: vacation.symbol, createdAt: ago(60),
            entries: [
                GoalEntry(date: ago(50), amount: 150_000),
                GoalEntry(date: ago(30), amount: 100_000),
                GoalEntry(date: ago(12), amount: 110_000)
            ]
        ))
        let reserve = idea("reserve")
        service.addGoal(Goal(
            cardId: main.id, title: reserve.title, targetAmount: 1_500_000, currentAmount: 1_050_000,
            colorHex: reserve.colors[0], gradientColors: reserve.colors,
            deadline: now.addingTimeInterval(400 * 86_400), symbol: reserve.symbol, createdAt: ago(200),
            entries: [
                GoalEntry(date: ago(180), amount: 400_000),
                GoalEntry(date: ago(100), amount: 350_000),
                GoalEntry(date: ago(40), amount: 300_000)
            ]
        ))
        let phone = idea("phone")
        service.addGoal(Goal(
            cardId: online.id, title: phone.title, targetAmount: 450_000, currentAmount: 90_000,
            colorHex: phone.colors[0], gradientColors: phone.colors,
            deadline: now.addingTimeInterval(200 * 86_400), symbol: phone.symbol, createdAt: ago(20),
            entries: [
                GoalEntry(date: ago(15), amount: 50_000),
                GoalEntry(date: ago(4), amount: 40_000)
            ]
        ))
    }

    /// Банковская СМС для чата: покупка по карте 4821 два часа назад
    static func sampleSMS(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        let stamp = formatter.string(from: now.addingTimeInterval(-2 * 3_600))
        return "GNUM\n18,400.00 AMD\n4274***4821\nFRESH SUPERMARKET, AM\n\(stamp)\nMNACORD 1,284,500.00"
    }

    /// Чат как в жизни: пришла СМС и найденная операция ждёт подтверждения, затем вопрос о тратах
    static func fillChat() {
        let store = AIChatStore.shared
        store.reset()
        store.send(text: sampleSMS())
        if let question = ScreenshotMode.question {
            store.send(text: question)
        }
        store.dropGreeting()
    }
}
#endif

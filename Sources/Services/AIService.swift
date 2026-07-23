import Foundation

/// Структура финансового рекомендательного совета от ИИ
public struct AIFinancialInsight: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let iconName: String
    public let type: InsightType
    
    public enum InsightType: Sendable {
        case positive
        case warning
        case info
    }
}

/// Умный сервисный модуль интеллектуального анализа трат и прогноза финансов SamFinance (AI Advisor 2026)
@MainActor
public final class AIService {
    public static let shared = AIService()
    
    private init() {}
    
    /// Генерирует глубокий аналитический разбор финансов пользователя на основе транзакций и карт
    public func generateInsights(financeService: FinanceService) -> [AIFinancialInsight] {
        var insights: [AIFinancialInsight] = []
        let transactions = financeService.transactions
        let expenses = transactions.filter { $0.type == .expense }
        let incomes = transactions.filter { $0.type == .income }
        
        let currencySymbol = CurrencyManager.shared.currentCurrency.symbol
        let totalBalanceFormatted = CurrencyManager.shared.format(financeService.totalBalance)
        let totalSpendingFormatted = CurrencyManager.shared.format(financeService.totalSpending)
        
        // 1. Анализ распределения доходов и трат
        let totalIncomeVal = incomes.reduce(0) { $0 + $1.amount }
        let totalExpenseVal = expenses.reduce(0) { $0 + $1.amount }
        
        if totalIncomeVal > 0 && totalExpenseVal > 0 {
            let savingsRate = ((totalIncomeVal - totalExpenseVal) / totalIncomeVal) * 100
            if savingsRate >= 20 {
                insights.append(AIFinancialInsight(
                    title: "Отличный норматив сбережений!",
                    message: "Вы сохраняете \(Int(savingsRate))% от своего дохода. Это выше рекомендуемого стандарта (20%).",
                    iconName: "chart.line.uptrend.xyaxis.circle.fill",
                    type: .positive
                ))
            } else if savingsRate < 5 {
                insights.append(AIFinancialInsight(
                    title: "Внимание к расходам",
                    message: "Расходы составляют \(Int(100 - savingsRate))% от доходов. Рекомендуем отложить часть денег в копилки.",
                    iconName: "exclamationmark.triangle.fill",
                    type: .warning
                ))
            }
        }
        
        // 2. Анализ топ-категории расходов за 30 дней
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentExpenses = expenses.filter { $0.date >= thirtyDaysAgo }
        
        var categoryTotals: [String: Double] = [:]
        for exp in recentExpenses {
            categoryTotals[exp.category.name, default: 0] += exp.amount
        }
        
        if let topCategory = categoryTotals.max(by: { $0.value < $1.value }) {
            let topCatFormatted = CurrencyManager.shared.format(topCategory.value)
            insights.append(AIFinancialInsight(
                title: "Основная статья расходов",
                message: "За последние 30 дней больше всего потрачено на «\(topCategory.key)» — \(topCatFormatted).",
                iconName: "bag.fill.badge.plus",
                type: .info
            ))
        }
        
        // 3. Анализ средней дневной нормы трат
        if !recentExpenses.isEmpty {
            let avgDaily = totalExpenseVal / 30.0
            let avgDailyFormatted = CurrencyManager.shared.format(avgDaily)
            insights.append(AIFinancialInsight(
                title: "Средний дневной расход",
                message: "В среднем вы расходуете около \(avgDailyFormatted) в день. Контролируйте этот показатель для удержания бюджета.",
                iconName: "calendar.badge.clock",
                type: .info
            ))
        }
        
        // 4. Анализ привязанных банковских карт и копилок
        let cards = financeService.cards
        let goals = financeService.goals
        let activeGoalsCount = goals.filter { !$0.isReached }.count
        
        if !cards.isEmpty {
            insights.append(AIFinancialInsight(
                title: "Привязанные карты (\(cards.count))",
                message: "Капитал распределен по \(cards.count) картам и \(activeGoalsCount) накопительным финансовым целям.",
                iconName: "creditcard.fill",
                type: .positive
            ))
        }
        
        if insights.isEmpty {
            insights.append(AIFinancialInsight(
                title: "Добро пожаловать в SamFinance!",
                message: "Добавьте первые транзакции или импортируйте СМС для формирования персонального ИИ-анализа трат.",
                iconName: "sparkles",
                type: .positive
            ))
        }
        
        return insights
    }
}

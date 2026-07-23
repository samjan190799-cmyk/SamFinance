import AppIntents
import Foundation

/// Системное действие для автоматического парсинга СМС через Быстрые команды (Siri Shortcuts)
@available(iOS 16.0, *)
public struct ProcessSMSIntent: AppIntent {
    public static var title: LocalizedStringResource { "Распознать СМС транзакцию" }
    public static var description: IntentDescription? { "Парсит текст банковской СМС и автоматически сохраняет транзакцию в SamFinance." }
    
    // Входной параметр — текст СМС, передаваемый из приложения "Быстрые команды"
    @Parameter(title: "Текст СМС")
    public var smsText: String
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Распознать транзакцию из \(\.$smsText)")
    }
    
    public init() {
        self.smsText = ""
    }
    
    public init(smsText: String) {
        self.smsText = smsText
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult {
        // Парсим СМС через наш SMSParser
        if let parsed = SMSParser.parse(text: smsText) {
            let financeService = FinanceService.shared
            
            // Находим подходящую категорию
            let category = financeService.categories.first(where: { $0.name == parsed.categoryName }) ?? financeService.categories[0]
            
            let transaction = Transaction(
                title: parsed.title,
                amount: parsed.amount,
                type: parsed.type,
                category: category,
                date: Date(),
                notes: "Автоматически импортировано через Быстрые команды",
                brandName: parsed.brandName,
                brandIcon: category.icon,
                brandColorHex: category.colorHex
            )
            
            // Добавляем операцию
            financeService.addTransaction(transaction)
            
            return .result()
        } else {
            return .result()
        }
    }
}

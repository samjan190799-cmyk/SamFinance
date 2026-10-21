import AppIntents
import Foundation

/// Ошибки действия распознавания СМС
enum ProcessSMSError: Error, CustomLocalizedStringResourceConvertible {
    case storageUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storageUnavailable:
            return "Данные SamFinance сейчас недоступны (возможно, телефон заблокирован). Операция не сохранена."
        }
    }
}

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
            let category = financeService.category(named: parsed.categoryName, type: parsed.type)

            let transaction = Transaction(
                title: parsed.title,
                amount: parsed.amount,
                type: parsed.type,
                category: category,
                date: parsed.date ?? Date(),
                notes: "Автоматически импортировано через Быстрые команды",
                brandName: parsed.brandName,
                brandIcon: category.icon,
                brandColorHex: category.colorHex
            )

            // Добавляем операцию. Если файл данных сейчас недоступен (например, телефон заблокирован),
            // сообщаем об ошибке в Быстрых командах, а не теряем СМС молча.
            guard financeService.addTransaction(transaction) else {
                throw ProcessSMSError.storageUnavailable
            }

            return .result()
        } else {
            return .result()
        }
    }
}

import AppIntents
import Foundation

/// Ошибки действия записи покупки
enum RecordPurchaseError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    case notificationsDisabled

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidAmount:
            return "Не удалось понять сумму покупки."
        case .notificationsDisabled:
            return "Уведомления SamFinance выключены: подсказка о покупке не может появиться. Включите их в настройках iOS."
        }
    }
}

/// Разбор суммы из автоматизации «Транзакция» в Быстрых командах: «12 400», «12,400.50 AMD», «$12.5»
@MainActor
enum PurchaseAmountParser {
    /// Возвращает сумму в базовой валюте приложения или nil, если числа в тексте нет
    static func parse(_ text: String) -> Double? {
        let upper = text.uppercased()
        let currency: AppCurrency
        if upper.contains("USD") || text.contains("$") {
            currency = .usd
        } else if upper.contains("EUR") || text.contains("€") {
            currency = .eur
        } else if upper.contains("RUB") || upper.contains("РУБ") || text.contains("₽") {
            currency = .rub
        } else if upper.contains("AMD") || upper.contains("ДРАМ") || text.contains("֏") {
            currency = .amd
        } else {
            currency = CurrencyManager.shared.baseCurrency
        }

        let cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }

        // Последний разделитель с 1–2 цифрами после него считаем десятичным, остальные — разделителями тысяч
        var normalized = cleaned.filter { $0.isNumber }
        if let lastSeparator = cleaned.lastIndex(where: { $0 == "." || $0 == "," }) {
            let fraction = String(cleaned[cleaned.index(after: lastSeparator)...])
            if (1...2).contains(fraction.count) {
                let integerPart = String(cleaned[..<lastSeparator].filter { $0.isNumber })
                normalized = integerPart + "." + fraction
            }
        }

        guard let value = Double(normalized), value > 0 else { return nil }
        return CurrencyService.shared.convert(amount: value, from: currency, to: CurrencyManager.shared.baseCurrency)
    }
}

/// Действие для Быстрых командах: записать покупку Apple Pay. Показывает уведомление «Расход или доход?»,
/// затем «На что?» и сохраняет операцию. Подключается к автоматизации «Транзакция» (Wallet).
@available(iOS 16.0, *)
public struct RecordPurchaseIntent: AppIntent {
    public static var title: LocalizedStringResource { "Записать покупку Apple Pay" }
    public static var description: IntentDescription? { "Показывает подсказку «Расход или доход?», затем категорию, и сохраняет покупку в SamFinance." }

    // Магазин и сумма берутся из переменных автоматизации «Транзакция»
    @Parameter(title: "Магазин")
    public var merchant: String

    @Parameter(title: "Сумма")
    public var amount: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Записать покупку в \(\.$merchant) на \(\.$amount)")
    }

    public init() {
        self.merchant = ""
        self.amount = ""
    }

    public init(merchant: String, amount: String) {
        self.merchant = merchant
        self.amount = amount
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard let value = PurchaseAmountParser.parse(amount) else {
            throw RecordPurchaseError.invalidAmount
        }
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = await PurchasePromptService.shared.postKindPrompt(
            merchant: name.isEmpty ? "Покупка" : name,
            amount: value,
            date: Date()
        )
        guard shown else {
            throw RecordPurchaseError.notificationsDisabled
        }
        return .result()
    }
}

import Foundation

/// Ключи настроек автоматизации. Их же читают переключатели в настройках через @AppStorage.
enum AutomationKeys {
    static let autoCreateCards = "auto_create_cards"
    static let skipOwnTransfers = "skip_own_transfers"
    static let ownSurnames = "own_surnames"
    static let merchantRules = "merchant_category_rules"
}

/// Результат обработки одной распознанной СМС
enum IngestResult {
    case recorded(Transaction, createdCard: Bool)
    case duplicate
    case skippedTransfer
    case storageUnavailable

    /// Короткое сообщение для Быстрых команд и экрана
    @MainActor
    var message: String {
        switch self {
        case .recorded(let transaction, let createdCard):
            let sign = transaction.type == .income ? "+" : "−"
            let amountText = "\(sign)\(CurrencyManager.shared.format(transaction.amount))"
            var text = String(localized: "Записано: \(transaction.title) · \(amountText)")
            if createdCard {
                text += ". " + String(localized: "Добавлена новая карта")
            }
            return text
        case .duplicate:
            return String(localized: "Эта операция уже записана")
        case .skippedTransfer:
            return String(localized: "Перевод между своими картами не учтён, баланс карты обновлён")
        case .storageUnavailable:
            return String(localized: "Данные Hashiv сейчас недоступны. Операция не сохранена")
        }
    }
}

/// Сводка по пакетной обработке СМС
struct IngestSummary {
    var recorded = 0
    var duplicates = 0
    var skippedTransfers = 0
    var failed = 0

    var text: String {
        var parts = [String(localized: "записано: \(recorded)")]
        if duplicates > 0 { parts.append(String(localized: "дубли: \(duplicates)")) }
        if skippedTransfers > 0 { parts.append(String(localized: "переводы между своими картами: \(skippedTransfers)")) }
        if failed > 0 { parts.append(String(localized: "не сохранено: \(failed)")) }
        return parts.joined(separator: ", ")
    }
}

/// Автоматизация учёта: превращает распознанную СМС в операцию без участия пользователя.
/// Привязывает операцию к карте по маске, ведёт баланс карты, отсекает дубли и переводы между своими картами,
/// запоминает категории магазинов.
@MainActor
public final class AutomationService {
    public static let shared = AutomationService()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Настройки

    /// Создавать карту сама, когда в СМС встретилась неизвестная маска
    var autoCreateCards: Bool {
        defaults.object(forKey: AutomationKeys.autoCreateCards) as? Bool ?? true
    }

    /// Не записывать переводы между своими картами как доход и расход
    var skipOwnTransfers: Bool {
        defaults.object(forKey: AutomationKeys.skipOwnTransfers) as? Bool ?? true
    }

    /// Фамилии владельца: из настроек и из имён на картах
    private func ownSurnames(financeService: FinanceService) -> [String] {
        let separators = CharacterSet(charactersIn: ",; \n")
        var names = (defaults.string(forKey: AutomationKeys.ownSurnames) ?? "")
            .uppercased()
            .components(separatedBy: separators)
            .filter { $0.count >= 3 }

        let placeholders = ["USER", "CARDHOLDER"]
        for card in financeService.cards {
            let last = card.holderName.uppercased().split(separator: " ").last.map(String.init) ?? ""
            if last.count >= 3 && !placeholders.contains(last) {
                names.append(last)
            }
        }
        return names
    }

    private func isOwnName(_ name: String?, financeService: FinanceService) -> Bool {
        guard let name else { return false }
        let upper = name.uppercased()
        return ownSurnames(financeService: financeService).contains { upper.contains($0) }
    }

    // MARK: - Запоминание категорий

    private static func merchantKey(_ merchant: String, type: TransactionType) -> String {
        let normalized = merchant.lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(type.rawValue):\(normalized)"
    }

    private var rules: [String: String] {
        get { defaults.dictionary(forKey: AutomationKeys.merchantRules) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: AutomationKeys.merchantRules) }
    }

    /// Запоминает, что магазин относится к категории: в следующий раз она подставится сама
    func learnCategory(merchant: String, category: Category) {
        let key = Self.merchantKey(merchant, type: category.type)
        guard !key.hasSuffix(":") else { return }
        var current = rules
        current[key] = category.id.uuidString
        rules = current
    }

    /// Категория, которую пользователь уже выбирал для этого магазина
    func learnedCategory(forMerchant merchant: String, type: TransactionType) -> Category? {
        let key = Self.merchantKey(merchant, type: type)
        guard let raw = rules[key], let id = UUID(uuidString: raw) else { return nil }
        return FinanceService.shared.categories.first { $0.id == id && $0.type == type }
    }

    // MARK: - Обработка СМС

    /// Записывает операцию из СМС. Баланс карты берётся из остатка в СМС, а если его нет, меняется на сумму операции.
    func ingest(_ parsed: ParsedSMSTransaction) -> IngestResult {
        let financeService = FinanceService.shared
        let baseCurrency = CurrencyManager.shared.baseCurrency
        let amount = CurrencyService.shared.convert(amount: parsed.amount, from: parsed.currency, to: baseCurrency)
        let balance = parsed.balanceAfter.map {
            CurrencyService.shared.convert(amount: $0, from: parsed.currency, to: baseCurrency)
        }
        let date = parsed.date ?? Date()

        if financeService.hasTransaction(externalKey: parsed.dedupKey) {
            return .duplicate
        }

        // Карта по маске из СМС; незнакомую создаём сами
        var card = parsed.cardLast4.flatMap { financeService.card(withLast4: $0) }
        var createdCard = false
        if card == nil, let last4 = parsed.cardLast4, autoCreateCards {
            card = createCard(last4: last4, balance: balance ?? 0, date: date, financeService: financeService)
            createdCard = card != nil
        }

        // Перевод между своими картами не доход и не расход: баланс обновляем, операцию не пишем
        if parsed.isTransfer && skipOwnTransfers && isOwnName(parsed.counterparty, financeService: financeService) {
            if let card, let balance {
                financeService.syncCardBalance(id: card.id, balance: balance, asOf: date)
            }
            return .skippedTransfer
        }

        // Выученная категория сильнее догадки парсера
        let merchant = parsed.brandName ?? parsed.title
        let learned = learnedCategory(forMerchant: merchant, type: parsed.type)
        let category = learned ?? financeService.category(named: parsed.categoryName, type: parsed.type)
        let needsReview = learned == nil && parsed.isCategoryGuessed

        let transaction = Transaction(
            title: parsed.title,
            amount: amount,
            type: parsed.type,
            category: category,
            date: date,
            notes: String(localized: "Автоматически из СМС"),
            brandName: parsed.brandName,
            brandIcon: category.icon,
            brandColorHex: category.colorHex,
            cardId: card?.id,
            externalKey: parsed.dedupKey,
            needsReview: needsReview ? true : nil
        )

        guard financeService.addTransaction(transaction) else {
            return .storageUnavailable
        }

        if let card {
            if let balance {
                financeService.syncCardBalance(id: card.id, balance: balance, asOf: date)
            } else {
                let delta = parsed.type == .income ? amount : -amount
                if let applied = financeService.applyToCardBalance(id: card.id, delta: delta, asOf: date) {
                    financeService.setBalanceDelta(transactionID: transaction.id, delta: applied)
                }
            }
        }
        return .recorded(transaction, createdCard: createdCard)
    }

    /// Обрабатывает список СМС по порядку дат, чтобы баланс карты остался от самой свежей
    func ingestAll(_ items: [ParsedSMSTransaction]) -> IngestSummary {
        var summary = IngestSummary()
        let ordered = items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        for item in ordered {
            switch ingest(item) {
            case .recorded:
                summary.recorded += 1
            case .duplicate:
                summary.duplicates += 1
            case .skippedTransfer:
                summary.skippedTransfers += 1
            case .storageUnavailable:
                summary.failed += 1
            }
        }
        return summary
    }

    private func createCard(last4: String, balance: Double, date: Date, financeService: FinanceService) -> Card? {
        let holder = financeService.cards.first?.holderName ?? "CARDHOLDER"
        let card = Card(
            last4: last4,
            holderName: holder,
            balance: balance,
            type: String(localized: "Карта •••• \(last4)"),
            colorHex: "#2A2B30",
            gradientColors: ["#2A2B30", "#1C1D21"],
            isFrozen: false,
            expiryDate: "—",
            balanceUpdatedAt: date
        )
        financeService.addCard(card, number: "")
        return financeService.card(withLast4: last4)
    }
}

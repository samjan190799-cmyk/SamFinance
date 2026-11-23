import Foundation

/// Наличные: один общий кошелёк рядом с картами. Баланс хранится в базовой валюте, как у карт,
/// а показывается в текущей. Меняется вручную («Пополнить», «Убавить», «Обнулить») и операциями с пометкой «Наличные».
public struct CashAccount: Codable, Equatable, Sendable {
    public var balance: Double
    /// Когда баланс поправили вручную. Операции старше этого момента баланс не меняют: поправка уже учитывает их.
    /// Пока поправок не было, баланс меняют любые операции.
    public var balanceUpdatedAt: Date?

    public init(balance: Double = 0, balanceUpdatedAt: Date? = nil) {
        self.balance = balance
        self.balanceUpdatedAt = balanceUpdatedAt
    }
}

/// Счёт, с которого списаны деньги или на который они пришли: наличные или карта
public enum BalanceAccount: Hashable, Sendable {
    case cash
    case card(UUID)

    /// Строка для хранения выбора (например, «в прошлый раз платил наличными»)
    public var storageKey: String {
        switch self {
        case .cash:
            return "cash"
        case .card(let id):
            return "card:" + id.uuidString
        }
    }

    public init?(storageKey: String) {
        if storageKey == "cash" {
            self = .cash
        } else if storageKey.hasPrefix("card:"), let id = UUID(uuidString: String(storageKey.dropFirst(5))) {
            self = .card(id)
        } else {
            return nil
        }
    }
}

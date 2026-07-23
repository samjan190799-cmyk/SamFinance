import Foundation
import SwiftUI
import Observation

/// Поддерживаемые валюты приложения
public enum AppCurrency: String, CaseIterable, Identifiable, Codable, Sendable {
    case amd = "AMD" // Армянский драм ֏
    case rub = "RUB" // Российский рубль ₽
    case usd = "USD" // Доллар США $
    case eur = "EUR" // Евро €
    
    public var id: String { rawValue }
    
    public var symbol: String {
        switch self {
        case .amd: return "֏"
        case .rub: return "₽"
        case .usd: return "$"
        case .eur: return "€"
        }
    }
    
    public var displayName: String {
        switch self {
        case .amd: return "Армянский драм (֏)"
        case .rub: return "Российский рубль (₽)"
        case .usd: return "Доллар США ($)"
        case .eur: return "Евро (€)"
        }
    }
}

/// Менеджер глобальной валюты приложения SamFinance
@Observable
@MainActor
public final class CurrencyManager {
    @MainActor public static let shared = CurrencyManager()
    
    public var currentCurrency: AppCurrency {
        didSet {
            UserDefaults.standard.set(currentCurrency.rawValue, forKey: "app_currency")
        }
    }
    
    private init() {
        // По умолчанию выставляем Армянский Драм (֏ / AMD)
        let saved = UserDefaults.standard.string(forKey: "app_currency") ?? AppCurrency.amd.rawValue
        self.currentCurrency = AppCurrency(rawValue: saved) ?? .amd
    }
    
    /// Форматирование суммы с символом выбранной валюты (например: "֏ 15,000" или "15,000 ֏")
    public func format(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        
        let formattedNum = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
        return "\(currentCurrency.symbol)\(formattedNum)"
    }
}

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
    
    public var flagIcon: String {
        switch self {
        case .amd: return "🇦🇲"
        case .rub: return "🇷🇺"
        case .usd: return "🇺🇸"
        case .eur: return "🇪🇺"
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

/// Менеджер глобальной валюты приложения SamFinance с автоматическим пересчетом по курсу
@Observable
@MainActor
public final class CurrencyManager {
    public static let shared = CurrencyManager()
    
    /// Базовая валюта сохранения сумм в приложении (Армянский драм AMD)
    public var baseCurrency: AppCurrency = .amd
    
    /// Текущая выбранная пользователем валюта отображения (AMD, RUB, USD, EUR)
    public var currentCurrency: AppCurrency {
        didSet {
            UserDefaults.standard.set(currentCurrency.rawValue, forKey: "app_currency")
        }
    }
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_currency") ?? AppCurrency.amd.rawValue
        self.currentCurrency = AppCurrency(rawValue: saved) ?? .amd
    }
    
    /// Пересчитывает сумму из базовой валюты в текущую выбранную пользователем по онлайн-курсу
    public func convertFromBase(_ amountInBase: Double) -> Double {
        return CurrencyService.shared.convert(amount: amountInBase, from: baseCurrency, to: currentCurrency)
    }
    
    /// Форматирование суммы с символом выбранной валюты и автопересчетом по курсу
    public func format(_ amountInBase: Double) -> String {
        let converted = convertFromBase(amountInBase)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = (currentCurrency == .usd || currentCurrency == .eur) ? 2 : 0
        formatter.groupingSeparator = " "
        
        let formattedNum = formatter.string(from: NSNumber(value: converted)) ?? "\(Int(converted))"
        return "\(currentCurrency.symbol)\(formattedNum)"
    }
}

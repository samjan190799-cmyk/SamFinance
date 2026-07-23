import Foundation
import SwiftUI
import Observation

/// Актуальный сервис онлайн курсов валют и их онлайн-конвертер
@Observable
@MainActor
public final class CurrencyService {
    @MainActor public static let shared = CurrencyService()
    
    // Курсы обмена относительно 1 USD (базовые значения по умолчанию + онлайн автообновление)
    public var exchangeRates: [AppCurrency: Double] = [
        .amd: 388.5, // 1 USD = ~388.5 AMD (Армянский драм)
        .rub: 88.5,  // 1 USD = ~88.5 RUB (Российский рубль)
        .usd: 1.0,   // 1 USD
        .eur: 0.92   // 1 USD = ~0.92 EUR (Евро)
    ]
    
    public var lastUpdated: Date = Date()
    public var isLoading: Bool = false
    
    private init() {
        fetchLatestRates()
    }
    
    /// Получение актуальных онлайн курсов валют с бекенда открытых курсов ЦБ
    public func fetchLatestRates() {
        isLoading = true
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            isLoading = false
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rates = json["rates"] as? [String: Double] {
                    
                    var newRates = self.exchangeRates
                    if let amd = rates["AMD"] { newRates[.amd] = amd }
                    if let rub = rates["RUB"] { newRates[.rub] = rub }
                    if let usd = rates["USD"] { newRates[.usd] = usd }
                    if let eur = rates["EUR"] { newRates[.eur] = eur }
                    
                    self.exchangeRates = newRates
                    self.lastUpdated = Date()
                }
            } catch {
                print("Failed to fetch exchange rates: \(error)")
            }
            self.isLoading = false
        }
    }
    
    /// Конвертация любой суммы из одной валюты в другую по текущему онлайн-курсу
    public func convert(amount: Double, from source: AppCurrency, to target: AppCurrency) -> Double {
        guard source != target else { return amount }
        guard let sourceRate = exchangeRates[source],
              let targetRate = exchangeRates[target],
              sourceRate > 0 else {
            return amount
        }
        
        let inUSD = amount / sourceRate
        return inUSD * targetRate
    }
    
    /// Рассчитывает прямой курс 1 валюты к другой (например: "1 RUB = 4.38 AMD")
    public func getDirectRate(from source: AppCurrency, to target: AppCurrency) -> Double {
        return convert(amount: 1.0, from: source, to: target)
    }
}

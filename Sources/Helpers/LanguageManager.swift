import Foundation
import SwiftUI
import Observation

/// Доступные языки интерфейса приложения
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case russian = "ru"
    case english = "en"
    case armenian = "hy"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .russian:
            return "Русский"
        case .english:
            return "English"
        case .armenian:
            return "Հայերեն"
        }
    }
    
    public var flagIcon: String {
        switch self {
        case .russian:
            return "🇷🇺"
        case .english:
            return "🇺🇸"
        case .armenian:
            return "🇦🇲"
        }
    }
}

/// Менеджер динамической локализации приложения SamFinance
@Observable
@MainActor
public final class LanguageManager {
    @MainActor public static let shared = LanguageManager()
    
    public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
        }
    }
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.russian.rawValue
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .russian
    }
    
    /// Получение локализованной строки по ключу
    public func localizedString(for key: String) -> String {
        guard let dict = translations[key] else { return key }
        return dict[currentLanguage] ?? dict[.russian] ?? key
    }
    
    // MARK: - Словарь переводов
    private let translations: [String: [AppLanguage: String]] = [
        // Табы и навигация
        "tab_debts": [.russian: "Долги", .english: "Debts", .armenian: "Պարտքեր"],
        "tab_goals": [.russian: "Копилки", .english: "Goals", .armenian: "Նպատակներ"],
        "tab_main": [.russian: "Главная", .english: "Dashboard", .armenian: "Գլխավոր"],
        "tab_cards": [.russian: "Карты", .english: "Cards", .armenian: "Քարտեր"],
        
        // Главный экран
        "total_balance": [.russian: "Общий баланс", .english: "Total balance", .armenian: "Ընդհանուր հաշվեկշիռ"],
        "spending": [.russian: "Расходы за период", .english: "Spending", .armenian: "Ծախսեր"],
        "send": [.russian: "Перевод", .english: "Send", .armenian: "Փոխանցել"],
        "request": [.russian: "Запрос", .english: "Request", .armenian: "Պահանջել"],
        "order_card": [.russian: "Заказать карту", .english: "Order a card", .armenian: "Պատվիրել քարտ"],
        "no_spending": [.russian: "Расходов нет", .english: "No spending yet", .armenian: "Ծախսեր չկան"],
        "weekly_spending": [.russian: "Динамика расходов за неделю", .english: "Weekly Spending Trend", .armenian: "Շաբաթական ծախսերի դինամիկա"],
        "category_distribution": [.russian: "Распределение по категориям", .english: "Category Breakdown", .armenian: "Բաշխում ըստ կատեգորիաների"],
        "no_chart_data": [.russian: "Нет данных для отображения", .english: "No data available", .armenian: "Տվյալներ չկան"],
        
        // Карты
        "cards_title": [.russian: "Карты", .english: "Cards", .armenian: "Քարտեր"],
        "add_card": [.russian: "Добавить карту", .english: "Add card", .armenian: "Ավելացնել քարտ"],
        "no_cards": [.russian: "Нет подключенных карт", .english: "No connected cards", .armenian: "Կցված քարտեր չկան"],
        "no_cards_desc": [.russian: "Выпустите вашу первую карту для удобного управления финансами.", .english: "Issue your first card for easy money management.", .armenian: "Թողարկեք Ձեր առաջին քարտը ֆինանսները կառավարելու համար:"],
        "freeze": [.russian: "Заморозить", .english: "Freeze", .armenian: "Սառեցնել"],
        "unfreeze": [.russian: "Разморозить", .english: "Unfreeze", .armenian: "Ապասառեցնել"],
        "card_details": [.russian: "Реквизиты карты", .english: "Card Details", .armenian: "Քարտի տվյալները"],
        "copy_number": [.russian: "Скопировать номер", .english: "Copy Card Number", .armenian: "Պատճենել համարը"],
        "copied": [.russian: "Номер скопирован!", .english: "Copied to Clipboard!", .armenian: "Համարը պատճենված է:"],
        "delete_card": [.russian: "Удалить карту", .english: "Delete Card", .armenian: "Ջնջել քարտը"],
        
        // Долги
        "debts_title": [.russian: "Долги", .english: "Debts", .armenian: "Պարտքեր"],
        "add_debt": [.russian: "Добавить долг", .english: "Add debt", .armenian: "Ավելացնել պարտք"],
        "credits_tab": [.russian: "Кредиты", .english: "Credits", .armenian: "Վարկեր"],
        "people_tab": [.russian: "Люди", .english: "People", .armenian: "Մարդիկ"],
        "empty_debts": [.russian: "Список долгов пуст", .english: "No active debts", .armenian: "Պարտքերի ցուցակը դատարկ է"],
        
        // Копилки
        "goals_title": [.russian: "Копилки", .english: "Goals", .armenian: "Նպատակներ"],
        "add_goal": [.russian: "Новая цель", .english: "New Goal", .armenian: "Նոր նպատակ"],
        "deposit": [.russian: "Пополнить", .english: "Deposit", .armenian: "Համալրել"],
        
        // Настройки
        "settings_title": [.russian: "Настройки", .english: "Settings", .armenian: "Կարգավորումներ"],
        "profile": [.russian: "Профиль", .english: "Profile", .armenian: "Անձնական էջ"],
        "user_name": [.russian: "Пользователь SamFinance", .english: "SamFinance User", .armenian: "SamFinance Օգտատեր"],
        "tariff": [.russian: "Тариф: Premium Pro", .english: "Plan: Premium Pro", .armenian: "Սակագին՝ Premium Pro"],
        "preferences": [.russian: "Предпочтения", .english: "Preferences", .armenian: "Նախապատվություններ"],
        "app_language": [.russian: "Язык приложения", .english: "App Language", .armenian: "Հավելվածի լեզուն"],
        "main_currency": [.russian: "Основная валюта", .english: "Primary Currency", .armenian: "Հիմնական արժույթ"],
        "export_data": [.russian: "Экспорт данных", .english: "Export Data", .armenian: "Տվյալների արտահանում"],
        "danger_zone": [.russian: "Опасная зона", .english: "Danger Zone", .armenian: "Վտանգավոր գոտի"],
        "reset_data": [.russian: "Сбросить все данные", .english: "Reset All Data", .armenian: "Վերականգնել տվյալները"],
        "reset_footer": [.russian: "Все карты, транзакции, долги и накопительные цели будут очищены из памяти.", .english: "All cards, transactions, debts, and savings goals will be cleared.", .armenian: "Բոլոր քարտերը, գործարքները, պարտքերը և նպատակները կջնջվեն:"]
    ]
}

/// Расширение String для удобного обращения string.localized
public extension String {
    var localized: String {
        LanguageManager.shared.localizedString(for: self)
    }
}

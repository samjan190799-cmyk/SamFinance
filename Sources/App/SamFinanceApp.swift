import SwiftUI
import UserNotifications

/// Точка входа в iOS-приложение SamFinance.
@main
struct SamFinanceApp: App {
    init() {
        // Кнопки подсказки покупки Apple Pay должны быть зарегистрированы, а делегат назначен при каждом запуске:
        // нажатие на кнопку может запустить приложение в фоне
        UNUserNotificationCenter.current().delegate = PurchaseNotificationDelegate.shared
        PurchasePromptService.shared.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

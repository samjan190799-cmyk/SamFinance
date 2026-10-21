@preconcurrency import UserNotifications
import Foundation

/// Напоминания о сроках долгов: уведомление в 9:00 в день срока для каждого непогашенного долга.
/// Других отложенных уведомлений в приложении нет, поэтому список пересоздаётся целиком.
@MainActor
public final class DebtReminderService {
    public static let shared = DebtReminderService()

    private init() {}

    /// Пересоздаёт напоминания по текущему списку долгов
    public func reschedule(_ debts: [Debt]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for debt in debts {
            if let request = makeRequest(for: debt) {
                center.add(request)
            }
        }
    }

    private func makeRequest(for debt: Debt) -> UNNotificationRequest? {
        guard !debt.isPaid else { return nil }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: debt.dueDate)
        components.hour = 9
        guard let fireDate = calendar.date(from: components), fireDate > Date() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = debt.isLent ? "Срок возврата долга: \(debt.name)" : "Срок платежа: \(debt.name)"
        content.body = "\(CurrencyManager.shared.format(debt.amount)) · сегодня"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: "debt-due-\(debt.id.uuidString)", content: content, trigger: trigger)
    }
}

@preconcurrency import UserNotifications
import Foundation

/// Идентификаторы уведомлений и кнопок подсказки покупки
enum PurchasePromptID {
    static let kindCategory = "purchase.kind"
    static let expenseFirstCategory = "purchase.expense.first"
    static let expenseMoreCategory = "purchase.expense.more"
    static let incomeCategory = "purchase.income"
    static let expenseAction = "purchase.action.expense"
    static let incomeAction = "purchase.action.income"
    static let skipAction = "purchase.action.skip"
    static let moreAction = "purchase.action.more"
    static let categoryActionPrefix = "purchase.action.category."
}

/// Данные покупки, которые переезжают между шагами в userInfo уведомления
struct PurchaseContext: Sendable {
    let merchant: String
    let amount: Double
    let date: Double // timeIntervalSince1970
    let kind: String? // TransactionType.rawValue, известен со второго шага

    init(merchant: String, amount: Double, date: Double, kind: String? = nil) {
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.kind = kind
    }

    init(info: [AnyHashable: Any]) {
        self.merchant = info["merchant"] as? String ?? ""
        self.amount = info["amount"] as? Double ?? 0
        self.date = info["date"] as? Double ?? Date().timeIntervalSince1970
        self.kind = info["kind"] as? String
    }

    var userInfo: [String: Any] {
        var info: [String: Any] = ["merchant": merchant, "amount": amount, "date": date]
        if let kind {
            info["kind"] = kind
        }
        return info
    }

    func withKind(_ kind: TransactionType) -> PurchaseContext {
        PurchaseContext(merchant: merchant, amount: amount, date: date, kind: kind.rawValue)
    }
}

/// Подсказки после покупки через Apple Pay. Автоматизация «Транзакция» в Быстрых командах вызывает
/// `RecordPurchaseIntent`, а сервис показывает уведомление с кнопками: сначала «Расход» или «Доход»,
/// затем категория. Выбор сохраняется как операция, приложение при этом не открывается.
@MainActor
public final class PurchasePromptService {
    public static let shared = PurchasePromptService()

    private init() {}

    /// Сколько категорий расходов показать на первом шаге, остальные открываются кнопкой «Ещё…»
    private static let firstPageSize = 3

    /// Категории расходов для покупок: переводы и долги к оплате картой не относятся
    private var expenseCategories: [Category] {
        let excluded = ["Переводы", "Долги"]
        return Category.defaultCategories.filter { $0.type == .expense && !excluded.contains($0.name) }
    }

    private var incomeCategories: [Category] {
        Category.defaultCategories.filter { $0.type == .income }
    }

    // MARK: - Регистрация кнопок

    /// Регистрирует наборы кнопок. Вызывать при запуске приложения, до показа уведомлений.
    public func registerCategories() {
        func categoryActions(_ list: [Category]) -> [UNNotificationAction] {
            list.map {
                UNNotificationAction(
                    identifier: PurchasePromptID.categoryActionPrefix + $0.id.uuidString,
                    title: $0.name,
                    options: [.authenticationRequired]
                )
            }
        }

        let kind = UNNotificationCategory(
            identifier: PurchasePromptID.kindCategory,
            actions: [
                UNNotificationAction(identifier: PurchasePromptID.expenseAction, title: "Расход", options: [.authenticationRequired]),
                UNNotificationAction(identifier: PurchasePromptID.incomeAction, title: "Доход", options: [.authenticationRequired]),
                UNNotificationAction(identifier: PurchasePromptID.skipAction, title: "Пропустить", options: [.destructive])
            ],
            intentIdentifiers: [],
            options: []
        )
        let expenseFirst = UNNotificationCategory(
            identifier: PurchasePromptID.expenseFirstCategory,
            actions: categoryActions(Array(expenseCategories.prefix(Self.firstPageSize))) + [
                UNNotificationAction(identifier: PurchasePromptID.moreAction, title: "Ещё…", options: [.authenticationRequired])
            ],
            intentIdentifiers: [],
            options: []
        )
        let expenseMore = UNNotificationCategory(
            identifier: PurchasePromptID.expenseMoreCategory,
            actions: categoryActions(Array(expenseCategories.dropFirst(Self.firstPageSize))),
            intentIdentifiers: [],
            options: []
        )
        let income = UNNotificationCategory(
            identifier: PurchasePromptID.incomeCategory,
            actions: categoryActions(incomeCategories),
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([kind, expenseFirst, expenseMore, income])
    }

    // MARK: - Разрешение на уведомления

    /// Запрашивает разрешение на уведомления. Возвращает true, если они разрешены.
    public func requestAuthorization() async -> Bool {
        await Self.requestAuthorizationFromSystem()
    }

    nonisolated private static func requestAuthorizationFromSystem() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated private static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    // MARK: - Шаги подсказки

    /// Первый шаг: «Расход или доход?». Возвращает false, если уведомления запрещены и подсказку показать нельзя.
    func postKindPrompt(merchant: String, amount: Double, date: Date) async -> Bool {
        // Магазин уже знаком: записываем расход сразу, без вопросов
        if let learned = AutomationService.shared.learnedCategory(forMerchant: merchant, type: .expense) {
            let known = PurchaseContext(
                merchant: merchant,
                amount: amount,
                date: date.timeIntervalSince1970,
                kind: TransactionType.expense.rawValue
            )
            record(categoryID: learned.id, context: known)
            return true
        }

        var status = await Self.currentAuthorizationStatus()
        if status == .notDetermined {
            _ = await requestAuthorization()
            status = await Self.currentAuthorizationStatus()
        }
        guard status == .authorized || status == .provisional else { return false }

        let context = PurchaseContext(merchant: merchant, amount: amount, date: date.timeIntervalSince1970)
        post(
            category: PurchasePromptID.kindCategory,
            title: header(for: context),
            body: "Это расход или доход?",
            context: context
        )
        return true
    }

    /// Обрабатывает нажатие на кнопку подсказки
    func handle(actionIdentifier: String, context: PurchaseContext) {
        switch actionIdentifier {
        case PurchasePromptID.expenseAction:
            post(
                category: PurchasePromptID.expenseFirstCategory,
                title: header(for: context),
                body: "Расход: на что потрачено?",
                context: context.withKind(.expense)
            )
        case PurchasePromptID.incomeAction:
            post(
                category: PurchasePromptID.incomeCategory,
                title: header(for: context),
                body: "Доход: откуда он?",
                context: context.withKind(.income)
            )
        case PurchasePromptID.moreAction:
            post(
                category: PurchasePromptID.expenseMoreCategory,
                title: header(for: context),
                body: "Расход: другие категории",
                context: context
            )
        case PurchasePromptID.skipAction:
            break
        default:
            guard actionIdentifier.hasPrefix(PurchasePromptID.categoryActionPrefix) else { return }
            let rawID = String(actionIdentifier.dropFirst(PurchasePromptID.categoryActionPrefix.count))
            record(categoryID: UUID(uuidString: rawID), context: context)
        }
    }

    /// Последний шаг: сохраняет операцию и сообщает результат
    private func record(categoryID: UUID?, context: PurchaseContext) {
        let financeService = FinanceService.shared
        guard let categoryID,
              let category = financeService.categories.first(where: { $0.id == categoryID }),
              let kind = context.kind.flatMap({ TransactionType(rawValue: $0) }) else {
            return
        }

        let transaction = Transaction(
            title: context.merchant,
            amount: context.amount,
            type: kind,
            category: category,
            date: Date(timeIntervalSince1970: context.date),
            notes: "Apple Pay, записано из подсказки после покупки",
            brandName: context.merchant,
            brandIcon: category.icon,
            brandColorHex: category.colorHex
        )

        let sign = kind == .expense ? "−" : "+"
        let amountText = "\(sign)\(CurrencyManager.shared.format(context.amount))"
        if financeService.addTransaction(transaction) {
            // Выбор запоминается: следующая покупка в этом магазине запишется без вопросов
            AutomationService.shared.learnCategory(merchant: context.merchant, category: category)
            post(
                category: "",
                title: "Записано",
                body: "\(context.merchant) · \(category.name) · \(amountText)",
                context: context,
                withSound: false
            )
        } else {
            post(
                category: "",
                title: "Не удалось сохранить",
                body: "\(context.merchant) · \(amountText). Откройте SamFinance и повторите.",
                context: context
            )
        }
    }

    // MARK: - Показ уведомлений

    private func header(for context: PurchaseContext) -> String {
        "\(context.merchant) · \(CurrencyManager.shared.format(context.amount))"
    }

    private func post(category: String, title: String, body: String, context: PurchaseContext, withSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = context.userInfo
        if withSound {
            content.sound = .default
        }
        Self.deliver(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated private static func deliver(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("⚠️ Не удалось показать подсказку покупки: \(error.localizedDescription)")
            }
        }
    }
}

/// Принимает нажатия на кнопки подсказки и показывает уведомления, пока приложение открыто
final class PurchaseNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = PurchaseNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let context = PurchaseContext(info: response.notification.request.content.userInfo)
        await PurchasePromptService.shared.handle(actionIdentifier: action, context: context)
    }
}

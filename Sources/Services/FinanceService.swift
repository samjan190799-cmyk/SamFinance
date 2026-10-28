import Foundation
import Observation

/// Менеджер данных финансов. Управляет картами, транзакциями, долгами и копилками.
/// Данные сохраняются локально в JSON-файлы. Демо-данные удалены для чистого старта.
@Observable
@MainActor
public final class FinanceService {
    @MainActor public static let shared = FinanceService()
    
    public private(set) var transactions: [Transaction] = []
    public private(set) var cards: [Card] = []
    public private(set) var debts: [Debt] = []
    public private(set) var goals: [Goal] = []
    public private(set) var customReminders: [CustomReminder] = []
    public private(set) var categories: [Category] = Category.defaultCategories
    
    // Пути к файлам сохранения в песочнице
    private let fileURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("transactions.json")
    }()
    
    private let cardsURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("cards.json")
    }()
    
    private let debtsURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("debts.json")
    }()
    
    private let goalsURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("goals.json")
    }()

    private let remindersURL: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("reminders.json")
    }()

    /// Хранилища данных на диске
    private enum Store: String {
        case transactions
        case cards
        case debts
        case goals
        case reminders
    }

    /// Хранилища, файл которых существует, но не удалось прочитать или сохранить рядом резервную копию
    /// (например, телефон заблокирован, а файлы защищены `completeFileProtection`).
    /// Пока хранилище в этом списке, запись в него запрещена, чтобы пустой массив не затёр непрочитанные данные.
    @ObservationIgnored private var unreadableStores: Set<Store> = []

    /// Все файлы прочитаны. Пока это не так (телефон заблокирован), напоминания не пересоздаются:
    /// пустые списки иначе удалили бы напоминания о непрочитанных долгах и копилках.
    var isFullyLoaded: Bool {
        unreadableStores.isEmpty
    }

    public init() {
        loadData()
        // Демо-информация полностью удалена при инициализации.
        // Приложение запускается полностью чистым.
    }

    // MARK: - Категории

    /// Подбирает категорию по названию и типу операции. Если такой нет, берёт первую категорию нужного типа,
    /// чтобы расход никогда не получил доходную категорию (и наоборот).
    public func category(named name: String, type: TransactionType) -> Category {
        categories.first { $0.name == name && $0.type == type }
            ?? categories.first { $0.type == type }
            ?? categories[0]
    }

    // MARK: - API для транзакций

    /// Возвращает `false`, если файл транзакций сейчас нельзя безопасно перезаписать — тогда операция не добавлена.
    @discardableResult
    public func addTransaction(_ transaction: Transaction) -> Bool {
        guard prepareForWrite(.transactions) else { return false }
        transactions.insert(transaction, at: 0)

        // Автоматически корректируем баланс карт, если транзакция привязана к счету (дополнительная логика)
        saveData()
        return true
    }

    public func deleteTransaction(_ transaction: Transaction) {
        guard prepareForWrite(.transactions) else { return }
        if let existing = transactions.first(where: { $0.id == transaction.id }) {
            revertBalance(of: existing)
        }
        transactions.removeAll { $0.id == transaction.id }
        saveData()
    }

    public func deleteTransactions(at offsets: IndexSet) {
        guard prepareForWrite(.transactions) else { return }
        for index in offsets where transactions.indices.contains(index) {
            revertBalance(of: transactions[index])
        }
        transactions.remove(atOffsets: offsets)
        saveData()
    }

    /// Меняет категорию операции и снимает отметку «проверить»
    public func updateCategory(transactionID: UUID, category: Category) {
        guard prepareForWrite(.transactions) else { return }
        if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
            transactions[index].category = category
            transactions[index].brandIcon = category.icon
            transactions[index].brandColorHex = category.colorHex
            transactions[index].needsReview = nil
            saveData()
        }
    }

    /// Запоминает, на сколько операция изменила баланс карты
    public func setBalanceDelta(transactionID: UUID, delta: Double) {
        guard prepareForWrite(.transactions) else { return }
        if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
            transactions[index].balanceDelta = delta
            saveData()
        }
    }

    /// Операция с таким ключом СМС уже записана
    public func hasTransaction(externalKey: String) -> Bool {
        transactions.contains { $0.externalKey == externalKey }
    }

    /// Сколько операций ждут проверки категории
    public var reviewCount: Int {
        transactions.filter { $0.needsReview == true }.count
    }

    /// Сбросить абсолютно все данные приложения (транзакции, карты, долги, цели)
    public func resetAllData() {
        // Пользователь явно просит стереть всё — защита от перезаписи больше не нужна
        unreadableStores.removeAll()
        CardSecretsStore.deleteAll()
        transactions.removeAll()
        cards.removeAll()
        debts.removeAll()
        goals.removeAll()
        customReminders.removeAll()
        saveData()
        saveCards()
        saveDebts()
        saveGoals()
        saveReminders()
    }
    
    // MARK: - API для карт
    
    public func toggleFreezeCard(id: UUID) {
        guard prepareForWrite(.cards) else { return }
        if let index = cards.firstIndex(where: { $0.id == id }) {
            cards[index].isFrozen.toggle()
            saveCards()
        }
    }

    /// Добавляет карту. Полный номер уходит в Keychain, в файле карт остаются только последние 4 цифры.
    public func addCard(_ card: Card, number: String) {
        guard prepareForWrite(.cards) else { return }
        let digits = number.filter { $0.isNumber }
        if !digits.isEmpty && !CardSecretsStore.setNumber(digits, for: card.id) {
            print("⚠️ Не удалось сохранить номер карты в Keychain")
        }
        var newCard = card
        if newCard.balanceUpdatedAt == nil {
            newCard.balanceUpdatedAt = Date()
        }
        cards.append(newCard)
        saveCards()
    }

    /// Сохраняет изменённую карту (реквизиты и оформление). Номер меняется, только если он передан.
    /// Если пользователь поправил баланс вручную, это новая точка отсчёта: операции старше этого момента баланс не изменят.
    public func updateCard(_ card: Card, number: String? = nil) {
        guard prepareForWrite(.cards), let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = card
        let previous = cards[index]
        updated.balanceUpdatedAt = abs(card.balance - previous.balance) > 0.0001 ? Date() : previous.balanceUpdatedAt
        if let number {
            let digits = number.filter { $0.isNumber }
            if !digits.isEmpty {
                if !CardSecretsStore.setNumber(digits, for: card.id) {
                    print("⚠️ Не удалось сохранить номер карты в Keychain")
                }
                updated.last4 = Card.lastFourDigits(of: digits)
            }
        }
        cards[index] = updated
        saveCards()
    }

    /// Полный номер карты из Keychain (nil, если его нет или устройство заблокировано)
    public func cardNumber(for id: UUID) -> String? {
        CardSecretsStore.number(for: id)
    }

    /// Карта по последним четырём цифрам из СМС
    public func card(withLast4 last4: String) -> Card? {
        cards.first { $0.last4 == last4 }
    }

    /// Ставит баланс карты из СМС, если сообщение не старее последней сверки
    public func syncCardBalance(id: UUID, balance: Double, asOf date: Date) {
        guard prepareForWrite(.cards), let index = cards.firstIndex(where: { $0.id == id }) else { return }
        if let updatedAt = cards[index].balanceUpdatedAt, date < updatedAt { return }
        cards[index].balance = balance
        cards[index].balanceUpdatedAt = date
        saveCards()
    }

    /// Применяет операцию к балансу карты и возвращает изменение. Возвращает nil, если баланс не трогали:
    /// у карты нет точки отсчёта или операция старше последней сверки.
    @discardableResult
    public func applyToCardBalance(id: UUID, delta: Double, asOf date: Date) -> Double? {
        guard prepareForWrite(.cards), let index = cards.firstIndex(where: { $0.id == id }) else { return nil }
        guard let updatedAt = cards[index].balanceUpdatedAt, date > updatedAt else { return nil }
        cards[index].balance += delta
        cards[index].balanceUpdatedAt = date
        saveCards()
        return delta
    }

    /// Откатывает изменение баланса, которое операция внесла в карту
    private func revertBalance(of transaction: Transaction) {
        guard let cardId = transaction.cardId,
              let delta = transaction.balanceDelta,
              prepareForWrite(.cards),
              let index = cards.firstIndex(where: { $0.id == cardId }) else { return }
        cards[index].balance -= delta
        saveCards()
    }

    public func deleteCard(id: UUID) {
        guard prepareForWrite(.cards) else { return }
        cards.removeAll { $0.id == id }
        saveCards()
        CardSecretsStore.deleteNumber(for: id)

        // Копилки удалённой карты без неё нигде не показываются, поэтому уходят вместе с ней
        if goals.contains(where: { $0.cardId == id }), prepareForWrite(.goals) {
            goals.removeAll { $0.cardId == id }
            saveGoals()
        }
    }

    // MARK: - API для долгов (Debts)

    public func addDebt(_ debt: Debt) {
        guard prepareForWrite(.debts) else { return }
        debts.insert(debt, at: 0)
        saveDebts()
    }

    /// Оплата: долг и разовый платёж закрываются, повторяющийся платёж переносит срок на следующий период и остаётся активным,
    /// а у кредита с графиком уменьшается остаток. Сумма меньше остатка вносит долг частично. Без суммы вносится всё,
    /// что положено (подробнее — в `Debt.applyPayment`).
    /// Возвращает запись после оплаты; nil, если такой записи нет.
    @discardableResult
    public func payDebt(id: UUID, amount: Double? = nil, now: Date = Date(), calendar: Calendar = .current) -> Debt? {
        guard prepareForWrite(.debts), let index = debts.firstIndex(where: { $0.id == id }) else { return nil }
        debts[index].applyPayment(amount, now: now, calendar: calendar)
        let paid = debts[index]
        saveDebts()
        return paid
    }

    /// Взнос в счёт долга без смены срока: остаток уменьшается, а при полном погашении запись закрывается.
    /// Нужен для досрочного взноса по кредиту с графиком и для оплаты по частям.
    @discardableResult
    public func repayDebt(id: UUID, amount: Double, now: Date = Date()) -> Debt? {
        guard prepareForWrite(.debts), let index = debts.firstIndex(where: { $0.id == id }), amount > 0 else { return nil }
        debts[index].applyRepayment(amount)
        debts[index].lastPaidAt = now
        let repaid = debts[index]
        saveDebts()
        return repaid
    }

    /// Кнопка с кружком: погашенный долг возвращается в активные, остальные оплачиваются
    public func togglePayDebt(id: UUID) {
        guard prepareForWrite(.debts), let index = debts.firstIndex(where: { $0.id == id }) else { return }
        if debts[index].isPaid {
            debts[index].isPaid = false
            saveDebts()
        } else {
            payDebt(id: id)
        }
    }

    /// Отмечает долг погашенным или возвращает в активные (кнопка «Погашен» в напоминании, действие ИИ).
    /// Повторяющийся платёж при «погашен» переносит срок вперёд.
    public func setDebtPaid(id: UUID, isPaid: Bool) {
        guard prepareForWrite(.debts), let index = debts.firstIndex(where: { $0.id == id }) else { return }
        if isPaid {
            if !debts[index].isPaid {
                payDebt(id: id)
            }
        } else if debts[index].isPaid {
            debts[index].isPaid = false
            saveDebts()
        }
    }

    /// Меняет, когда заранее напомнить о сроке долга
    public func setDebtReminder(id: UUID, reminder: DebtReminder) {
        guard prepareForWrite(.debts) else { return }
        if let index = debts.firstIndex(where: { $0.id == id }) {
            debts[index].reminder = reminder
            saveDebts()
        }
    }

    /// Сохраняет правку долга: имя, сумму, срок, направление, тип и напоминание. Признак погашения не трогает.
    public func updateDebt(_ debt: Debt) {
        guard prepareForWrite(.debts), let index = debts.firstIndex(where: { $0.id == debt.id }) else { return }
        var updated = debt
        updated.isPaid = debts[index].isPaid
        if updated.lastPaidAt == nil {
            updated.lastPaidAt = debts[index].lastPaidAt
        }
        if updated.lastPaidAmount == nil {
            updated.lastPaidAmount = debts[index].lastPaidAmount
        }
        // Сумму подняли выше прежней: прошлые взносы больше не показывают прогресс
        if let original = updated.originalAmount, updated.amount >= original {
            updated.originalAmount = nil
        }
        debts[index] = updated
        saveDebts()
    }

    public func deleteDebt(id: UUID) {
        guard prepareForWrite(.debts) else { return }
        debts.removeAll { $0.id == id }
        saveDebts()
    }

    // MARK: - API для своих напоминаний

    public func addCustomReminder(_ reminder: CustomReminder) {
        guard prepareForWrite(.reminders) else { return }
        customReminders.append(reminder)
        saveReminders()
    }

    public func updateCustomReminder(_ reminder: CustomReminder) {
        guard prepareForWrite(.reminders), let index = customReminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        customReminders[index] = reminder
        saveReminders()
    }

    public func deleteCustomReminder(id: UUID) {
        guard prepareForWrite(.reminders) else { return }
        customReminders.removeAll { $0.id == id }
        saveReminders()
    }

    // MARK: - API для копилок (Goals)

    /// Чем закончилось пополнение или снятие
    public enum GoalMoveOutcome: Equatable, Sendable {
        /// Сумма неверна или копилки нет
        case rejected
        case done
        /// Этим пополнением цель достигнута
        case reachedTarget
    }

    public func addGoal(_ goal: Goal) {
        guard prepareForWrite(.goals) else { return }
        var newGoal = goal
        if newGoal.createdAt == nil {
            newGoal.createdAt = Date()
        }
        Self.refreshCompletion(&newGoal)
        goals.append(newGoal)
        saveGoals()
    }

    /// Сохраняет правку копилки: название, цель, срок, значок, цвет и карту.
    /// Накопленная сумма и журнал остаются прежними, их меняют только пополнение и снятие.
    public func updateGoal(_ goal: Goal) {
        guard prepareForWrite(.goals), let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        var updated = goals[index]
        updated.title = goal.title
        updated.targetAmount = goal.targetAmount
        updated.deadline = goal.deadline
        updated.symbol = goal.symbol
        updated.colorHex = goal.colorHex
        updated.gradientColors = goal.gradientColors
        updated.cardId = goal.cardId
        Self.refreshCompletion(&updated)
        goals[index] = updated
        saveGoals()
    }

    public func goalsForCard(cardId: UUID) -> [Goal] {
        goals.filter { $0.cardId == cardId }
    }

    /// Пополняет копилку. Деньги остаются на карте, приложение лишь откладывает их под цель.
    @discardableResult
    public func deposit(goalID: UUID, amount: Double, note: String? = nil, date: Date = Date()) -> GoalMoveOutcome {
        guard amount.isFinite, amount > 0 else { return .rejected }
        return applyMove(goalID: goalID, signedAmount: amount, note: note, date: date)
    }

    /// Снимает деньги из копилки; больше, чем накоплено, снять нельзя
    @discardableResult
    public func withdraw(goalID: UUID, amount: Double, note: String? = nil, date: Date = Date()) -> GoalMoveOutcome {
        guard amount.isFinite, amount > 0,
              let goal = goals.first(where: { $0.id == goalID }),
              amount <= goal.currentAmount + 0.0001 else { return .rejected }
        return applyMove(goalID: goalID, signedAmount: -amount, note: note, date: date)
    }

    /// Прежнее имя пополнения: оставлено для кода, который его вызывает
    public func addFundsToGoal(id: UUID, amount: Double) {
        deposit(goalID: id, amount: amount)
    }

    /// Отменяет запись журнала: сумма копилки возвращается к тому, что было до неё
    public func removeGoalEntry(goalID: UUID, entryID: UUID) {
        guard prepareForWrite(.goals),
              let index = goals.firstIndex(where: { $0.id == goalID }),
              let entry = goals[index].entries.first(where: { $0.id == entryID }) else { return }
        goals[index].entries.removeAll { $0.id == entryID }
        goals[index].currentAmount = max(goals[index].currentAmount - entry.amount, 0)
        Self.refreshCompletion(&goals[index])
        saveGoals()
    }

    public func deleteGoal(id: UUID) {
        guard prepareForWrite(.goals) else { return }
        goals.removeAll { $0.id == id }
        saveGoals()
    }

    /// Сколько денег карты не отложено в копилках
    public func freeBalance(of card: Card) -> Double {
        max(card.balance - SavingsSummary.reserved(on: card.id, in: goals), 0)
    }

    private func applyMove(goalID: UUID, signedAmount: Double, note: String?, date: Date) -> GoalMoveOutcome {
        guard prepareForWrite(.goals), let index = goals.firstIndex(where: { $0.id == goalID }) else { return .rejected }
        let wasCompleted = goals[index].isCompleted
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        goals[index].currentAmount = max(goals[index].currentAmount + signedAmount, 0)
        goals[index].entries.append(GoalEntry(date: date, amount: signedAmount, note: (cleanNote?.isEmpty ?? true) ? nil : cleanNote))
        Self.refreshCompletion(&goals[index])
        saveGoals()
        return !wasCompleted && goals[index].isCompleted ? .reachedTarget : .done
    }

    /// Отметка «достигнута» ставится, когда сумма дошла до цели, и снимается, если сумма снова меньше
    private static func refreshCompletion(_ goal: inout Goal) {
        if goal.isCompleted {
            if goal.completedAt == nil {
                goal.completedAt = Date()
            }
        } else {
            goal.completedAt = nil
        }
    }

    // MARK: - Подсчеты и вычисления
    
    /// Общий текущий баланс (сумма всех активных балансов карт)
    public var totalBalance: Double {
        cards
            .filter { !$0.isFrozen }
            .reduce(0.0) { $0 + $1.balance }
    }
    
    /// Суммарный доход (по транзакциям)
    public var totalIncome: Double {
        transactions
            .filter { $0.type == .income }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Суммарный расход (по транзакциям)
    public var totalExpenses: Double {
        transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Суммарные расходы (для блока Spending на главном экране)
    public var totalSpending: Double {
        transactions
            .filter { $0.type == .expense }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    public var expenseByCategory: [Category: Double] {
        var result: [Category: Double] = [:]
        for t in transactions where t.type == .expense {
            result[t.category, default: 0.0] += t.amount
        }
        return result
    }
    
    // MARK: - Сохранение и загрузка
    
    private func loadData() {
        loadTransactions()
        loadCards()
        loadDebts()
        loadGoals()
        loadReminders()
        ReminderService.shared.update(from: self)
    }

    private func loadTransactions() {
        guard let loaded = readStore([Transaction].self, store: .transactions, url: fileURL, dateStrategy: .iso8601) else { return }

        // Старые транзакции хранят категории со случайными id — приводим их к постоянным
        let migrated = loaded.map { Self.withCanonicalCategory($0) }
        transactions = migrated
        if migrated != loaded {
            saveData()
        }
    }

    private func loadCards() {
        let numbersMigrated = migrateLegacyCardNumbers()
        if let loaded = readStore([Card].self, store: .cards, url: cardsURL) {
            cards = loaded
            // Старые поля number и cvv убираем из файла, только когда все номера уже лежат в Keychain
            if numbersMigrated {
                saveCards()
            }
        }
    }

    /// Старый формат cards.json хранил полный номер карты и CVV открытым текстом.
    private struct LegacyCardNumber: Decodable {
        let id: UUID
        let number: String?
    }

    /// Переносит номера карт из старого cards.json в Keychain.
    /// Возвращает true, если в файле были старые поля и все номера теперь в Keychain, то есть файл можно пересохранить без них.
    private func migrateLegacyCardNumbers() -> Bool {
        guard let data = try? Data(contentsOf: cardsURL),
              let legacy = try? JSONDecoder().decode([LegacyCardNumber].self, from: data) else {
            return false
        }
        let withNumbers = legacy.filter { !($0.number ?? "").isEmpty }
        guard !withNumbers.isEmpty else { return false }

        var allStored = true
        for item in withNumbers {
            let digits = (item.number ?? "").filter { $0.isNumber }
            if digits.isEmpty { continue }
            if !CardSecretsStore.setNumber(digits, for: item.id) {
                allStored = false
            }
        }
        if !allStored {
            print("⚠️ Не удалось перенести номера карт в Keychain, старый файл пока не меняется")
        }
        return allStored
    }

    private func loadDebts() {
        if let loaded = readStore([Debt].self, store: .debts, url: debtsURL, dateStrategy: .iso8601) {
            debts = loaded
        }
    }

    private func loadGoals() {
        if let loaded = readStore([Goal].self, store: .goals, url: goalsURL) {
            goals = loaded
        }
    }

    private func loadReminders() {
        if let loaded = readStore([CustomReminder].self, store: .reminders, url: remindersURL, dateStrategy: .iso8601) {
            customReminders = loaded
        }
    }

    /// Заменяет категорию транзакции на встроенную с тем же названием и типом (с постоянным id)
    private static func withCanonicalCategory(_ transaction: Transaction) -> Transaction {
        guard let canonical = Category.defaultCategories.first(where: {
                  $0.name == transaction.category.name && $0.type == transaction.category.type
              }),
              canonical != transaction.category else {
            return transaction
        }
        var fixed = transaction
        fixed.category = canonical
        return fixed
    }

    /// Читает массив из файла хранилища. Данные при этом никогда не теряются:
    /// - файла нет — возвращает nil, это чистый старт;
    /// - файл есть, но не читается (например, телефон заблокирован) — хранилище закрывается для записи,
    ///   пока файл не удастся прочитать;
    /// - файл прочитан, но не декодируется (повреждён или изменилась схема) — он переносится
    ///   в резервную копию, чтобы следующее сохранение его не затёрло.
    private func readStore<T: Decodable>(
        _ type: [T].Type,
        store: Store,
        url: URL,
        dateStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate
    ) -> [T]? {
        unreadableStores.remove(store)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            print("⚠️ Не удалось прочитать \(url.lastPathComponent), запись заблокирована: \(error.localizedDescription)")
            unreadableStores.insert(store)
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = dateStrategy
            return try decoder.decode(type, from: data)
        } catch {
            print("⚠️ Не удалось декодировать \(url.lastPathComponent): \(error)")
            if !moveToBackup(url) {
                unreadableStores.insert(store)
            }
            return nil
        }
    }

    /// Переносит нечитаемый файл в `<имя>.corrupt-<время>.json` рядом с оригиналом
    private func moveToBackup(_ url: URL) -> Bool {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = url.deletingPathExtension().lastPathComponent
        let backupURL = url.deletingLastPathComponent().appendingPathComponent("\(name).corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: backupURL)
            print("⚠️ Файл сохранён как \(backupURL.lastPathComponent)")
            return true
        } catch {
            print("⚠️ Не удалось сохранить резервную копию \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    /// Проверяет, что файл хранилища можно безопасно перезаписывать. Если раньше он не читался, пробует загрузить его снова.
    private func prepareForWrite(_ store: Store) -> Bool {
        if unreadableStores.contains(store) {
            switch store {
            case .transactions: loadTransactions()
            case .cards: loadCards()
            case .debts: loadDebts()
            case .goals: loadGoals()
            case .reminders: loadReminders()
            }
        }
        return !unreadableStores.contains(store)
    }

    private func saveData() {
        guard !unreadableStores.contains(.transactions) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(transactions)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить транзакции: \(error.localizedDescription)")
        }
        // Вечернее напоминание не приходит в день, когда операции уже записаны
        ReminderService.shared.update(from: self)
    }
    
    private func saveCards() {
        guard !unreadableStores.contains(.cards) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cards)
            try data.write(to: cardsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить карты: \(error.localizedDescription)")
        }
        ReminderService.shared.update(from: self)
    }
    
    private func saveDebts() {
        guard !unreadableStores.contains(.debts) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(debts)
            try data.write(to: debtsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить долги: \(error.localizedDescription)")
        }
        ReminderService.shared.update(from: self)
    }
    
    private func saveGoals() {
        guard !unreadableStores.contains(.goals) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(goals)
            try data.write(to: goalsURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить цели: \(error.localizedDescription)")
        }
        ReminderService.shared.update(from: self)
    }

    private func saveReminders() {
        guard !unreadableStores.contains(.reminders) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(customReminders)
            try data.write(to: remindersURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("⚠️ Не удалось сохранить напоминания: \(error.localizedDescription)")
        }
        ReminderService.shared.update(from: self)
    }
}

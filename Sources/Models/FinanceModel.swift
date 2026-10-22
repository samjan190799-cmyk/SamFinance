import Foundation

/// Тип транзакции: доход или расход
public enum TransactionType: String, Codable, Sendable, CaseIterable {
    case income = "income"
    case expense = "expense"
}

/// Категория транзакции
public struct Category: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let icon: String // Имя системной иконки SF Symbols
    public let colorHex: String // Hex-код цвета для отображения
    public let type: TransactionType
    
    public init(id: UUID = UUID(), name: String, icon: String, colorHex: String, type: TransactionType) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.type = type
    }
    
    /// Предопределенный список категорий по умолчанию.
    /// Идентификаторы фиксированы: категория сохраняется целиком внутри каждой транзакции,
    /// и случайные UUID при каждом запуске превращали одну и ту же категорию в разные.
    /// Менять существующие номера нельзя, новые категории добавляются в конец с новым номером.
    public static let defaultCategories: [Category] = [
        Category(id: stableID(1), name: "Зарплата", icon: "briefcase.fill", colorHex: "#34C759", type: .income),
        Category(id: stableID(2), name: "Фриланс", icon: "laptopcomputer", colorHex: "#007AFF", type: .income),
        Category(id: stableID(3), name: "Инвестиции", icon: "chart.line.uptrend.xyaxis", colorHex: "#AF52DE", type: .income),
        Category(id: stableID(4), name: "Продукты", icon: "cart.fill", colorHex: "#FF9500", type: .expense),
        Category(id: stableID(5), name: "Транспорт", icon: "car.fill", colorHex: "#5AC8FA", type: .expense),
        Category(id: stableID(6), name: "Рестораны", icon: "fork.knife", colorHex: "#FF2D55", type: .expense),
        Category(id: stableID(7), name: "Жилье", icon: "house.fill", colorHex: "#5E5CE6", type: .expense),
        Category(id: stableID(8), name: "Развлечения", icon: "gamecontroller.fill", colorHex: "#FFCC00", type: .expense),
        Category(id: stableID(9), name: "Здоровье", icon: "heart.text.square.fill", colorHex: "#FF3B30", type: .expense),
        Category(id: stableID(10), name: "Долги", icon: "banknote.fill", colorHex: "#A2845E", type: .expense),
        Category(id: stableID(11), name: "Прочее", icon: "ellipsis.circle.fill", colorHex: "#8E8E93", type: .expense),
        Category(id: stableID(12), name: "Переводы", icon: "arrow.left.arrow.right", colorHex: "#5AC8FA", type: .expense),
        Category(id: stableID(13), name: "Переводы", icon: "arrow.left.arrow.right", colorHex: "#5AC8FA", type: .income)
    ]

    /// Постоянный идентификатор встроенной категории по её номеру
    private static func stableID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "5A3F1C00-0000-4000-8000-%012ld", number))!
    }
}

/// Банковская карта пользователя
public struct Card: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var last4: String // Последние 4 цифры номера. Полный номер лежит в Keychain (CardSecretsStore), CVV не хранится
    public var holderName: String
    public var balance: Double
    public var type: String // Назначение карты ("Карта для покупок")
    public var colorHex: String // Основной цвет свечения
    public var gradientColors: [String] // Цвета для градиентного фона
    public var isFrozen: Bool
    public var expiryDate: String // Срок действия (MM/YY)
    public var balanceUpdatedAt: Date? // На какой момент верен баланс: операции старше него баланс не меняют

    // Оформление и подробности карты; у старых карт их нет
    public var bankName: String? // Банк: подпись на карте
    public var network: CardNetwork? // Платёжная система
    public var pattern: CardPattern? // Узор на лицевой стороне
    public var symbol: String? // Значок рядом с назначением (SF Symbol)

    public init(id: UUID = UUID(), last4: String, holderName: String, balance: Double, type: String = "Digital card", colorHex: String, gradientColors: [String], isFrozen: Bool = false, expiryDate: String = "08/29", balanceUpdatedAt: Date? = nil, bankName: String? = nil, network: CardNetwork? = nil, pattern: CardPattern? = nil, symbol: String? = nil) {
        self.id = id
        self.last4 = last4
        self.holderName = holderName
        self.balance = balance
        self.type = type
        self.colorHex = colorHex
        self.gradientColors = gradientColors
        self.isFrozen = isFrozen
        self.expiryDate = expiryDate
        self.balanceUpdatedAt = balanceUpdatedAt
        self.bankName = bankName
        self.network = network
        self.pattern = pattern
        self.symbol = symbol
    }

    /// Последние 4 цифры из номера в любом виде (с пробелами или без)
    public static func lastFourDigits(of number: String) -> String {
        String(number.filter { $0.isNumber }.suffix(4))
    }

    private enum CodingKeys: String, CodingKey {
        case id, last4, holderName, balance, type, colorHex, gradientColors, isFrozen, expiryDate, balanceUpdatedAt
        case bankName, network, pattern, symbol
        case number // Только чтение: старые файлы хранили полный номер прямо в cards.json
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let stored = try container.decodeIfPresent(String.self, forKey: .last4) {
            last4 = stored
        } else {
            // Старый формат: полный номер уходит в Keychain при загрузке (FinanceService), здесь берём только конец
            last4 = Card.lastFourDigits(of: try container.decodeIfPresent(String.self, forKey: .number) ?? "")
        }
        holderName = try container.decode(String.self, forKey: .holderName)
        balance = try container.decode(Double.self, forKey: .balance)
        type = try container.decode(String.self, forKey: .type)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        gradientColors = try container.decode([String].self, forKey: .gradientColors)
        isFrozen = try container.decode(Bool.self, forKey: .isFrozen)
        expiryDate = try container.decode(String.self, forKey: .expiryDate)
        balanceUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .balanceUpdatedAt)
        bankName = try container.decodeIfPresent(String.self, forKey: .bankName)
        // Неизвестное значение (например, из более новой версии) не должно ломать чтение всех карт
        network = (try? container.decodeIfPresent(CardNetwork.self, forKey: .network)) ?? nil
        pattern = (try? container.decodeIfPresent(CardPattern.self, forKey: .pattern)) ?? nil
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(last4, forKey: .last4)
        try container.encode(holderName, forKey: .holderName)
        try container.encode(balance, forKey: .balance)
        try container.encode(type, forKey: .type)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(gradientColors, forKey: .gradientColors)
        try container.encode(isFrozen, forKey: .isFrozen)
        try container.encode(expiryDate, forKey: .expiryDate)
        try container.encodeIfPresent(balanceUpdatedAt, forKey: .balanceUpdatedAt)
        try container.encodeIfPresent(bankName, forKey: .bankName)
        try container.encodeIfPresent(network, forKey: .network)
        try container.encodeIfPresent(pattern, forKey: .pattern)
        try container.encodeIfPresent(symbol, forKey: .symbol)
    }
}

/// Тип долга: кредит организации или долг физическому лицу
public enum DebtType: String, Codable, Sendable {
    case credit = "credit"
    case person = "person"
}

/// Долг (взаиморасчеты с контактами или кредиты банкам)
public struct Debt: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String // Имя человека или банка
    public var amount: Double
    public var dueDate: Date
    public var isLent: Bool // true - мне должны (Lent), false - я должен (Borrowed)
    public var isPaid: Bool // Статус погашения
    public var type: DebtType
    
    public init(id: UUID = UUID(), name: String, amount: Double, dueDate: Date = Date(), isLent: Bool, isPaid: Bool = false, type: DebtType = .person) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.isLent = isLent
        self.isPaid = isPaid
        self.type = type
    }
}

/// Движение денег по копилке: пополнение (сумма больше нуля) или снятие (меньше нуля)
public struct GoalEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var date: Date
    public var amount: Double
    public var note: String?

    public init(id: UUID = UUID(), date: Date = Date(), amount: Double, note: String? = nil) {
        self.id = id
        self.date = date
        self.amount = amount
        self.note = note
    }
}

/// Накопительная цель (Копилка): деньги остаются на карте, приложение лишь откладывает их под цель
public struct Goal: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var cardId: UUID? // Карта, на которой лежат деньги; у общей копилки её нет
    public var title: String // Название цели (например, "На подарки")
    public var targetAmount: Double // Целевая сумма
    public var currentAmount: Double // Накоплено на данный момент
    public var colorHex: String // Цвет свечения
    public var gradientColors: [String] // Цвета градиента карточки цели

    // Подробности копилки; у старых копилок их нет
    public var deadline: Date? // К какому дню нужно накопить
    public var symbol: String? // Значок (SF Symbol)
    public var createdAt: Date?
    public var completedAt: Date? // Когда сумма впервые дошла до цели; пусто, если цель не достигнута
    public var entries: [GoalEntry] // Журнал пополнений и снятий

    public init(id: UUID = UUID(), cardId: UUID? = nil, title: String, targetAmount: Double, currentAmount: Double = 0.0, colorHex: String, gradientColors: [String], deadline: Date? = nil, symbol: String? = nil, createdAt: Date? = nil, completedAt: Date? = nil, entries: [GoalEntry] = []) {
        self.id = id
        self.cardId = cardId
        self.title = title
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.colorHex = colorHex
        self.gradientColors = gradientColors
        self.deadline = deadline
        self.symbol = symbol
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case id, cardId, title, targetAmount, currentAmount, colorHex, gradientColors
        case deadline, symbol, createdAt, completedAt, entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cardId = try container.decodeIfPresent(UUID.self, forKey: .cardId)
        title = try container.decode(String.self, forKey: .title)
        targetAmount = try container.decode(Double.self, forKey: .targetAmount)
        currentAmount = try container.decode(Double.self, forKey: .currentAmount)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        gradientColors = try container.decode([String].self, forKey: .gradientColors)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        // Файлы прежних версий журнала не знали
        entries = try container.decodeIfPresent([GoalEntry].self, forKey: .entries) ?? []
    }
}

/// Модель финансовой транзакции
public struct Transaction: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var amount: Double
    public var type: TransactionType
    public var category: Category
    public var date: Date
    public var notes: String?
    
    // Брендирование транзакции под новый дизайн
    public var brandName: String? // Например, "Apple"
    public var brandIcon: String? // Системная иконка или логотип (для простоты системная иконка)
    public var brandColorHex: String? // Цвет точки индикатора рядом с логотипом

    // Автоматизация: все поля необязательные, чтобы старые файлы транзакций читались без потерь
    public var cardId: UUID? // Карта, с которой прошла операция
    public var externalKey: String? // Ключ СМС для защиты от дублей
    public var needsReview: Bool? // Категория подобрана наугад: стоит проверить
    public var balanceDelta: Double? // На сколько операция изменила баланс карты (чтобы откатить при удалении)

    public init(id: UUID = UUID(), title: String, amount: Double, type: TransactionType, category: Category, date: Date = Date(), notes: String? = nil, brandName: String? = nil, brandIcon: String? = nil, brandColorHex: String? = nil, cardId: UUID? = nil, externalKey: String? = nil, needsReview: Bool? = nil, balanceDelta: Double? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.date = date
        self.notes = notes
        self.brandName = brandName
        self.brandIcon = brandIcon
        self.brandColorHex = brandColorHex
        self.cardId = cardId
        self.externalKey = externalKey
        self.needsReview = needsReview
        self.balanceDelta = balanceDelta
    }
}


extension Category {
    /// Встроенные категории показываются на языке приложения, свои — как назвал их пользователь
    public var displayName: String {
        Category.displayName(for: name)
    }

    public static func displayName(for name: String) -> String {
        builtInNames.contains(name) ? NSLocalizedString(name, comment: "") : name
    }

    private static let builtInNames: Set<String> = Set(defaultCategories.map(\.name))
}

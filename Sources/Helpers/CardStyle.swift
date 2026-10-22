import Foundation

/// Платёжная система карты. Определяется по началу номера; ArCa по номеру не определить, её выбирают вручную.
public enum CardNetwork: String, Codable, CaseIterable, Identifiable, Sendable {
    case visa
    case mastercard
    case arca
    case mir
    case amex

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .arca: return "ArCa"
        case .mir: return String(localized: "МИР")
        case .amex: return "American Express"
        }
    }

    /// Определяет систему по первым цифрам номера
    public static func detect(from digits: String) -> CardNetwork? {
        guard !digits.isEmpty else { return nil }
        if digits.hasPrefix("34") || digits.hasPrefix("37") { return .amex }
        if digits.hasPrefix("4") { return .visa }
        if digits.count >= 2, let prefix = Int(digits.prefix(2)), (51...55).contains(prefix) { return .mastercard }
        if digits.count >= 4, let prefix = Int(digits.prefix(4)) {
            if (2221...2720).contains(prefix) { return .mastercard }
            if (2200...2204).contains(prefix) { return .mir }
        }
        return nil
    }
}

/// Узор на лицевой стороне карты
public enum CardPattern: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case dots
    case lines
    case waves
    case rings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return String(localized: "Без узора")
        case .dots: return String(localized: "Точки")
        case .lines: return String(localized: "Линии")
        case .waves: return String(localized: "Волны")
        case .rings: return String(localized: "Круги")
        }
    }
}

/// Готовая цветовая схема карты: два цвета градиента
public struct CardPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let colors: [String]

    public var title: String {
        switch id {
        case "lime": return String(localized: "Лайм")
        case "graphite": return String(localized: "Графит")
        case "black": return String(localized: "Чёрная")
        case "silver": return String(localized: "Серебро")
        case "ocean": return String(localized: "Океан")
        case "violet": return String(localized: "Фиолет")
        case "coral": return String(localized: "Коралл")
        case "mint": return String(localized: "Мята")
        case "sunset": return String(localized: "Закат")
        case "gold": return String(localized: "Золото")
        case "rose": return String(localized: "Роза")
        default: return String(localized: "Сланец")
        }
    }

    public static let all: [CardPreset] = [
        CardPreset(id: "lime", colors: ["#C6F432", "#B2E01E"]),
        CardPreset(id: "graphite", colors: ["#2A2B30", "#1C1D21"]),
        CardPreset(id: "black", colors: ["#000000", "#000000"]),
        CardPreset(id: "silver", colors: ["#F4F4F5", "#DCDCE0"]),
        CardPreset(id: "ocean", colors: ["#2F80ED", "#1B3A8A"]),
        CardPreset(id: "violet", colors: ["#8E5CF7", "#4B2BB8"]),
        CardPreset(id: "coral", colors: ["#FF7A59", "#E0405A"]),
        CardPreset(id: "mint", colors: ["#3DDC97", "#0F8F6A"]),
        CardPreset(id: "sunset", colors: ["#FF9A3D", "#E8366B"]),
        CardPreset(id: "gold", colors: ["#F6D365", "#C9972B"]),
        CardPreset(id: "rose", colors: ["#F7A8C4", "#D8588F"]),
        CardPreset(id: "slate", colors: ["#52606D", "#2B3640"])
    ]

    /// Схема с такими же цветами, если карта оформлена готовой схемой
    public static func matching(_ colors: [String]) -> CardPreset? {
        let wanted = colors.map { $0.uppercased() }
        return all.first { $0.colors.map { $0.uppercased() } == wanted }
    }
}

/// Значки, которые можно поставить на карту рядом с назначением (SF Symbols)
public enum CardSymbol {
    public static let all = [
        "cart.fill", "airplane", "gift.fill", "house.fill", "briefcase.fill",
        "heart.fill", "star.fill", "gamecontroller.fill", "graduationcap.fill"
    ]

    /// Название значка для VoiceOver
    public static func title(_ name: String?) -> String {
        switch name {
        case "cart.fill": return String(localized: "Покупки")
        case "airplane": return String(localized: "Путешествия")
        case "gift.fill": return String(localized: "Подарки")
        case "house.fill": return String(localized: "Дом")
        case "briefcase.fill": return String(localized: "Работа")
        case "heart.fill": return String(localized: "Любимое")
        case "star.fill": return String(localized: "Избранное")
        case "gamecontroller.fill": return String(localized: "Игры")
        case "graduationcap.fill": return String(localized: "Учёба")
        default: return String(localized: "Без значка")
        }
    }
}

/// Ввод реквизитов карты: форматирование «на лету» и проверки
public enum CardInput {
    /// Самый длинный номер карты (у American Express 15 цифр)
    public static let maxDigits = 19

    /// Только цифры 0–9
    public static func digits(_ text: String) -> String {
        text.filter { ("0"..."9").contains($0) }
    }

    /// Номер группами: 0000 0000 0000 0000, у American Express 0000 000000 00000
    public static func formatNumber(_ raw: String, network: CardNetwork? = nil) -> String {
        var all = digits(raw)
        let isAmex = network == .amex || all.hasPrefix("34") || all.hasPrefix("37")
        all = String(all.prefix(isAmex ? 15 : maxDigits))
        let groups = isAmex ? [4, 6, 5] : [4, 4, 4, 4, 3]

        var parts: [String] = []
        var index = all.startIndex
        for size in groups {
            guard index < all.endIndex else { break }
            let end = all.index(index, offsetBy: size, limitedBy: all.endIndex) ?? all.endIndex
            parts.append(String(all[index..<end]))
            index = end
        }
        return parts.joined(separator: " ")
    }

    /// Срок при вводе: «0829» и «08/29» превращаются в «08/29», а «1» и «12» остаются как есть
    public static func formatExpiry(_ raw: String) -> String {
        let all = String(digits(raw).prefix(4))
        guard all.count > 2 else { return all }
        return String(all.prefix(2)) + "/" + String(all.dropFirst(2))
    }

    /// Срок в виде ММ/ГГ или nil, если месяц или длина неверны
    public static func normalizedExpiry(_ raw: String) -> String? {
        let all = digits(raw)
        guard all.count == 4, let month = Int(all.prefix(2)), (1...12).contains(month) else { return nil }
        return String(all.prefix(2)) + "/" + String(all.suffix(2))
    }

    /// Срок истёк: карта действует до конца указанного месяца
    public static func isExpired(_ expiry: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let normalized = normalizedExpiry(expiry),
              let month = Int(normalized.prefix(2)),
              let year = Int(normalized.suffix(2)),
              let start = calendar.date(from: DateComponents(year: 2000 + year, month: month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return false
        }
        return now >= end
    }

    /// Допустимая длина номера
    public static func isValidLength(_ digits: String) -> Bool {
        (13...maxDigits).contains(digits.count)
    }

    /// Контрольная сумма по алгоритму Луна: ловит опечатки в номере
    public static func passesLuhn(_ digits: String) -> Bool {
        let numbers = digits.compactMap { $0.wholeNumberValue }
        guard numbers.count == digits.count, numbers.count >= 12 else { return false }
        var sum = 0
        for (offset, value) in numbers.reversed().enumerated() {
            var item = value
            if offset % 2 == 1 {
                item *= 2
                if item > 9 { item -= 9 }
            }
            sum += item
        }
        return sum % 10 == 0
    }
}

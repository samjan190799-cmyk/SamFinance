import Foundation

/// Результат парсинга СМС-сообщения от банка
public struct ParsedSMSTransaction: Sendable, Hashable {
    public let title: String
    /// Сумма в валюте `currency`
    public let amount: Double
    public let currency: AppCurrency
    public let type: TransactionType
    public let brandName: String?
    public let categoryName: String
    public let date: Date?
    /// Последние 4 цифры карты из маски `4318***0640`
    public let cardLast4: String?
    /// Остаток на карте после операции, если банк его прислал
    public let balanceAfter: Double?
    /// Перевод между картами (C2C): свой он или чужой, решает AutomationService по имени
    public let isTransfer: Bool
    public let counterparty: String?
    /// Категория выбрана по умолчанию, а не по магазину: стоит проверить
    public let isCategoryGuessed: Bool
    /// Ключ для защиты от дублей: карта, сумма, время и магазин
    public let dedupKey: String
}

/// Помощник для автоматического парсинга СМС-сообщений банков Армении, России и мира.
/// Сначала пробует структурный формат (IDBank, ARCA: операция, сумма, маска карты, магазин, дата, остаток),
/// затем общий разбор по ключевым словам.
public struct SMSParser {

    // MARK: - Пакетный разбор

    /// Высокоточное сканирование ленты из 100-200+ СМС сообщений
    public static func parseBatch(text: String) -> [ParsedSMSTransaction] {
        var results: [ParsedSMSTransaction] = []
        for message in splitIntoMessages(text) {
            if let parsed = parse(text: message) {
                results.append(parsed)
            }
        }
        return results
    }

    /// Делит вставленный текст на отдельные СМС
    static func splitIntoMessages(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var messages: [String] = []

        // Пустая строка между сообщениями — самый надёжный разделитель
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if lines.isEmpty { continue }

            let isStructured = lines.contains { firstMatch(cardMaskPattern, in: $0) != nil }
            var current: [String] = []
            for line in lines {
                let startsNewMessage: Bool
                if isStructured {
                    startsNewMessage = !current.isEmpty && isOperationHeader(line) && isComplete(current)
                } else {
                    startsNewMessage = !current.isEmpty && isHeaderOfSMS(line)
                }

                if startsNewMessage {
                    messages.append(current.joined(separator: "\n"))
                    current = [line]
                } else {
                    current.append(line)
                }
            }
            if !current.isEmpty {
                messages.append(current.joined(separator: "\n"))
            }
        }
        return messages
    }

    /// Строка-код операции в начале СМС: GNUM, E-POS GNUM, C2C, ATM…
    private static func isOperationHeader(_ line: String) -> Bool {
        let upper = line.uppercased()
        let headers = ["GNUM", "E-POS", "POS", "C2C", "P2P", "ATM", "MUTQ", "TRANSFER", "PAYMENT", "REFUND", "NOT ENOUGH FUNDS"]
        return headers.contains { upper.hasPrefix($0) }
    }

    /// СМС закончена, когда в ней уже есть дата или остаток. Смотрим все строки, а не только последнюю:
    /// на скриншотах после СМС бывают посторонние строки вроде «Вчера 14:32».
    private static func isComplete(_ lines: [String]) -> Bool {
        lines.contains { firstMatch(balancePattern, in: $0) != nil || firstMatch(datePattern, in: $0) != nil }
    }

    /// Проверка, является ли строка началом банковской СМС в свободном формате
    private static func isHeaderOfSMS(_ text: String) -> Bool {
        let lower = text.lowercased()
        let bankKeywords = [
            "inecobank", "ameriabank", "acba", "ardshinbank", "evocabank", "idbank", "converse", "arca", "amio", "amio bank",
            "сбербанк", "т-банк", "тинькофф", "втб", "альфа", "списание", "зачисление", "покупка", "оплата", "card", "kart"
        ]
        return bankKeywords.contains { lower.contains($0) }
    }

    // MARK: - Разбор одного сообщения

    private static let declineKeywords = [
        "not enough funds", "insufficient funds", "недостаточно средств",
        "отказ", "declined", "failed", "chhajoghvec", "anharajogh", "vcharumy chstacvec"
    ]

    /// Парсит отдельный текст сообщения и извлекает сумму, тип операции, карту, остаток и категорию
    public static func parse(text: String) -> ParsedSMSTransaction? {
        let lowercased = text.lowercased()

        // Отклонённые операции и сообщения о нехватке средств не записываем
        if declineKeywords.contains(where: { lowercased.contains($0) }) {
            return nil
        }

        if let structured = parseStructured(text: text) {
            return structured
        }
        return parseGeneric(text: text)
    }

    // MARK: - Структурный формат банков

    /// Маска карты «4318***0640». Распознанный со скриншота текст бывает с пробелами и другими звёздочками: «4318 •••0640»
    private static let cardMaskPattern = #"\b\d{4}\s?[\*•×xX]{2,}\s?(\d{4})\b"#
    private static let amountPairPattern = #"(\d[\d\s,.]*\d|\d)\s*(AMD|USD|EUR|RUB|֏|₽|€|\$)"#
    private static let balancePattern = #"(?:mnacord|balance|balans|остаток|баланс|մնացորդ)\s*:?\s*(\d[\d\s,.]*)"#
    private static let datePattern = #"\b(\d{2}[./-]\d{2}[./-]\d{2,4}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)\b"#

    private static func parseStructured(text: String) -> ParsedSMSTransaction? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let flat = lines.joined(separator: " ")
        guard let maskMatch = firstMatch(cardMaskPattern, in: flat),
              let maskRange = Range(maskMatch.range, in: flat),
              let last4 = capture(1, of: maskMatch, in: flat) else {
            return nil
        }

        // Сумма стоит до маски карты. Если указаны две (например, USD и эквивалент в AMD), берём в драмах.
        let head = String(flat[..<maskRange.lowerBound])
        let pairs = amountPairs(in: head)
        guard let chosen = pairs.last(where: { $0.currency == .amd }) ?? pairs.last else {
            return nil
        }

        // Код операции ищем до строки с маской: на скриншоте перед СМС может стоять имя отправителя или время
        let maskIndex = lines.firstIndex { firstMatch(cardMaskPattern, in: $0) != nil } ?? 0
        let operation = (lines[...maskIndex].first(where: isOperationHeader) ?? lines[0]).uppercased()
        let details = detailLines(in: lines)
        let firstDetail = details.first ?? ""
        let date = extractDate(from: flat)
        let balance = extractBalance(from: flat)

        let isTransfer = operation.contains("C2C") || operation.contains("P2P") || operation.contains("TRANSFER")
        var type: TransactionType = .expense
        var counterparty: String? = nil
        var merchant = ""
        var title: String
        var categoryName: String
        var guessed = false

        if isTransfer {
            let direction = transferDirection(details: details)
            type = direction
            let name = cleanCounterparty(firstDetail)
            counterparty = name.isEmpty ? nil : name
            if direction == .income {
                title = name.isEmpty ? "Входящий перевод" : "Перевод от \(prettify(name))"
            } else {
                title = name.isEmpty ? "Перевод" : "Перевод · \(prettify(name))"
            }
            categoryName = "Переводы"
            merchant = name
        } else {
            merchant = stripCountry(firstDetail)
            let combined = (merchant + " " + operation).lowercased()
            let isIncome = ["MUTQ", "CREDIT", "REFUND", "RETURN", "SALARY", "ЗАЧИСЛ", "ПОПОЛН"].contains { operation.contains($0) }
            type = isIncome ? .income : .expense

            if operation.contains("ATM") {
                title = "Снятие наличных"
                categoryName = "Прочее"
            } else if let match = categoryRule(for: combined) {
                title = merchant.isEmpty ? "Операция по карте •••• \(last4)" : prettify(merchant)
                categoryName = match.category
            } else {
                title = merchant.isEmpty ? "Операция по карте •••• \(last4)" : prettify(merchant)
                categoryName = type == .income ? "Зарплата" : "Прочее"
                guessed = true
            }
        }

        let key = dedupKey(last4: last4, amount: chosen.value, date: date, merchant: merchant)
        return ParsedSMSTransaction(
            title: title,
            amount: chosen.value,
            currency: chosen.currency,
            type: type,
            brandName: merchant.isEmpty ? nil : prettify(merchant),
            categoryName: categoryName,
            date: date,
            cardLast4: last4,
            balanceAfter: balance,
            isTransfer: isTransfer,
            counterparty: counterparty,
            isCategoryGuessed: guessed,
            dedupKey: key
        )
    }

    private struct AmountPair {
        let value: Double
        let currency: AppCurrency
    }

    private static func amountPairs(in text: String) -> [AmountPair] {
        allMatches(amountPairPattern, in: text).compactMap { match in
            guard let rawNumber = capture(1, of: match, in: text),
                  let rawCurrency = capture(2, of: match, in: text),
                  let value = parseNumber(rawNumber),
                  value > 0, value < 100_000_000 else {
                return nil
            }
            return AmountPair(value: value, currency: currency(from: rawCurrency))
        }
    }

    private static func currency(from token: String) -> AppCurrency {
        switch token.uppercased() {
        case "USD", "$": return .usd
        case "EUR", "€": return .eur
        case "RUB", "₽": return .rub
        default: return .amd
        }
    }

    /// Строки между маской карты и датой: магазин или получатель, страна
    private static func detailLines(in lines: [String]) -> [String] {
        guard let maskIndex = lines.firstIndex(where: { firstMatch(cardMaskPattern, in: $0) != nil }) else { return [] }
        var result: [String] = []
        for line in lines[(maskIndex + 1)...] {
            if firstMatch(datePattern, in: line) != nil || firstMatch(balancePattern, in: line) != nil {
                break
            }
            result.append(line)
        }
        return result
    }

    /// Направление перевода: «TO:» и «-OUT» — исходящий, «FROM:» и «-IN» — входящий
    private static func transferDirection(details: [String]) -> TransactionType {
        let joined = details.joined(separator: " ").uppercased()
        if joined.contains("FROM:") || joined.contains("-IN") {
            return .income
        }
        return .expense
    }

    private static func cleanCounterparty(_ line: String) -> String {
        var result = line.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        for prefix in ["TO:", "FROM:", "To:", "From:"] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count))
        }
        for suffix in ["-IN", "-OUT"] where result.uppercased().hasSuffix(suffix) {
            result = String(result.dropLast(suffix.count))
        }
        return stripCountry(result).trimmingCharacters(in: .whitespaces)
    }

    /// Убирает код страны в конце строки: «ARARAT MARKET, AM» → «ARARAT MARKET»
    private static func stripCountry(_ line: String) -> String {
        line
            .replacingOccurrences(of: #",\s*[A-Za-z]{2}\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
    }

    /// «ARARAT MARKET» → «Ararat Market»; уже смешанный регистр («Temu.com») не трогаем
    private static func prettify(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == trimmed.uppercased() ? trimmed.capitalized : trimmed
    }

    /// Общий ключ дублей: по нему же сверяются операции, которые нашёл облачный ИИ
    static func dedupKey(last4: String?, amount: Double, date: Date?, merchant: String) -> String {
        let stamp = Int(date?.timeIntervalSince1970 ?? 0)
        let normalized = merchant.lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(last4 ?? "-")|\(amount)|\(stamp)|\(normalized)"
    }

    // MARK: - Общий разбор по ключевым словам

    private static func parseGeneric(text: String) -> ParsedSMSTransaction? {
        let lowercased = text.lowercased()

        // 1. Очистка текста от номеров карт, телефонов, остатков и служебных кодов
        let sanitizedText = sanitizeTextForAmountExtraction(text)

        // 2. Извлечение суммы
        guard let amount = extractAmount(from: sanitizedText), amount > 0, amount < 100_000_000 else {
            return nil
        }

        // 3. Определение типа операции (доход или расход)
        var type: TransactionType = .expense
        let incomeWords = [
            "зачисление", "пополнение", "получен перевод", "зарплата", "refund", "received", "deposit",
            "mutq", "veradardz", "stacvats", "incass"
        ]
        if incomeWords.contains(where: { lowercased.contains($0) }) {
            type = .income
        }

        let expenseWords = ["elq hashvic", "списание", "оплата", "покупка", "vcharum"]
        if expenseWords.contains(where: { lowercased.contains($0) }) {
            type = .expense
        }

        // 4. Определение бренда и категории
        var brandName: String? = nil
        var categoryName = type == .income ? "Зарплата" : "Прочее"
        var guessed = true

        if lowercased.contains("idbank") || lowercased.contains("elq hashvic") || lowercased.contains("mutq hashvin") {
            brandName = "IDBank"
            if lowercased.contains("elq hashvic") { type = .expense }
            if lowercased.contains("mutq hashvin") { type = .income }
        } else if hasWord("arca", in: lowercased) {
            brandName = "ARCA System"
        } else if hasWord("amio", in: lowercased) || hasWord("varky", in: lowercased) || hasWord("vark", in: lowercased) {
            brandName = "AMIO Bank"
            categoryName = "Долги"
            guessed = false
        }

        if let rule = categoryRule(for: lowercased) {
            categoryName = rule.category
            guessed = false
            if let brand = rule.brand {
                brandName = brand
            }
        }

        if brandName == nil || brandName == "IDBank" || brandName == "ARCA System" {
            if let found = extractPossibleBrand(from: text) {
                brandName = found
            }
        }

        let parsedDate = extractDate(from: text)
        let title = brandName ?? (type == .income ? "Пополнение счета" : "Операция по карте")
        let last4 = firstMatch(cardMaskPattern, in: text).flatMap { capture(1, of: $0, in: text) }

        return ParsedSMSTransaction(
            title: title,
            amount: amount,
            currency: .amd,
            type: type,
            brandName: brandName,
            categoryName: categoryName,
            date: parsedDate,
            cardLast4: last4,
            balanceAfter: extractBalance(from: text),
            isTransfer: false,
            counterparty: nil,
            isCategoryGuessed: guessed,
            dedupKey: dedupKey(last4: last4, amount: amount, date: parsedDate, merchant: brandName ?? "")
        )
    }

    // MARK: - Правила категорий

    private struct CategoryRule {
        let keywords: [String]
        let category: String
        let brand: String?
    }

    private static let categoryRules: [CategoryRule] = [
        CategoryRule(keywords: ["sas"], category: "Продукты", brand: "SAS Supermarket"),
        CategoryRule(keywords: ["yerevan city", "ереван сити"], category: "Продукты", brand: "Yerevan City"),
        CategoryRule(keywords: ["carrefour"], category: "Продукты", brand: "Carrefour"),
        CategoryRule(
            keywords: ["nor zovq", "kaiser", "evrika", "магнит", "пятерочка", "перекресток", "lenta", "grocery", "supermarket", "market", "ararat", "bakery", "bread"],
            category: "Продукты",
            brand: nil
        ),
        CategoryRule(keywords: ["gg"], category: "Транспорт", brand: "gg Taxi"),
        CategoryRule(keywords: ["yandex go", "yandex.go", "yandex.taxi", "яндекс"], category: "Транспорт", brand: "Yandex Go"),
        CategoryRule(
            keywords: ["metro", "cps", "ran oil", "flash", "uber", "лукойл", "taxi", "fuel", "petrol", "gas station"],
            category: "Транспорт",
            brand: nil
        ),
        CategoryRule(
            keywords: ["tavern yerevan", "lavash", "dargett", "cinnabon", "paul", "starbucks", "kfc", "mcdonalds", "burger king", "cafe", "restaurant", "кофе", "pizza", "coffee", "bar", "pub", "grill"],
            category: "Рестораны",
            brand: nil
        ),
        CategoryRule(keywords: ["pharm", "pharmacy", "аптека", "doctor", "клиника", "clinic", "hospital", "medical"], category: "Здоровье", brand: nil),
        CategoryRule(
            keywords: ["steam", "playstation", "netflix", "spotify", "кино", "cinema", "yandex plus", "apple.com/bill", "google play", "youtube"],
            category: "Развлечения",
            brand: nil
        ),
        CategoryRule(keywords: ["ucom", "beeline", "vivacell", "gazprom armenia", "yerevan water", "electric networks"], category: "Жилье", brand: nil),
        CategoryRule(keywords: ["temu", "aliexpress", "amazon", "wildberries", "ozon"], category: "Прочее", brand: nil)
    ]

    /// Первое подходящее правило. Слова ищутся целиком, чтобы «gg» не находилось внутри чужих слов.
    private static func categoryRule(for lowercased: String) -> CategoryRule? {
        categoryRules.first { rule in
            rule.keywords.contains { hasWord($0, in: lowercased) }
        }
    }

    private static func hasWord(_ word: String, in lowercased: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
        return lowercased.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Очистка текста и извлечение чисел

    /// Очищает текст от 16-значных номеров карт, скрытых номеров карт, телефонов, остатка счета и служебных кодов
    private static func sanitizeTextForAmountExtraction(_ text: String) -> String {
        var result = text

        // 1. Скрываем остаток на счете (Balans: 45000 AMD / Остаток: 12000 RUB / Dostupno: 5000 / MNACORD: 9,403.90)
        let balancePatterns = [
            #"\b(?:balans|balance|mnacord|ostatok|остаток|hashvum|hashvin|dostupno|доступно|dostupny)\b[:\s]*[A-Za-z֏₽\$€]*\s*(\d{1,3}(?:[\s,]\d{3})*(?:[.,]\d{1,2})?)"#,
            #"\b(?:остаток|баланс)\b[:\s]*(\d{1,3}(?:[\s,]\d{3})*(?:[.,]\d{1,2})?)\s*(?:руб|₽|amd|֏|dram|драм|usd|\$)?"#
        ]
        for pattern in balancePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "[BALANS_MASKED]")
            }
        }

        // 2. Скрываем 16-значные номера карт (например, 4318 2900 1046 4994 или 4318-2900-1046-4994 или 4318290010464994)
        let cardNumberPatterns = [
            #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#,
            #"\b\d{4,6}[\*xX]+\d{4}\b"#,
            #"\b(?:\*|x|X){4,12}\d{4}\b"#,
            #"(?:card|kart|карта|карт|счет|hashiv)\s*[:#]?\s*\*?\d{4,16}\b"#
        ]
        for pattern in cardNumberPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "[CARD_MASKED]")
            }
        }

        // 3. Скрываем номера телефонов (например, +37498123456 или 89991234567)
        let phonePattern = #"\b(?:\+?374|\+?7|8)[\s-]?\(?\d{2,3}\)?[\s-]?\d{3}[\s-]?\d{2,4}\b"#
        if let regex = try? NSRegularExpression(pattern: phonePattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "[PHONE_MASKED]")
        }

        // 4. Скрываем коды авторизации / транзакций (Auth: 89123, ID: 12345678)
        let codePattern = #"\b(?:auth|code|id|ref|kod|kod:|spravka|справка|код|авторизация)\s*[:#]?\s*\d{4,12}\b"#
        if let regex = try? NSRegularExpression(pattern: codePattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "[CODE_MASKED]")
        }

        return result
    }

    /// Переводит число из СМС в Double. Последний разделитель с 1–2 цифрами считается десятичным,
    /// остальные — разделителями тысяч: «3,500.00», «12.5», «1 234,50» и «3,500».
    static func parseNumber(_ raw: String) -> Double? {
        let cleaned = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }

        guard let lastSeparator = cleaned.lastIndex(where: { $0 == "." || $0 == "," }) else {
            return Double(cleaned)
        }

        let fraction = String(cleaned[cleaned.index(after: lastSeparator)...])
        if (1...2).contains(fraction.count) {
            let integerPart = String(cleaned[..<lastSeparator].filter { $0.isNumber })
            return Double(integerPart + "." + fraction)
        }
        return Double(cleaned.filter { $0.isNumber })
    }

    /// Извлекает числовую сумму из очищенного текста СМС
    private static func extractAmount(from text: String) -> Double? {
        let patterns = [
            #"\b(\d{1,3}(?:[\s\u{00A0},]\d{3})*(?:[.,]\d{1,2})?)\s*(?:amd|֏|dram|драм|руб|руб.|рублей|₽|usd|\$|eur|€)\b"#,
            #"(?:amd|֏|dram|драм|руб|руб.|рублей|₽|usd|\$|eur|€)\s*(\d{1,3}(?:[\s\u{00A0},]\d{3})*(?:[.,]\d{1,2})?)\b"#,
            #"\b(?:vcharum|poxancum|vcharvel|tranzakcia|transakcia|оплата|списание|зачисление|покупка|расход|доход|payment|charge|spent|amount)\b[^\d]*?(\d{1,3}(?:[\s\u{00A0},]\d{3})*(?:[.,]\d{1,2})?)\b"#
        ]

        for pattern in patterns {
            if let match = firstMatch(pattern, in: text),
               let rawNumber = capture(1, of: match, in: text),
               let value = parseNumber(rawNumber),
               value > 0, value < 100_000_000 {
                return value
            }
        }

        // Безопасный фолбэк: ищем числа от 10 до 1,000,000 без суффиксов карт
        for match in allMatches(#"\b(\d{1,6}(?:[.,]\d{1,2})?)\b"#, in: text) {
            if let rawNumber = capture(1, of: match, in: text),
               let value = parseNumber(rawNumber),
               value >= 10, value <= 1_000_000 {
                return value
            }
        }

        return nil
    }

    /// Остаток на карте после операции: MNACORD / BALANCE / Остаток
    private static func extractBalance(from text: String) -> Double? {
        guard let match = firstMatch(balancePattern, in: text),
              let raw = capture(1, of: match, in: text) else {
            return nil
        }
        return parseNumber(raw)
    }

    /// Попытка извлечь имя бренда или локации из армянской или международной СМС
    private static func extractPossibleBrand(from text: String) -> String? {
        let patterns = [
            #"point:\s*([a-zA-Z0-9\s\.\-\"\']{3,20})\b"#,
            #"at\s+([a-zA-Z0-9\s\.\-\"\']{3,20})\b"#,
            #"в\s+([а-яА-Яa-zA-Z0-9\s\.\-\"\']{3,20})\b"#,
            #"оплата\s+([а-яА-Яa-zA-Z0-9\s\.\-\"\']{3,20})\b"#
        ]

        for pattern in patterns {
            if let match = firstMatch(pattern, in: text),
               let brand = capture(1, of: match, in: text)?.trimmingCharacters(in: .whitespacesAndNewlines),
               brand.count >= 3 {
                return brand
            }
        }
        return nil
    }

    /// Извлекает точную дату и время операции из текста СМС
    private static func extractDate(from text: String) -> Date? {
        let formatters: [DateFormatter] = {
            let formats = [
                "dd.MM.yyyy HH:mm", "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy",
                "dd/MM/yyyy HH:mm", "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy",
                "dd/MM/yy HH:mm", "dd/MM/yy HH:mm:ss", "dd/MM/yy",
                "dd.MM.yy HH:mm", "dd.MM.yy HH:mm:ss", "dd.MM.yy",
                "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"
            ]
            return formats.map { format in
                let df = DateFormatter()
                df.dateFormat = format
                df.locale = Locale(identifier: "en_US_POSIX")
                return df
            }
        }()

        let patterns = [
            datePattern,
            #"\b(\d{4}[./-]\d{2}[./-]\d{2}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)\b"#
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern, in: text, options: []),
               let dateString = capture(1, of: match, in: text) {
                for df in formatters {
                    if let date = df.date(from: dateString), isPlausibleSMSDate(date) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    /// Отсекает заведомо неверные даты. Формат «yyyy» принимает двузначный год «26» как 26 год н. э.,
    /// и без этой проверки импорт записывал бы операции на две тысячи лет назад; дата из будущего в СМС тоже невозможна.
    private static func isPlausibleSMSDate(_ date: Date) -> Bool {
        let earliest = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2000, month: 1, day: 1).date ?? .distantPast
        let latest = Date().addingTimeInterval(24 * 60 * 60)
        return date >= earliest && date <= latest
    }

    // MARK: - Регулярные выражения

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    private static func allMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    private static func capture(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}

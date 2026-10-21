import Foundation

/// Результат парсинга СМС-сообщения от банка
public struct ParsedSMSTransaction: Sendable, Hashable {
    public let title: String
    public let amount: Double
    public let type: TransactionType
    public let brandName: String?
    public let categoryName: String
    public let date: Date?
}

/// Продвинутый помощник для автоматического парсинга СМС-сообщений банков Армении, России и мира
public struct SMSParser {
    
    /// Высокоточное сканирование ленты из 100-200+ СМС сообщений
    public static func parseBatch(text: String) -> [ParsedSMSTransaction] {
        var results: [ParsedSMSTransaction] = []
        let rawLines = text.components(separatedBy: .newlines)
        var currentChunkLines: [String] = []
        
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            if isHeaderOfSMS(trimmed) && !currentChunkLines.isEmpty {
                let fullChunk = currentChunkLines.joined(separator: " ")
                if let parsed = parse(text: fullChunk) {
                    results.append(parsed)
                }
                currentChunkLines = [trimmed]
            } else {
                currentChunkLines.append(trimmed)
            }
        }
        
        if !currentChunkLines.isEmpty {
            let fullChunk = currentChunkLines.joined(separator: " ")
            if let parsed = parse(text: fullChunk) {
                results.append(parsed)
            }
        }
        
        return results
    }
    
    /// Проверка, является ли строка началом банковской СМС
    private static func isHeaderOfSMS(_ text: String) -> Bool {
        let lower = text.lowercased()
        let bankKeywords = [
            "inecobank", "ameriabank", "acba", "ardshinbank", "evocabank", "idbank", "converse", "arca", "amio", "amio bank",
            "сбербанк", "т-банк", "тинькофф", "втб", "альфа", "списание", "зачисление", "покупка", "оплата", "card", "kart"
        ]
        return bankKeywords.contains { lower.contains($0) }
    }
    
    /// Парсит отдельный текст сообщения и извлекает сумму, тип операций и категории
    public static func parse(text: String) -> ParsedSMSTransaction? {
        let lowercased = text.lowercased()
        
        // 0. Игнорируем отклоненные операции и сообщения о нехватке средств
        let declineKeywords = [
            "not enough funds", "insufficient funds", "недостаточно средств",
            "отказ", "declined", "failed", "chhajoghvec", "anharajogh", "vcharumy chstacvec"
        ]
        if declineKeywords.contains(where: { lowercased.contains($0) }) {
            return nil
        }
        
        // 1. Очистка текста от номеров карт, телефонов, остатков и служебных кодов
        let sanitizedText = sanitizeTextForAmountExtraction(text)
        
        // 2. Извлечение суммы
        guard let amount = extractAmount(from: sanitizedText), amount > 0, amount < 100_000_000 else {
            return nil
        }
        
        // 3. Определение типа операции (доход или расход)
        var type: TransactionType = .expense
        if lowercased.contains("зачисление") || 
           lowercased.contains("пополнение") || 
           lowercased.contains("получен перевод") || 
           lowercased.contains("зарплата") || 
           lowercased.contains("refund") || 
           lowercased.contains("received") || 
           lowercased.contains("deposit") ||
           lowercased.contains("mutq") ||
           lowercased.contains("veradardz") ||
           lowercased.contains("stacvats") ||
           lowercased.contains("incass") {
            type = .income
        }
        
        if lowercased.contains("elq hashvic") || lowercased.contains("списание") || lowercased.contains("оплата") || lowercased.contains("покупка") || lowercased.contains("vcharum") {
            type = .expense
        }
        
        // 4. Определение бренда и категории
        var brandName: String? = nil
        var categoryName = type == .income ? "Зарплата" : "Продукты"
        
        // Банки Армении (IDBank, ARCA, AMIO BANK, Inecobank и др)
        if lowercased.contains("idbank") || lowercased.contains("elq hashvic") || lowercased.contains("mutq hashvin") {
            brandName = "IDBank"
            if lowercased.contains("elq hashvic") { type = .expense }
            if lowercased.contains("mutq hashvin") { type = .income }
        } else if lowercased.contains("arca") {
            brandName = "ARCA System"
            categoryName = "Продукты"
        } else if lowercased.contains("amio") || lowercased.contains("varky") || lowercased.contains("vark") {
            brandName = "AMIO Bank"
            categoryName = "Долги"
        }
        
        if lowercased.contains("sas") || lowercased.contains("yerevan city") || lowercased.contains("ереван сити") || lowercased.contains("nor zovq") || lowercased.contains("carrefour") || lowercased.contains("kaiser") || lowercased.contains("evrika") || lowercased.contains("магнит") || lowercased.contains("пятерочка") || lowercased.contains("перекресток") || lowercased.contains("lenta") || lowercased.contains("grocery") || lowercased.contains("supermarket") {
            if lowercased.contains("sas") { brandName = "SAS Supermarket" }
            else if lowercased.contains("yerevan city") || lowercased.contains("ереван сити") { brandName = "Yerevan City" }
            else if lowercased.contains("carrefour") { brandName = "Carrefour" }
            else { brandName = "Супермаркет" }
            categoryName = "Продукты"
        }
        else if lowercased.contains("gg") || lowercased.contains("yandex.go") || lowercased.contains("yandex.taxi") || lowercased.contains("яндекс") || lowercased.contains("metro") || lowercased.contains("cps") || lowercased.contains("ran oil") || lowercased.contains("flash") || lowercased.contains("uber") || lowercased.contains("лукойл") {
            if lowercased.contains("gg") { brandName = "gg Taxi" }
            else if lowercased.contains("yandex") || lowercased.contains("яндекс") { brandName = "Yandex Go" }
            else { brandName = "Транспорт / АЗС" }
            categoryName = "Транспорт"
        }
        else if lowercased.contains("tavern yerevan") || lowercased.contains("lavash") || lowercased.contains("dargett") || lowercased.contains("cinnabon") || lowercased.contains("paul") || lowercased.contains("starbucks") || lowercased.contains("kfc") || lowercased.contains("mcdonalds") || lowercased.contains("burger king") || lowercased.contains("cafe") || lowercased.contains("restaurant") || lowercased.contains("кофе") {
            brandName = "Кафе / Ресторан"
            categoryName = "Рестораны"
        }
        else if lowercased.contains("pharm") || lowercased.contains("аптека") || lowercased.contains("doctor") || lowercased.contains("клиника") {
            brandName = "Аптека / Медицина"
            categoryName = "Здоровье"
        }
        else if lowercased.contains("steam") || lowercased.contains("playstation") || lowercased.contains("netflix") || lowercased.contains("spotify") || lowercased.contains("кино") || lowercased.contains("yandex plus") {
            brandName = "Подписка / Развлечения"
            categoryName = "Развлечения"
        }
        
        if brandName == nil {
            brandName = extractPossibleBrand(from: text)
        }
        
        let parsedDate = extractDate(from: text)
        let title = brandName ?? (type == .income ? "Пополнение счета" : "Операция по карте")
        
        return ParsedSMSTransaction(
            title: title,
            amount: amount,
            type: type,
            brandName: brandName,
            categoryName: categoryName,
            date: parsedDate
        )
    }
    
    /// Очищает текст от 16-значных номеров карт, скрытых номеров карт, телефонов, остатка счета и служебных кодов
    private static func sanitizeTextForAmountExtraction(_ text: String) -> String {
        var result = text
        
        // 1. Скрываем остаток на счете (Balans: 45000 AMD / Остаток: 12000 RUB / Dostupno: 5000)
        let balancePatterns = [
            #"\b(?:balans|balance|ostatok|остаток|hashvum|hashvin|dostupno|доступно|dostupny)\b[:\s]*[A-Za-z֏₽\$€]*\s*(\d{1,3}(?:[\s,]\d{3})*(?:[.,]\d{1,2})?)"#,
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
    
    /// Извлекает числовую сумму из очищенного текста СМС
    private static func extractAmount(from text: String) -> Double? {
        let patterns = [
            #"\b(\d{1,3}(?:[\s\u{00A0},]\d{3})*(?:[.,]\d{1,2})?)\s*(?:amd|֏|dram|драм|руб|руб.|рублей|₽|usd|\$|eur|€)\b"#,
            #"(?:amd|֏|dram|драм|руб|руб.|рублей|₽|usd|\$|eur|€)\s*(\d{1,3}(?:[\s\u{00A0},]\d{3})*(?:[.,]\d{1,2})?)\b"#,
            #"\b(?:vcharum|poxancum|vcharvel|tranzakcia|transakcia|оплата|списание|зачисление|покупка|расход|доход|payment|charge|spent|amount)\b[^\d]*?(\d{1,3}(?:[\s\u{00A0},]\d{3})*(?:[.,]\d{1,2})?)\b"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text) {
                    let rawStr = String(text[range])
                    let cleaned = rawStr
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: "\u{00A0}", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                    
                    if let val = Double(cleaned), val > 0, val < 100_000_000 {
                        return val
                    }
                }
            }
        }
        
        // Безопасный фолбэк: ищем числа от 10 до 1,000,000 без суффиксов карт
        let fallbackPattern = #"\b(\d{1,6}(?:[.,]\d{1,2})?)\b"#
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []),
           let matches = try? regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let rawStr = String(text[range])
                    let cleaned = rawStr.replacingOccurrences(of: ",", with: ".")
                    if let val = Double(cleaned), val >= 10, val <= 1_000_000 {
                        return val
                    }
                }
            }
        }
        
        return nil
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
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text) {
                    let brand = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
                    if brand.count >= 3 {
                        return brand
                    }
                }
            }
        }
        return nil
    }
    
    /// Извлекает точную дату и время операции из текста СМС
    private static func extractDate(from text: String) -> Date? {
        let patterns = [
            #"\b(\d{2}[./-]\d{2}[./-]\d{2,4}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)\b"#,
            #"\b(\d{4}[./-]\d{2}[./-]\d{2}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)\b"#
        ]
        
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
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    let dateStr = String(text[range])
                    for df in formatters {
                        if let date = df.date(from: dateStr), isPlausibleSMSDate(date) {
                            return date
                        }
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
}

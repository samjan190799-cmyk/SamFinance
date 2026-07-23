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
        
        // 1. Разбиваем ленту на отдельные сообщения по переносам строк или по именам банков/ключевым словам
        let rawLines = text.components(separatedBy: .newlines)
        var currentChunk = ""
        
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Если строка содержит признаки нового сообщения банка или сумму, проверяем
            let isNewMessageHeader = isHeaderOfSMS(trimmed)
            
            if isNewMessageHeader && !currentChunk.isEmpty {
                if let parsed = parse(text: currentChunk) {
                    results.append(parsed)
                }
                currentChunk = trimmed
            } else {
                if currentChunk.isEmpty {
                    currentChunk = trimmed
                } else {
                    currentChunk += " " + trimmed
                }
            }
            
            // Если в текущей строке/чанке уже можно извлечь СМС транзакцию
            if let parsed = parse(text: currentChunk) {
                results.append(parsed)
                currentChunk = ""
            }
        }
        
        if !currentChunk.isEmpty, let parsed = parse(text: currentChunk) {
            results.append(parsed)
        }
        
        return results
    }
    
    /// Проверка, является ли строка началом банковской СМС
    private static func isHeaderOfSMS(_ text: String) -> Bool {
        let lower = text.lowercased()
        let bankKeywords = [
            "inecobank", "ameriabank", "acba", "ardshinbank", "evocabank", "idbank", "converse", "vcharum", "poxancum", "vcharvel", "сбербанк", "т-банк", "тинькофф", "втб", "альфа", "списание", "зачисление", "покупка", "оплата", "card", "kart"
        ]
        return bankKeywords.contains { lower.contains($0) }
    }
    
    /// Парсит отдельный текст сообщения и извлекает сумму, тип операций и категории
    public static func parse(text: String) -> ParsedSMSTransaction? {
        let lowercased = text.lowercased()
        
        // 1. Попытка извлечь сумму (AMD, ֏, Драм, RUB, USD, EUR или любое число транзакции)
        guard let amount = extractAmount(from: text) else {
            return nil
        }
        
        // 2. Определение типа операции (доход или расход)
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
        
        // 3. Определение бренда и категории (с акцентом на армянские и международные бренды)
        var brandName: String? = nil
        var categoryName = type == .income ? "Зарплата" : "Продукты"
        
        // Магазины и Продукты Армении и мира
        if lowercased.contains("sas") || lowercased.contains("yerevan city") || lowercased.contains("ереван сити") || lowercased.contains("nor zovq") || lowercased.contains("carrefour") || lowercased.contains("kaiser") || lowercased.contains("evrika") || lowercased.contains("магнит") || lowercased.contains("пятерочка") || lowercased.contains("перекресток") || lowercased.contains("lenta") || lowercased.contains("grocery") || lowercased.contains("supermarket") {
            if lowercased.contains("sas") { brandName = "SAS Supermarket" }
            else if lowercased.contains("yerevan city") || lowercased.contains("ереван сити") { brandName = "Yerevan City" }
            else if lowercased.contains("carrefour") { brandName = "Carrefour" }
            else { brandName = "Супермаркет" }
            categoryName = "Продукты"
        }
        // Транспорт (Такси, Бензин, Метро)
        else if lowercased.contains("gg") || lowercased.contains("yandex.go") || lowercased.contains("yandex.taxi") || lowercased.contains("яндекс") || lowercased.contains("metro") || lowercased.contains("cps") || lowercased.contains("ran oil") || lowercased.contains("flash") || lowercased.contains("uber") || lowercased.contains("лукойл") {
            if lowercased.contains("gg") { brandName = "gg Taxi" }
            else if lowercased.contains("yandex") || lowercased.contains("яндекс") { brandName = "Yandex Go" }
            else { brandName = "Транспорт / АЗС" }
            categoryName = "Транспорт"
        }
        // Рестораны и Кафе
        else if lowercased.contains("tavern yerevan") || lowercased.contains("lavash") || lowercased.contains("dargett") || lowercased.contains("cinnabon") || lowercased.contains("paul") || lowercased.contains("starbucks") || lowercased.contains("kfc") || lowercased.contains("mcdonalds") || lowercased.contains("burger king") || lowercased.contains("cafe") || lowercased.contains("restaurant") || lowercased.contains("кофе") {
            brandName = "Кафе / Ресторан"
            categoryName = "Рестораны"
        }
        // Здоровье и Аптеки
        else if lowercased.contains("pharm") || lowercased.contains("аптека") || lowercased.contains("doctor") || lowercased.contains("клиника") {
            brandName = "Аптека / Медицина"
            categoryName = "Здоровье"
        }
        // Развлечения и Подписки
        else if lowercased.contains("steam") || lowercased.contains("playstation") || lowercased.contains("netflix") || lowercased.contains("spotify") || lowercased.contains("кино") || lowercased.contains("yandex plus") {
            brandName = "Подписка / Развлечения"
            categoryName = "Развлечения"
        }
        
        // Если бренд не определен, извлекаем его из текста
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
    
    /// Извлекает числовую сумму из текста СМС (с акцентом на AMD, ֏, Драм, RUB, USD, EUR)
    private static func extractAmount(from text: String) -> Double? {
        let patterns = [
            // Сумма перед или после символов валют: AMD, ֏, dram, драм, руб, $, eur
            #"\b(\d{1,3}(?:[\s,]\d{3})*(?:[.,]\d{1,2})?)\s*(?:amd|֏|dram|драм|руб|₽|usd|\$|eur|€)\b"#,
            #"(?:amd|֏|dram|драм|руб|₽|usd|\$|eur|€)\s*(\d{1,3}(?:[\s,]\d{3})*(?:[.,]\d{1,2})?)\b"#,
            // Сумма после ключевых слов операций (vcharum, poxancum, spissanie, покупка, оплата, payment, charge)
            #"\b(?:vcharum|poxancum|vcharvel|tranzakcia|transakcia|оплата|списание|зачисление|покупка|расход|доход|payment|charge|spent|amount)\b.*?\b(\d{1,3}(?:[\s,]\d{3})*(?:[.,]\d{1,2})?)\b"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text) {
                    let cleaned = text[range]
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                    
                    if let val = Double(cleaned), val > 0 {
                        return val
                    }
                }
            }
        }
        
        // Универсальный фолбек: ищем любые числа с возможной дробной частью
        let fallbackPattern = #"\b(\d{1,3}(?:\d{3})*(?:[.,]\d{1,2})?)\b"#
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []),
           let matches = try? regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            for match in matches {
                if let range = Range(match.range(at: 0), in: text) {
                    let cleaned = text[range].replacingOccurrences(of: ",", with: ".")
                    if let val = Double(cleaned), val >= 10 { // Отсекаем мелкие технические цифры вроде 4 цифр карты
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
            #"point:\s*([a-zA-Z0-9\s\.\-\"\']{3,20})\b"#, // "Point: SAS Supermarket"
            #"at\s+([a-zA-Z0-9\s\.\-\"\']{3,20})\b"#,    // "at Yerevan City"
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
                "dd/MM/yyyy HH:mm", "dd/MM/yy HH:mm", "dd.MM.yy HH:mm",
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
                        if let date = df.date(from: dateStr) {
                            return date
                        }
                    }
                }
            }
        }
        
        return nil
    }
}


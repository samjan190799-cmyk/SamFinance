import Foundation

/// Результат парсинга СМС-сообщения от банка
public struct ParsedSMSTransaction: Sendable, Hashable {
    public let title: String
    public let amount: Double
    public let type: TransactionType
    public let brandName: String?
    public let categoryName: String
}

/// Помощник для автоматического парсинга СМС-сообщений от банков
public struct SMSParser {
    
    /// Парсит блок текста со множеством СМС сообщений (историю СМС)
    public static func parseBatch(text: String) -> [ParsedSMSTransaction] {
        let lines = text.components(separatedBy: .newlines)
        var results: [ParsedSMSTransaction] = []
        var currentChunk = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            // Пробуем скомпоновать блок СМС или распознать отдельной строкой
            if let singleParsed = parse(text: trimmed) {
                results.append(singleParsed)
                currentChunk = ""
            } else {
                currentChunk += " " + trimmed
                if let chunkParsed = parse(text: currentChunk) {
                    results.append(chunkParsed)
                    currentChunk = ""
                }
            }
        }
        
        return results
    }
    
    /// Парсит текст сообщения и пытается извлечь сумму, тип транзакции и бренд/категорию
    public static func parse(text: String) -> ParsedSMSTransaction? {
        let lowercased = text.lowercased()
        
        // 1. Попытка извлечь сумму
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
           lowercased.contains("deposit") {
            type = .income
        }
        
        // 3. Определение бренда и категории
        var brandName: String? = nil
        var categoryName = type == .income ? "Зарплата" : "Развлечения"
        
        if lowercased.contains("magnit") || lowercased.contains("магнит") || lowercased.contains("pyaterochka") || lowercased.contains("пятерочка") || lowercased.contains("perekrestok") || lowercased.contains("перекресток") || lowercased.contains("ашан") || lowercased.contains("auchan") || lowercased.contains("lenta") || lowercased.contains("лента") || lowercased.contains("grocery") || lowercased.contains("supermarket") {
            brandName = "Магнит / Пятерочка"
            categoryName = "Продукты"
        } else if lowercased.contains("starbucks") || lowercased.contains("mcdonalds") || lowercased.contains("burger king") || lowercased.contains("kfc") || lowercased.contains("шоколадница") || lowercased.contains("кофе") || lowercased.contains("cafe") || lowercased.contains("restaurant") {
            brandName = "Starbucks / Кафе"
            categoryName = "Рестораны"
        } else if lowercased.contains("yandex.taxi") || lowercased.contains("яндекс.такси") || lowercased.contains("uber") || lowercased.contains("metro") || lowercased.contains("метро") || lowercased.contains("bus") || lowercased.contains("бензин") || lowercased.contains("lukoil") || lowercased.contains("лукойл") {
            brandName = "Яндекс.Такси / Метро"
            categoryName = "Транспорт"
        } else if lowercased.contains("steam") || lowercased.contains("playstation") || lowercased.contains("netflix") || lowercased.contains("spotify") || lowercased.contains("кино") || lowercased.contains("cinema") || lowercased.contains("theatre") || lowercased.contains("yandex plus") {
            brandName = "Подписка / Развлечения"
            categoryName = "Развлечения"
        } else if lowercased.contains("аптека") || lowercased.contains("pharmacy") || lowercased.contains("doctor") || lowercased.contains("больница") || lowercased.contains("клиника") || lowercased.contains("стоматология") {
            brandName = "Аптека"
            categoryName = "Здоровье"
        } else if lowercased.contains("жкх") || lowercased.contains("rent") || lowercased.contains("аренда") || lowercased.contains("коммунальные") {
            categoryName = "Жилье"
        } else if lowercased.contains("фриланс") || lowercased.contains("freelance") || lowercased.contains("заказ") || lowercased.contains("kwork") {
            categoryName = "Фриланс"
        } else if lowercased.contains("дивиденды") || lowercased.contains("акции") || lowercased.contains("invest") || lowercased.contains("брокер") {
            categoryName = "Инвестиции"
        }
        
        // Вытаскиваем бренд из текста СМС, если не определили
        if brandName == nil {
            brandName = extractPossibleBrand(from: text)
        }
        
        let title = brandName ?? (type == .income ? "Пополнение счета" : "Покупка")
        
        return ParsedSMSTransaction(
            title: title,
            amount: amount,
            type: type,
            brandName: brandName,
            categoryName: categoryName
        )
    }
    
    /// Извлекает числовую сумму из текста СМС
    private static func extractAmount(from text: String) -> Double? {
        // Регулярные выражения для поиска сумм, например "500.00", "500", "1 500", "1,500.50"
        let patterns = [
            #"\b(\d{1,3}(?:\s?\d{3})*(?:[.,]\d{2})?)\s*(?:₽|р|руб|usd|\$|eur|€)\b"#, // Сумма с валютой
            #"\b(?:сумма|amount|списание|зачисление|покупка|оплата|расход|доход|payment|charge)\b.*?\b(\d+(?:[.,]\d{2})?)\b"# // Сумма после ключевого слова
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text) {
                    let cleaned = text[range]
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                    
                    if let val = Double(cleaned) {
                        return val
                    }
                }
            }
        }
        
        // Фолбек: просто ищем первое число с точкой/запятой или без них
        let fallbackPattern = #"\b(\d+(?:[.,]\d{1,2})?)\b"#
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text) {
                let cleaned = text[range].replacingOccurrences(of: ",", with: ".")
                if let val = Double(cleaned), val > 0 {
                    return val
                }
            }
        }
        
        return nil
    }
    
    /// Попытка извлечь имя бренда из СМС (например, в кавычках или после предлогов)
    private static func extractPossibleBrand(from text: String) -> String? {
        let patterns = [
            #"in\s+([a-zA-Z0-9\s\.\-]{3,15})\b"#, // "in Starbucks"
            #"at\s+([a-zA-Z0-9\s\.\-]{3,15})\b"#, // "at Walmart"
            #"в\s+([а-яА-Яa-zA-Z0-9\s\.\-\"\']{3,15})\b"#, // "в Магните"
            #"оплата\s+([а-яА-Яa-zA-Z0-9\s\.\-\"\']{3,15})\b"#
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
}

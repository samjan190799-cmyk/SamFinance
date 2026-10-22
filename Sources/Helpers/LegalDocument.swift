import Foundation

/// Блок текста правового документа
enum LegalBlock: Equatable, Sendable {
    case title(String)
    case heading(String)
    case paragraph(String)
    case bullet(String)
}

/// Правовые тексты приложения лежат в Resources/Legal как простой Markdown: «# » — название документа, «## » — раздел,
/// «- » — пункт списка (одной строкой), остальное — абзацы. Внутри строк допустимы **жирный** и [ссылки](https://…).
/// Те же файлы служат источником для страницы политики на сайте (docs/build_privacy_page.py).
enum LegalDocument {
    static func parse(_ markdown: String) -> [LegalBlock] {
        var blocks: [LegalBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    /// Политика конфиденциальности: на русском для русского интерфейса, для остальных языков на английском.
    /// Пустой список, если файл не найден в пакете приложения.
    static func privacyPolicy(for language: AppLanguage, bundle: Bundle = .main) -> [LegalBlock] {
        let code = language == .russian ? "ru" : "en"
        guard let url = bundle.url(forResource: "PrivacyPolicy.\(code)", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parse(text)
    }
}

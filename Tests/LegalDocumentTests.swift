import XCTest
@testable import SamFinance

/// Политика конфиденциальности: разбор Markdown, наличие файлов в приложении и согласованность русской и английской версий
final class LegalDocumentTests: XCTestCase {
    private let appBundle = Bundle(for: FinanceService.self)
    private let inlineOnly = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)

    private func text(of blocks: [LegalBlock]) -> String {
        blocks.map { block -> String in
            switch block {
            case .title(let text), .heading(let text), .paragraph(let text), .bullet(let text):
                return text
            }
        }.joined(separator: "\n")
    }

    private func headings(of blocks: [LegalBlock]) -> [String] {
        blocks.compactMap { block -> String? in
            if case .heading(let text) = block { return text }
            return nil
        }
    }

    private func links(in text: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"\]\((https://[^)\s]+)\)"#)
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    func testMarkdownIsSplitIntoBlocks() {
        let blocks = LegalDocument.parse("""
        # Title

        First line
        second line.

        ## Section
        - one
        - two

        Last paragraph.
        """)
        XCTAssertEqual(blocks, [
            .title("Title"),
            .paragraph("First line second line."),
            .heading("Section"),
            .bullet("one"),
            .bullet("two"),
            .paragraph("Last paragraph.")
        ])
    }

    func testEmptyTextGivesNoBlocks() {
        XCTAssertTrue(LegalDocument.parse("").isEmpty)
        XCTAssertTrue(LegalDocument.parse("\n  \n").isEmpty)
    }

    func testPolicyIsBundledInRussianAndEnglish() {
        for language in [AppLanguage.russian, .english] {
            let blocks = LegalDocument.privacyPolicy(for: language, bundle: appBundle)
            XCTAssertFalse(blocks.isEmpty, "нет текста политики для \(language.rawValue)")
            if case .title = blocks.first {} else {
                XCTFail("политика должна начинаться с названия: \(language.rawValue)")
            }
            XCTAssertGreaterThanOrEqual(headings(of: blocks).count, 8)
        }
    }

    func testArmenianInterfaceShowsTheEnglishPolicy() {
        XCTAssertEqual(
            LegalDocument.privacyPolicy(for: .armenian, bundle: appBundle),
            LegalDocument.privacyPolicy(for: .english, bundle: appBundle)
        )
    }

    func testMissingFileGivesNoBlocks() {
        XCTAssertTrue(LegalDocument.privacyPolicy(for: .english, bundle: Bundle(for: LegalDocumentTests.self)).isEmpty)
    }

    func testBothVersionsHaveTheSameStructureAndLinks() {
        let russian = LegalDocument.privacyPolicy(for: .russian, bundle: appBundle)
        let english = LegalDocument.privacyPolicy(for: .english, bundle: appBundle)
        XCTAssertEqual(headings(of: russian).count, headings(of: english).count)
        XCTAssertEqual(links(in: text(of: russian)), links(in: text(of: english)))
        XCTAssertFalse(links(in: text(of: english)).isEmpty)
    }

    func testPolicyNamesEveryRecipientOfAIData() {
        for language in [AppLanguage.russian, .english] {
            let body = text(of: LegalDocument.privacyPolicy(for: language, bundle: appBundle))
            for name in ["Anthropic", "OpenAI", "Google", "open.er-api.com", "CVV", "Keychain"] {
                XCTAssertTrue(body.contains(name), "в политике (\(language.rawValue)) нет «\(name)»")
            }
        }
    }

    func testPolicyNamesButtonsTheWayTheAppShowsThem() throws {
        func table(_ language: String) throws -> [String: String] {
            let path = try XCTUnwrap(appBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        }
        let russian = try table("ru")
        let english = try table("en")
        let russianBody = text(of: LegalDocument.privacyPolicy(for: .russian, bundle: appBundle))
        let englishBody = text(of: LegalDocument.privacyPolicy(for: .english, bundle: appBundle))

        for key in ["reset_data", "export_data"] {
            XCTAssertTrue(russianBody.contains(try XCTUnwrap(russian[key])), "в русской политике нет подписи \(key)")
            XCTAssertTrue(englishBody.contains(try XCTUnwrap(english[key])), "в английской политике нет подписи \(key)")
        }
        XCTAssertTrue(russianBody.contains("Удалить ключ"))
        XCTAssertTrue(englishBody.contains(try XCTUnwrap(english["Удалить ключ"])))
        XCTAssertTrue(russianBody.contains("ИИ-помощник"))
        XCTAssertTrue(englishBody.contains(try XCTUnwrap(english["ИИ-помощник"])))
    }

    func testEveryParagraphIsValidInlineMarkdown() {
        for language in [AppLanguage.russian, .english] {
            for block in LegalDocument.privacyPolicy(for: language, bundle: appBundle) {
                switch block {
                case .paragraph(let text), .bullet(let text):
                    XCTAssertNoThrow(try AttributedString(markdown: text, options: inlineOnly), text)
                    XCTAssertEqual(text.components(separatedBy: "**").count % 2, 1, "непарные ** в: \(text)")
                case .title, .heading:
                    break
                }
            }
        }
    }
}

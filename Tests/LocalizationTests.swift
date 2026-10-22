import XCTest
@testable import SamFinance

/// Проверяет файлы переводов: одинаковый набор ключей, согласованные подстановки и перевод встроенных категорий.
final class LocalizationTests: XCTestCase {
    private let bundle = Bundle(for: FinanceService.self)

    private func table(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
            "нет Localizable.strings для \(language)"
        )
        let dictionary = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], "не читается файл \(language)")
        return dictionary
    }

    /// Подстановки в строке: %@, %lld, %lf, %.1f, %%
    private func placeholders(_ text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:lld|lf|@|\.1f|%)|\$\{\w+\}"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .map { $0.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
            .sorted()
    }

    func testEnglishAndArmenianHaveTheSameKeys() throws {
        let english = try table("en")
        let armenian = try table("hy")
        XCTAssertEqual(Set(english.keys), Set(armenian.keys))
        XCTAssertGreaterThan(english.count, 250)
    }

    func testRussianTableKeepsShortKeys() throws {
        let russian = try table("ru")
        let english = try table("en")
        XCTAssertFalse(russian.isEmpty)
        for key in russian.keys {
            XCTAssertNotNil(english[key], "в английском нет короткого ключа \(key)")
        }
    }

    func testPlaceholdersMatchTheKey() throws {
        for language in ["en", "hy"] {
            for (key, value) in try table(language) where key.contains("%") || key.contains("${") {
                XCTAssertEqual(placeholders(key), placeholders(value), "[\(language)] \(key)")
            }
            for (key, value) in try table(language) where !key.contains("%") && !key.contains("${") {
                XCTAssertTrue(placeholders(value).isEmpty, "[\(language)] лишняя подстановка в переводе: \(key)")
            }
        }
    }

    func testNoEmptyTranslations() throws {
        for language in ["ru", "en", "hy"] {
            for (key, value) in try table(language) {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "[\(language)] \(key)")
            }
        }
    }

    func testTranslationsAreActuallyTranslated() throws {
        let english = try table("en")
        let armenian = try table("hy")
        let cyrillic = try NSRegularExpression(pattern: "[А-Яа-яЁё]")
        for (key, value) in english where key.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil {
            XCTAssertNil(cyrillic.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), "русские буквы в английском переводе: \(key)")
        }
        for (key, value) in armenian where key.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil {
            XCTAssertNil(cyrillic.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), "русские буквы в армянском переводе: \(key)")
        }
    }

    func testBuiltInCategoriesAreTranslatedInEveryLanguage() throws {
        let english = try table("en")
        let armenian = try table("hy")
        for category in Category.defaultCategories {
            XCTAssertNotNil(english[category.name], "нет английского названия категории \(category.name)")
            XCTAssertNotNil(armenian[category.name], "нет армянского названия категории \(category.name)")
        }
    }

    func testSampleTranslationsThroughAppLanguage() {
        XCTAssertEqual(AppLanguage.russian.string("Обзор"), "Обзор")
        XCTAssertEqual(AppLanguage.english.string("Обзор"), "Overview")
        XCTAssertEqual(AppLanguage.armenian.string("Обзор"), "Ակնարկ")
        XCTAssertEqual(AppLanguage.english.string("Продукты"), "Groceries")
        XCTAssertEqual(AppLanguage.armenian.string("Продукты"), "Մթերք")
        XCTAssertEqual(AppLanguage.english.string("cards_title"), "Cards")
    }

    func testUnknownKeyReturnsItself() {
        XCTAssertEqual(AppLanguage.english.string("нет такого ключа"), "нет такого ключа")
        XCTAssertEqual(Category.displayName(for: "Моя категория"), "Моя категория")
    }

    func testLanguageSelectionIsStoredAsAppleLanguages() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "AppleLanguages")
        defer {
            if let saved {
                defaults.set(saved, forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }

        AppLanguage.select(.armenian)
        XCTAssertEqual(AppLanguage.selected, .armenian)
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["hy"])

        AppLanguage.select(.english)
        XCTAssertEqual(AppLanguage.selected, .english)
    }

    func testAppLanguageIsOneOfTheSupportedOnes() {
        XCTAssertTrue(AppLanguage.allCases.contains(AppLanguage.current))
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), ["ru", "en", "hy"])
    }

    func testBundleDeclaresTheThreeLanguages() {
        let localizations = Set(bundle.localizations)
        XCTAssertTrue(localizations.isSuperset(of: ["ru", "en", "hy"]), "\(localizations)")
    }
}

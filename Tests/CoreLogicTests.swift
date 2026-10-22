import XCTest
@testable import SamFinance

@MainActor
final class CoreLogicTests: XCTestCase {

    // MARK: - Сумма покупки из Быстрых команд

    func testPurchaseAmountParsing() throws {
        XCTAssertEqual(try XCTUnwrap(PurchaseAmountParser.parse("12 400")), 12_400, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PurchaseAmountParser.parse("12,400.50 AMD")), 12_400.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PurchaseAmountParser.parse("1,5")), 1.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(PurchaseAmountParser.parse("3 500 ֏")), 3_500, accuracy: 0.001)
    }

    func testPurchaseAmountRejectsNonNumbers() {
        XCTAssertNil(PurchaseAmountParser.parse("abc"))
        XCTAssertNil(PurchaseAmountParser.parse("0"))
        XCTAssertNil(PurchaseAmountParser.parse(""))
    }

    func testPurchaseAmountInForeignCurrencyIsConvertedToBase() throws {
        let base = CurrencyManager.shared.baseCurrency
        let converted = try XCTUnwrap(PurchaseAmountParser.parse("10 USD"))
        let expected = CurrencyService.shared.convert(amount: 10, from: .usd, to: base)
        XCTAssertEqual(converted, expected, accuracy: 0.001)
    }

    // MARK: - Периоды

    func testTimePeriodFilter() {
        let now = Date()
        let day: TimeInterval = 86_400
        XCTAssertTrue(TimePeriodFilter.today.contains(now))
        XCTAssertFalse(TimePeriodFilter.today.contains(now.addingTimeInterval(-2 * day)))
        XCTAssertTrue(TimePeriodFilter.week.contains(now.addingTimeInterval(-6 * day)))
        XCTAssertFalse(TimePeriodFilter.week.contains(now.addingTimeInterval(-8 * day)))
        XCTAssertTrue(TimePeriodFilter.month.contains(now.addingTimeInterval(-29 * day)))
        XCTAssertFalse(TimePeriodFilter.month.contains(now.addingTimeInterval(-31 * day)))
        XCTAssertTrue(TimePeriodFilter.allTime.contains(Date(timeIntervalSince1970: 0)))
    }

    func testPeriodTitlesAreNotEmpty() {
        for period in TimePeriodFilter.allCases {
            XCTAssertFalse(period.title.isEmpty)
        }
    }

    // MARK: - Категории

    func testDefaultCategoriesHaveStableUniqueIds() {
        let first = AppCategory.defaultCategories
        let second = AppCategory.defaultCategories
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
    }

    func testTransfersExistForBothTypes() {
        let transfers = AppCategory.defaultCategories.filter { $0.name == "Переводы" }
        XCTAssertEqual(Set(transfers.map(\.type)), [.expense, .income])
    }

    func testCategoryDisplayNameForBuiltInAndCustom() {
        for category in AppCategory.defaultCategories {
            XCTAssertFalse(category.displayName.isEmpty)
        }
        let custom = AppCategory(name: "Моя категория", icon: "star", colorHex: "#FFFFFF", type: .expense)
        XCTAssertEqual(custom.displayName, "Моя категория")
    }

    // MARK: - Валюты

    func testConversionIsIdentityForSameCurrency() {
        for currency in AppCurrency.allCases {
            XCTAssertEqual(CurrencyService.shared.convert(amount: 123.45, from: currency, to: currency), 123.45, accuracy: 0.0001)
        }
    }

    func testConversionRoundTrip() {
        let there = CurrencyService.shared.convert(amount: 100, from: .usd, to: .amd)
        let back = CurrencyService.shared.convert(amount: there, from: .amd, to: .usd)
        XCTAssertEqual(back, 100, accuracy: 0.001)
        XCTAssertGreaterThan(there, 100)
    }

    func testCurrencyNamesAndSymbols() {
        XCTAssertEqual(AppCurrency.amd.symbol, "֏")
        XCTAssertEqual(AppCurrency.usd.symbol, "$")
        for currency in AppCurrency.allCases {
            XCTAssertFalse(currency.displayName.isEmpty)
        }
    }

    func testAmountFormatting() {
        let manager = CurrencyManager.shared
        let saved = manager.currentCurrency
        defer { manager.currentCurrency = saved }

        manager.currentCurrency = .amd
        XCTAssertEqual(manager.formatNumber(412_300), "412 300")
        XCTAssertEqual(manager.format(412_300), "412 300 ֏")

        manager.currentCurrency = .usd
        let usd = manager.format(388.5)
        XCTAssertTrue(usd.hasPrefix("$"), usd)
    }

    func testCompactAmountUsesShortSuffixes() {
        let manager = CurrencyManager.shared
        let saved = manager.currentCurrency
        defer { manager.currentCurrency = saved }
        manager.currentCurrency = .amd

        XCTAssertTrue(compactAmount(950).contains("950"))
        XCTAssertTrue(compactAmount(148_000).contains("148"))
        XCTAssertTrue(compactAmount(1_200_000).contains("1.2") || compactAmount(1_200_000).contains("1,2"))
    }
}

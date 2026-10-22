import XCTest
@testable import SamFinance

final class SMSParserTests: XCTestCase {

    private func components(_ date: Date?) -> DateComponents? {
        date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
    }

    func testGroceryPurchaseIsParsed() throws {
        let parsed = try XCTUnwrap(SMSParser.parse(text: SMSSamples.groceryPurchase))
        XCTAssertEqual(parsed.amount, 3_500, accuracy: 0.001)
        XCTAssertEqual(parsed.currency, .amd)
        XCTAssertEqual(parsed.type, .expense)
        XCTAssertEqual(parsed.cardLast4, "0640")
        XCTAssertEqual(parsed.categoryName, "Продукты")
        XCTAssertFalse(parsed.isCategoryGuessed)
        XCTAssertFalse(parsed.isTransfer)
        XCTAssertEqual(try XCTUnwrap(parsed.balanceAfter), 120_000, accuracy: 0.001)

        let date = components(parsed.date)
        XCTAssertEqual(date?.year, 2025)
        XCTAssertEqual(date?.month, 1)
        XCTAssertEqual(date?.day, 15)
        XCTAssertEqual(date?.hour, 14)
        XCTAssertEqual(date?.minute, 32)
    }

    func testSalaryIsIncome() throws {
        let parsed = try XCTUnwrap(SMSParser.parse(text: SMSSamples.salary))
        XCTAssertEqual(parsed.type, .income)
        XCTAssertEqual(parsed.amount, 150_000, accuracy: 0.001)
        XCTAssertEqual(parsed.categoryName, "Зарплата")
    }

    func testOutgoingTransferHasCounterparty() throws {
        let parsed = try XCTUnwrap(SMSParser.parse(text: SMSSamples.transferOut))
        XCTAssertTrue(parsed.isTransfer)
        XCTAssertEqual(parsed.type, .expense)
        XCTAssertEqual(parsed.categoryName, "Переводы")
        XCTAssertEqual(parsed.counterparty?.uppercased(), "ARMEN PETROSYAN")
    }

    func testIncomingTransferIsIncome() throws {
        let parsed = try XCTUnwrap(SMSParser.parse(text: SMSSamples.transferIn))
        XCTAssertTrue(parsed.isTransfer)
        XCTAssertEqual(parsed.type, .income)
        XCTAssertEqual(parsed.amount, 25_000, accuracy: 0.001)
    }

    func testAtmWithdrawalIsOtherCategory() throws {
        let parsed = try XCTUnwrap(SMSParser.parse(text: SMSSamples.atmWithdrawal))
        XCTAssertEqual(parsed.type, .expense)
        XCTAssertEqual(parsed.categoryName, "Прочее")
        XCTAssertEqual(parsed.amount, 20_000, accuracy: 0.001)
    }

    func testDeclinedOperationIsIgnored() {
        XCTAssertNil(SMSParser.parse(text: SMSSamples.declined))
    }

    func testFreeFormIdBankMessage() throws {
        let parsed = try XCTUnwrap(SMSParser.parse(text: SMSSamples.freeForm))
        XCTAssertEqual(parsed.amount, 5_000, accuracy: 0.001)
        XCTAssertEqual(parsed.type, .expense)
        XCTAssertEqual(parsed.brandName, "IDBank")
    }

    func testOrdinaryTextWithNumbersIsNotATransaction() {
        XCTAssertNil(SMSParser.parse(text: "Hello, call me at 12345"))
        XCTAssertNil(SMSParser.parse(text: "Your verification code is 482913"))
        XCTAssertNil(SMSParser.parse(text: "Встреча в 2026 году, офис 215"))
    }

    func testBatchSplitsMessagesByBlankLine() {
        let batch = SMSParser.parseBatch(text: SMSSamples.groceryPurchase + "\n\n" + SMSSamples.salary)
        XCTAssertEqual(batch.count, 2)
    }

    func testBatchSplitsMessagesWithoutBlankLine() {
        let batch = SMSParser.parseBatch(text: SMSSamples.groceryPurchase + "\n" + SMSSamples.salary)
        XCTAssertEqual(batch.count, 2)
    }

    func testSameMessageHasSameDedupKey() throws {
        let first = try XCTUnwrap(SMSParser.parse(text: SMSSamples.groceryPurchase))
        let second = try XCTUnwrap(SMSParser.parse(text: SMSSamples.groceryPurchase))
        XCTAssertEqual(first.dedupKey, second.dedupKey)

        let other = try XCTUnwrap(SMSParser.parse(text: SMSSamples.salary))
        XCTAssertNotEqual(first.dedupKey, other.dedupKey)
    }

    func testTwoDigitYearIsReadAs2000s() throws {
        let text = """
        GNUM
        1,500.00 AMD
        4318***0640
        KFC, AM
        15.01.25 14:32
        """
        let parsed = try XCTUnwrap(SMSParser.parse(text: text))
        XCTAssertEqual(components(parsed.date)?.year, 2025)
    }

    func testMaskFromScreenshotRecognition() throws {
        // Распознанный со скриншота текст: пробел и другие звёздочки в маске карты
        let text = """
        GNUM
        2,000.00 AMD
        4318 •••0640
        CARREFOUR, AM
        15.01.2025 10:00
        """
        let parsed = try XCTUnwrap(SMSParser.parse(text: text))
        XCTAssertEqual(parsed.cardLast4, "0640")
        XCTAssertEqual(parsed.categoryName, "Продукты")
    }

    func testNumberParsing() {
        XCTAssertEqual(SMSParser.parseNumber("3,500.00"), 3_500)
        XCTAssertEqual(SMSParser.parseNumber("12.5"), 12.5)
        XCTAssertEqual(SMSParser.parseNumber("1 234,50"), 1_234.5)
        XCTAssertEqual(SMSParser.parseNumber("3,500"), 3_500)
        XCTAssertNil(SMSParser.parseNumber("abc"))
    }
}

import XCTest
import SwiftUI
@testable import SamFinance

/// Ввод реквизитов карты: форматирование, проверки и определение платёжной системы
final class CardInputTests: XCTestCase {

    func testDigitsKeepsOnlyNumbers() {
        XCTAssertEqual(CardInput.digits("4111-1111 1111_1111abc"), "4111111111111111")
        XCTAssertEqual(CardInput.digits(""), "")
    }

    func testNumberIsGroupedByFour() {
        XCTAssertEqual(CardInput.formatNumber("4111111111111111"), "4111 1111 1111 1111")
        XCTAssertEqual(CardInput.formatNumber("41111"), "4111 1")
        XCTAssertEqual(CardInput.formatNumber("4111"), "4111")
        XCTAssertEqual(CardInput.formatNumber("4111 1111-1111_1111"), "4111 1111 1111 1111")
        XCTAssertEqual(CardInput.formatNumber(""), "")
    }

    func testLongNumberIsCutAtNineteenDigits() {
        XCTAssertEqual(CardInput.formatNumber("4111111111111111234"), "4111 1111 1111 1111 234")
        XCTAssertEqual(CardInput.formatNumber("41111111111111112345678"), "4111 1111 1111 1111 234")
    }

    func testAmexNumberHasItsOwnGrouping() {
        XCTAssertEqual(CardInput.formatNumber("378282246310005"), "3782 822463 10005")
        XCTAssertEqual(CardInput.formatNumber("3782822463100059999"), "3782 822463 10005")
        XCTAssertEqual(CardInput.formatNumber("123456789012345", network: .amex), "1234 567890 12345")
    }

    func testExpiryIsFormattedWhileTyping() {
        XCTAssertEqual(CardInput.formatExpiry(""), "")
        XCTAssertEqual(CardInput.formatExpiry("0"), "0")
        XCTAssertEqual(CardInput.formatExpiry("08"), "08")
        XCTAssertEqual(CardInput.formatExpiry("082"), "08/2")
        XCTAssertEqual(CardInput.formatExpiry("0829"), "08/29")
        XCTAssertEqual(CardInput.formatExpiry("08/29"), "08/29")
        XCTAssertEqual(CardInput.formatExpiry("082999"), "08/29")
    }

    func testExpiryIsNormalizedOrRejected() {
        XCTAssertEqual(CardInput.normalizedExpiry("0829"), "08/29")
        XCTAssertEqual(CardInput.normalizedExpiry("08/29"), "08/29")
        XCTAssertNil(CardInput.normalizedExpiry("1329"))
        XCTAssertNil(CardInput.normalizedExpiry("0029"))
        XCTAssertNil(CardInput.normalizedExpiry("082"))
        XCTAssertNil(CardInput.normalizedExpiry("08/2029"))
        XCTAssertNil(CardInput.normalizedExpiry(""))
    }

    func testCardIsValidUntilTheEndOfItsMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2029, month: 8, day: 15)))

        XCTAssertFalse(CardInput.isExpired("08/29", now: now, calendar: calendar))
        XCTAssertFalse(CardInput.isExpired("12/29", now: now, calendar: calendar))
        XCTAssertFalse(CardInput.isExpired("01/31", now: now, calendar: calendar))
        XCTAssertTrue(CardInput.isExpired("07/29", now: now, calendar: calendar))
        XCTAssertTrue(CardInput.isExpired("12/28", now: now, calendar: calendar))
        // Неверный срок «истёкшим» не считается: об ошибке скажет проверка формата
        XCTAssertFalse(CardInput.isExpired("13/29", now: now, calendar: calendar))
    }

    func testNumberLength() {
        XCTAssertFalse(CardInput.isValidLength(String(repeating: "1", count: 12)))
        XCTAssertTrue(CardInput.isValidLength(String(repeating: "1", count: 13)))
        XCTAssertTrue(CardInput.isValidLength(String(repeating: "1", count: 16)))
        XCTAssertTrue(CardInput.isValidLength(String(repeating: "1", count: 19)))
        XCTAssertFalse(CardInput.isValidLength(String(repeating: "1", count: 20)))
    }

    func testLuhnCheck() {
        XCTAssertTrue(CardInput.passesLuhn("4111111111111111"))
        XCTAssertTrue(CardInput.passesLuhn("5555555555554444"))
        XCTAssertTrue(CardInput.passesLuhn("378282246310005"))
        XCTAssertFalse(CardInput.passesLuhn("4111111111111112"))
        XCTAssertFalse(CardInput.passesLuhn("4111 1111 1111 1111"))
        XCTAssertFalse(CardInput.passesLuhn("12345678901"))
        XCTAssertFalse(CardInput.passesLuhn(""))
    }

    func testNetworkIsDetectedByNumberPrefix() {
        XCTAssertEqual(CardNetwork.detect(from: "4111"), .visa)
        XCTAssertEqual(CardNetwork.detect(from: "4"), .visa)
        XCTAssertEqual(CardNetwork.detect(from: "5105105105105100"), .mastercard)
        XCTAssertEqual(CardNetwork.detect(from: "55"), .mastercard)
        XCTAssertEqual(CardNetwork.detect(from: "2221000000000009"), .mastercard)
        XCTAssertEqual(CardNetwork.detect(from: "2720"), .mastercard)
        XCTAssertEqual(CardNetwork.detect(from: "2200"), .mir)
        XCTAssertEqual(CardNetwork.detect(from: "2204123412341234"), .mir)
        XCTAssertEqual(CardNetwork.detect(from: "340000"), .amex)
        XCTAssertEqual(CardNetwork.detect(from: "370000"), .amex)
    }

    func testUnknownPrefixHasNoNetwork() {
        XCTAssertNil(CardNetwork.detect(from: ""))
        XCTAssertNil(CardNetwork.detect(from: "5"))
        XCTAssertNil(CardNetwork.detect(from: "22"))
        XCTAssertNil(CardNetwork.detect(from: "50"))
        XCTAssertNil(CardNetwork.detect(from: "56"))
        XCTAssertNil(CardNetwork.detect(from: "2205"))
        XCTAssertNil(CardNetwork.detect(from: "2721"))
        XCTAssertNil(CardNetwork.detect(from: "6011"))
    }

    func testPresetsAreUniqueAndMatchByColors() {
        let ids = CardPreset.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        for preset in CardPreset.all {
            XCTAssertEqual(preset.colors.count, 2)
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertEqual(CardPreset.matching(preset.colors)?.id, preset.id)
        }
        // Регистр букв в цвете не важен
        XCTAssertEqual(CardPreset.matching(["#c6f432", "#b2e01e"])?.id, "lime")
        XCTAssertNil(CardPreset.matching(["#123456", "#654321"]))
    }

    func testTitlesAreNotEmpty() {
        for network in CardNetwork.allCases {
            XCTAssertFalse(network.title.isEmpty)
        }
        for pattern in CardPattern.allCases {
            XCTAssertFalse(pattern.title.isEmpty)
        }
        let titles = CardSymbol.all.map { CardSymbol.title($0) }
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertFalse(CardSymbol.title(nil).isEmpty)
    }

    func testColorRoundTripsThroughHex() {
        XCTAssertEqual(Color(hex: "#C6F432").hexString, "#C6F432")
        XCTAssertEqual(Color(hex: "#000000").hexString, "#000000")
        XCTAssertEqual(Color(hex: "#FFFFFF").hexString, "#FFFFFF")
    }

    func testColorOutsideSRGBIsClamped() {
        let wide = Color(.sRGB, red: 1.2, green: -0.1, blue: 0.5, opacity: 1)
        XCTAssertEqual(wide.hexString, "#FF0080")
    }
}

/// Сохранение карты с оформлением и обратная совместимость со старыми данными
@MainActor
final class CardCustomizationTests: XCTestCase {
    private var service: FinanceService { FinanceService.shared }

    // Вызов super.setUp() здесь не нужен (он пустой) и не компилируется в Swift 6 для MainActor-классов
    override func setUp() async throws {
        service.resetAllData()
    }

    override func tearDown() async throws {
        service.resetAllData()
    }

    private func makeCard(last4: String = "1111", balance: Double = 1_000, updatedAt: Date? = nil) -> Card {
        Card(last4: last4, holderName: "TEST USER", balance: balance, colorHex: "#2A2B30", gradientColors: ["#2A2B30", "#1C1D21"], balanceUpdatedAt: updatedAt)
    }

    func testOldCardWithoutDesignFieldsStillDecodes() throws {
        let json = """
        {"id":"5A3F1C00-0000-4000-8000-000000000001","last4":"0640","holderName":"TEST USER","balance":1000,\
        "type":"Main","colorHex":"#C6F432","gradientColors":["#C6F432","#B2E01E"],"isFrozen":false,"expiryDate":"08/29"}
        """
        let card = try JSONDecoder().decode(Card.self, from: Data(json.utf8))
        XCTAssertEqual(card.last4, "0640")
        XCTAssertNil(card.bankName)
        XCTAssertNil(card.network)
        XCTAssertNil(card.pattern)
        XCTAssertNil(card.symbol)
    }

    func testUnknownDesignValuesDoNotBreakDecoding() throws {
        let json = """
        {"id":"5A3F1C00-0000-4000-8000-000000000002","last4":"0640","holderName":"TEST USER","balance":1000,\
        "type":"Main","colorHex":"#C6F432","gradientColors":["#C6F432","#B2E01E"],"isFrozen":false,"expiryDate":"08/29",\
        "network":"unionpay","pattern":"stripes","symbol":"airplane","bankName":"Ameria"}
        """
        let card = try JSONDecoder().decode(Card.self, from: Data(json.utf8))
        XCTAssertNil(card.network)
        XCTAssertNil(card.pattern)
        XCTAssertEqual(card.symbol, "airplane")
        XCTAssertEqual(card.bankName, "Ameria")
    }

    func testDesignSurvivesEncodingRoundTrip() throws {
        let card = Card(
            last4: "4444", holderName: "TEST USER", balance: 10, type: "Travel", colorHex: "#FF9A3D",
            gradientColors: ["#FF9A3D", "#E8366B"], expiryDate: "01/31",
            bankName: "Ameria", network: .arca, pattern: .waves, symbol: "airplane"
        )
        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(Card.self, from: data)
        XCTAssertEqual(decoded, card)
    }

    func testUpdateCardChangesDesignAndKeepsIdentity() throws {
        var card = makeCard()
        service.addCard(card, number: "")

        card.type = "Путешествия"
        card.bankName = "Ameria"
        card.network = .arca
        card.pattern = .rings
        card.symbol = "airplane"
        card.gradientColors = ["#3DDC97", "#0F8F6A"]
        card.colorHex = "#3DDC97"
        service.updateCard(card)

        XCTAssertEqual(service.cards.count, 1)
        let saved = try XCTUnwrap(service.cards.first)
        XCTAssertEqual(saved.id, card.id)
        XCTAssertEqual(saved.type, "Путешествия")
        XCTAssertEqual(saved.bankName, "Ameria")
        XCTAssertEqual(saved.network, .arca)
        XCTAssertEqual(saved.pattern, .rings)
        XCTAssertEqual(saved.symbol, "airplane")
        XCTAssertEqual(saved.gradientColors, ["#3DDC97", "#0F8F6A"])
    }

    func testUpdatedDesignSurvivesReload() throws {
        var card = makeCard()
        service.addCard(card, number: "")
        card.pattern = .dots
        card.bankName = "IDBank"
        service.updateCard(card)

        let reloaded = FinanceService()
        let saved = try XCTUnwrap(reloaded.cards.first { $0.id == card.id })
        XCTAssertEqual(saved.pattern, .dots)
        XCTAssertEqual(saved.bankName, "IDBank")
    }

    func testUpdatingUnknownCardDoesNothing() {
        service.updateCard(makeCard())
        XCTAssertTrue(service.cards.isEmpty)
    }

    func testManualBalanceChangeMovesReferencePoint() throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        var card = makeCard(balance: 100, updatedAt: reference)
        service.addCard(card, number: "")

        // Баланс не менялся: точка отсчёта остаётся прежней
        card.type = "Другое название"
        service.updateCard(card)
        XCTAssertEqual(try XCTUnwrap(service.cards.first).balanceUpdatedAt, reference)

        // Баланс поправили вручную: старые СМС его уже не перепишут
        card.balance = 250
        service.updateCard(card)
        let saved = try XCTUnwrap(service.cards.first)
        XCTAssertEqual(saved.balance, 250, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(saved.balanceUpdatedAt), reference)
    }

    func testEditingNumberUpdatesLastDigits() throws {
        let card = makeCard(last4: "1111")
        service.addCard(card, number: "4111111111111111")
        try XCTSkipUnless(service.cardNumber(for: card.id) != nil, "Keychain недоступен в этой среде")

        service.updateCard(card, number: "5555 5555 5555 4444")
        XCTAssertEqual(service.cardNumber(for: card.id), "5555555555554444")
        XCTAssertEqual(try XCTUnwrap(service.cards.first).last4, "4444")

        // Без нового номера прежний остаётся на месте (правят ту карту, что сейчас в списке)
        var current = try XCTUnwrap(service.cards.first)
        current.type = "Только название"
        service.updateCard(current)
        XCTAssertEqual(service.cardNumber(for: card.id), "5555555555554444")
        XCTAssertEqual(try XCTUnwrap(service.cards.first).last4, "4444")
        XCTAssertEqual(try XCTUnwrap(service.cards.first).type, "Только название")
    }
}

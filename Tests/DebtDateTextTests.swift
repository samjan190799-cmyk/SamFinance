import XCTest
@testable import SamFinance

/// Срок в строке долга: год показывается только тогда, когда срок не в этом году
final class DebtDateTextTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    /// Полдень по Гринвичу и середина месяца: в любом часовом поясе день и год не меняются
    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    func testDueDateInCurrentYearHasNoYear() throws {
        let text = DebtDateText.due(try date(2026, 11, 4), now: try date(2026, 11, 7), calendar: calendar)
        XCTAssertFalse(text.contains("2026"), text)
    }

    func testDueDateInNextYearShowsYear() throws {
        // 15 октября следующего года: без года такой срок выглядел бы как давно просроченный
        let text = DebtDateText.due(try date(2027, 10, 15), now: try date(2026, 11, 7), calendar: calendar)
        XCTAssertTrue(text.contains("2027"), text)
    }

    func testDueDateInPreviousYearShowsYear() throws {
        let text = DebtDateText.due(try date(2025, 12, 15), now: try date(2026, 1, 20), calendar: calendar)
        XCTAssertTrue(text.contains("2025"), text)
    }
}
